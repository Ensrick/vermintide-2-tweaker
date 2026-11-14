import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
BS = chr(92)
def rep(old, new, count=1):
    global s
    old = old.replace('<BS>', BS); new = new.replace('<BS>', BS)
    n = s.count(old)
    if n != count:
        print('MISMATCH', n, 'expected', count, '::', old[:70]); sys.exit(1)
    s = s.replace(old, new)

rep("Three supervised experiments of about ten minutes each decide them (E1, E2, E3).",
    "Three supervised experiments decide them: E1 and E2 take about ten minutes each, E3 needs a first driver build.")
rep("The game is not installed right now (Steam shows 32 MB of 45 GB downloaded), so nothing about the retail exe could be checked.",
    "The game was not installed during this audit (Steam was still downloading: 29.8 of 45.4 GB at the last check), so nothing about the retail exe could be checked.")
rep("the eleven memory notes named in the brief plus", "the seven memory notes named in the brief plus")
rep("Severity counts: S0 = 1, S1 = 4, S2 = 4, S3 = 1.", "Severity counts: S0 = 1, S1 = 3, S2 = 5, S3 = 1.")
rep("**F5 (S1). The planned inbound channel", "**F5 (S2). The planned inbound channel")
rep("LOG-A: `StateTitleScreenMain` 22:45:09.912, `StateTitleScreenInitNetwork` 22:45:09.925, keep 22:45:22.969.",
    "LOG-A:5096, 5179 (`StateTitleScreenMain` to `StateTitleScreenInitNetwork` in 13 ms); LOG-A:6532, 6542 (the load-save step starts 17 ms after the backend-ready line, so no click happened); LOG-A:6806 keep.")
old6_start = "2. **Build the run folder** "
i = s.index(old6_start); j = s.index("3. **Record identity**")
new6 = ("2. **Prepare the profile and the run folder.** Two harness-owned folders outside the repo, for example `C:<BS>Users<BS><user><BS>.claude<BS>vt2-harness<BS>profile<BS>` (kept between runs) and `...<BS>vt2-harness<BS>runs<BS><utc-stamp>-<nonce><BS>` (evidence for one run). "
        "The profile folder plays the part of the user profile: it holds `AppData<BS>Roaming<BS>Fatshark<BS>Vermintide 2<BS>` with (a) a `user_settings.config` regenerated for every run: low graphics, `screen_resolution = [1280 720]`, `fullscreen = false`, `borderless_fullscreen = false`, `max_fps = 30`, all volumes 0, the `mods` list holding only VMF, the mods the plan needs, and the driver last, `mods_settings` holding VMF logging-to-log plus every option value the plan asks for, and the key `vt2_test_plan`; "
        "(b) a copy of the owner's `save_data.sav`, refreshed before each run, so first-run flows (tutorial, gamma) do not trigger; (c) the shader cache the game builds there once (about 200 MB in the owner's profile), which is why the profile is kept and not recreated per run. "
        "Retention: keep the last 20 run folders and every run cited on an issue; a run folder is logs and small tables (a few MB). Check free space under the owner's storage rules before the first run.\n")
s = s[:i] + new6.replace('<BS>', BS) + s[j:]
rep("| Hang | Heartbeat and stage time caps; the engine's own deadlock timer is on (`deadlock_timeout = 15` in `user_settings.config:16`). |",
    "| Hang | Heartbeat and stage time caps, enforced from outside the game. The profile also carries the game's `deadlock_timeout` setting (`user_settings.config:16`; its effect is unverified). |")
rep("set the lobby private to all but the client (row 66), print its lobby id.",
    "set the game private (row 66), print its lobby id.")
rep("BytesDownloaded 32650672 of 45379541120, TargetBuildID 25901688;",
    "BytesDownloaded 32650672 of 45379541120 when first read (29779703584 at the end of the audit), TargetBuildID 25901688;")
rep("8. **Collect** into the run folder: console log, crash dump,",
    "8. **Collect** into the run folder (moved out of the profile): console log, crash dump,")
open(p, 'w', encoding='utf-8', newline='\n').write(s)
bad = [hex(ord(c)) for c in set(s) if ord(c) < 32 and c not in '\n\t']
print('ok', len(s), 'ctrl:', bad)
