# cos_la_apply_req silent-drop investigation

## Root cause (one line)

`mod:network_send(rpc, "server", payload)` does not exist in VMF. The string
`"server"` is treated as a literal `peer_id`, fails the
`_vmf_users[peer_id]` lookup inside `convert_names_to_numbers`, and
`send_rpc_vmf_data` silently returns without putting any packet on the wire.

## Evidence

### VMF source (`vmf/scripts/mods/vmf/modules/core/network.lua`, public GitHub)

```lua
VMFMod.network_send = function (self, rpc_name, recipient, ...)
    if recipient == "all" then
        for peer_id, _ in pairs(_vmf_users) do
            send_rpc_vmf_data(peer_id, self:get_name(), rpc_name, ...)
        end
        send_rpc_vmf_data_local(self:get_name(), rpc_name, ...)
    elseif recipient == "others" then
        for peer_id, _ in pairs(_vmf_users) do
            send_rpc_vmf_data(peer_id, self:get_name(), rpc_name, ...)
        end
    elseif recipient == "local" or recipient == Network.peer_id() then
        send_rpc_vmf_data_local(self:get_name(), rpc_name, ...)
    else
        send_rpc_vmf_data(recipient, self:get_name(), rpc_name, ...)
    end
end
```

The four recipient forms VMF understands are: `"all"`, `"others"`, `"local"`,
or a literal numeric/string peer_id. **There is no `"server"` branch.**

Downstream, `send_rpc_vmf_data` ultimately calls
`convert_names_to_numbers(peer_id, mod_name, rpc_name)`, which looks up the
peer in `_vmf_users` (populated by the ping/pong handshake) and returns
`nil, nil` for an unknown peer. Both `mod_number` and `rpc_number` come back
nil and the send body is skipped — no error, no log, no packet.

### Verified against the VMF bundle on disk

Extracted `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\1369573612\98161451961848df.mod_bundle`
to `C:\Users\danjo\Temp\vmf_unpack_raw\` with the VT2 unpacker. The network
module is `08663A2FC489ECB2.lua`
(`@scripts/mods/vmf/modules/core/network.lua`). Bytecode strings confirm the
same shape: `local`, `others`, `all`, `_vmf_users`, `send_rpc_vmf_data`,
`send_rpc_vmf_data_local`, `convert_names_to_numbers`, `is_rpc_registered`,
plus the unique error string `attempt to send non-registered` (used on the
sender-side `is_rpc_registered` precheck). No `server`/`host` literal exists
in the module.

### Call sites in cosmetics_tweaker.lua

```
3848:  mod:network_send("cos_la_apply",        "all",    { ... })   -- HOST broadcast — OK
3861:  mod:network_send("cos_la_apply_req",    "server", { ... })   -- CLIENT → host — BROKEN
4075:  mod:network_send("cos_la_apply",        "all",    { ... })   -- HOST broadcast — OK
4287:  mod:network_send("cos_glow_apply",      "all",    { ... })   -- HOST broadcast — OK
4292:  mod:network_send("cos_glow_apply_req",  "server", { ... })   -- CLIENT → host — BROKEN
4320:  mod:network_send("cos_glow_apply",      "all",    { ... })   -- HOST broadcast — OK
4347:  mod:network_send("cos_glow_apply",      "all",    { ... })   -- HOST broadcast — OK
```

Two send sites use `"server"`. Both are the only client→host paths in the
mod. Every "directed-to-joiner" hot-join replay at line 4717 already uses a
**literal `peer_id`** (the joiner's ID from `players_added`) — that path
works for the exact same reason: VMF's `else` branch routes a real peer_id
correctly.

### Log evidence

- PC-A (CLIENT): `[cos_la_apply emit] CLIENT->req ...` fires (we're past
  `_is_local_server() == false` and reached the broken `network_send` line).
  Zero `[cos_la_apply recv]`, zero `[CACHE WRITE]` — packet never returns
  because it was never sent.
- Lyndsey (HOST): bridge registered 35 items, `cos_la_apply_req` handler is
  registered (otherwise her own host-mode emit at line 3848 wouldn't work),
  yet she logs zero `[cos_la_apply recv]` from PC-A. The packet never
  arrived because PC-A never transmitted it.
- Glow hot-join replay (HOST→targeted-peer at line 4717) works on Lyndsey's
  side because that path uses a literal `peer_id`, exercising VMF's `else`
  branch correctly.

## Hypothesis verdicts

| # | Hypothesis | Verdict |
|---|---|---|
| H1 | VMF version/hash mismatch silently drops RPCs | **Refuted.** VMF's mod/RPC dictionary is built by ping/pong over `_shared_mods_map` / `_shared_rpcs_map`. There is no per-mod content-hash check; only the mod name + rpc name need to match. Both peers register `cos_la_apply_req` under the same names, so this is fine. The mod/rpc shared map is also irrelevant when the sender bails before the lookup is even consulted with a valid peer_id. |
| H2 | Sanctioned-status / permissioning | **Refuted.** VMF mods don't have a "sanctioned" gate for outbound RPCs; the only sanctioning concept in VT2 is realm selection (modded vs official), which is already in effect once both peers are in the same lobby. |
| H3 | Lyndsey's handlers didn't register | **Refuted.** Her bridge is up, her own `cos_la_apply` "all" broadcast loops back (host-as-sender path uses the same `network_register` table). If her registration had failed the host emit at line 3848 would also fail. |
| H4 | GameSession not propagating mod RPCs | **Refuted.** Mod RPCs ride `rpc_chat_message` (see `08663A2FC489ECB2.lua` strings: `rpc_chat_message`, `Network`, `peer_id`), not the GameSession. The chat-RPC channel is up the moment both peers can talk in chat. |
| H5 | `_is_local_server()` mis-detection | **Refuted by logs.** PC-A logs `CLIENT->req`, Lyndsey runs her host-only hot_join_sync — roles are detected correctly. |
| **NEW** | **VMF has no `"server"` recipient** | **Confirmed root cause.** See above. |

## Why this passed earlier QA

The bug was masked by the only previously-tested topology where the local
machine was the host. Host-side `_send_la_apply` short-circuits to the
direct `"all"` broadcast (line 3848); the broken `"server"` line at 3861 is
only reached when the local peer is a client. PC-A→PC-B sessions during
earlier dev had PC-A as host on every cos-tweaker iteration prior to
v0.9.0.7-hotfix; the first session where Lyndsey hosted and PC-A was a
client is exactly the scenario where this surfaces.

## Patch

Two one-line changes (plus a guard against a nil host peer at startup):

```lua
-- cosmetics_tweaker.lua:3861 (LA path)
-    mod:network_send("cos_la_apply_req", "server", {
+    local host = _host_peer_id()
+    if not host then return end   -- network manager not ready yet
+    mod:network_send("cos_la_apply_req", host, {
         slot         = slot_name,
         kind         = kind,
         armoury_key  = armoury_key,
         vanilla_key  = vanilla_key,
     })

-- cosmetics_tweaker.lua:4292 (glow path)
-        mod:network_send("cos_glow_apply_req", "server", {
+        local host = _host_peer_id()
+        if not host then return end
+        mod:network_send("cos_glow_apply_req", host, {
             state = state,
         })
```

`_host_peer_id()` already exists at line 3780 and resolves to
`Managers.state.network.server_peer_id` — the literal peer_id of the dedicated
or hosting peer, exactly what VMF's `else` branch expects.

### Defensive belt-and-suspenders (optional but cheap)

If host detection ever returns a stale peer_id during a transition window,
the request silently no-ops on the wire (peer not in `_vmf_users`). Add a
soft retry: on emit, queue the payload into `_la_apply_req_pending` and
re-send from `mod.update` for ~2 seconds if no echo of `cos_la_apply` for
the same `(slot, armoury_key)` has come back via the receiver at line 4115.
This protects against the host-peer-id-not-yet-known race at level
transitions without affecting the steady-state path.

### Why not "fix VMF"

Adding a `"server"` recipient to VMF is the right long-term fix and would
make every consumer mod symmetric with the documented `"all"` / `"others"` /
`"local"` set, but it requires a VMF release and a hard-dep bump. Calling
`network_send(..., _host_peer_id(), ...)` is the supported pattern as of
current VMF and used by other mods (it's the same shape the working
hot-join replay at line 4717 already uses for targeted sends).

## Verification matrix after patch

| Scenario | Sender | Receiver | Expected log |
|---|---|---|---|
| Client picks LA cosmetic | PC-A (client) | Host | PC-A `CLIENT->req`, host `[cos_la_apply_req] recv from <PC-A>`, host `cos_la_apply emit (broadcast)`, all peers `[cos_la_apply recv]` + `[CACHE WRITE]` |
| Host picks LA cosmetic | Host | All | Host `HOST broadcast`, all `[cos_la_apply recv]` (unchanged from current behavior) |
| Hot-join client | Host | Joining client | Host `[hot-join replay] sent N cos_la_apply entries targeted at joiner=<PEER>` (unchanged) |
| Client toggles glow | PC-A (client) | Host | Symmetric to LA path on `cos_glow_apply_req` |
