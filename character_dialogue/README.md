# Character Dialogue

Character Dialogue is a VMF mod for browsing and controlling individual Vermintide 2 voice lines. It uses stable Wwise event IDs, persists only user overrides, and leaves unmodified dialogue on the vanilla path.

The full catalogue is generated offline from `Vermintide-2-Source-Code/dialogues/generated/*.lua`:

```powershell
py -3 tools/dialogue/generate_catalogue.py --source C:\path\to\Vermintide-2-Source-Code\dialogues\generated --output character_dialogue\scripts\mods\character_dialogue\character_dialogue_catalogue.lua
```

Preview playback is local-only. Natural dialogue selection remains host-authoritative and sends only vanilla dialogue IDs/indexes through the existing engine RPC.

Some Chaos Wastes dialogue banks are not resident in the keep or Adventure
missions. Character Dialogue resolves only the empirically audited Morris
source family to Fatshark's shared `resource_packages/dlcs/morris_ingame`
package. It loads that single package asynchronously on demand under a private
reference, keeps only the latest pending click, and releases the package when
preview ownership ends. Unmapped dialogue continues through vanilla Wwise
playback without speculative package loading.

Each generated catalogue tuple also carries Fatshark's authored clip duration.
The Dialogue tab combines that duration with `WwiseWorld.get_playing_elapsed`
for its active-row progress bar; Wwise playback state remains the completion
authority. Preview position is never inferred for every catalogue row.

Automatic isolation is an Apply-gated setting in the custom Dialogue tab.
`_cd_isolation_setting.lua` owns its VMF callbacks and direct API setter; the
entry module owns audio reconciliation. API v6 adds schema-1
`isolation_setting = { version=1, setting_id="auto_isolation" }` without changing
existing playback/get/set APIs. GUI Dev maps this exact setting to CD's VMF
owner, persists with `notify=false`, then calls `on_settings_batch_changed`
once. Ordinary VMF notification and the direct setter reconcile once too.
The custom browser has no tab-profile or DEFAULT contract; those controls are
hidden rather than saving an incomplete or foreign profile.
