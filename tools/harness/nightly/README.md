# Nightly rig run (WP-H-11 step 4)

The owner decides whether the rig runs at night. Nothing here is registered or enabled by an agent.

| File | What it is |
|---|---|
| `../Invoke-NightlyRun.ps1` | The nightly run: smoke and sweep plans through `run.ps1`, a report in `qa/runtime/reports/nightly-<date>.md`, the patch-day canary when the game build changed. Publishes nothing. |
| `nightly_launch.pyw` | Started by the task with `pythonw.exe` (no console); starts the script with `pwsh` and `CREATE_NO_WINDOW`, so no console window ever appears. |
| `Vt2RigNightly.task.xml` | The task definition: daily 03:30, only while the owner is logged on, not on battery, at most 4 hours, one instance. `<Enabled>false</Enabled>`. |
| `Register-NightlyTask.ps1` | Run by the owner: fills the paths and registers the task **disabled**. |

When it refuses: the script ends at once (one line in `<RigRoot>\nightly.log`, no report) when
- the last keyboard or mouse input is less than 30 minutes old (`GetLastInputInfo`; `-MinIdleMinutes`);
- a process in `tools/harness/busy-processes.txt` runs, or any process started from a Steam library's `steamapps\common` folder (every Steam game, Spider-Man included);
- and it checks again before each plan, so coming back to the machine stops the rest of the night.

`run.ps1` keeps its own refusals for every plan (free RAM, Steam not running, the rig lock).

To turn it on, as the owner, from this checkout:

```powershell
pwsh -NoProfile -File tools/harness/nightly/Register-NightlyTask.ps1 -RigRoot $env:USERPROFILE\.claude\vt2-harness
Enable-ScheduledTask -TaskName Vt2RigNightly      # the deliberate second step
```

To turn it off again: `Disable-ScheduledTask -TaskName Vt2RigNightly`, or `Unregister-ScheduledTask -TaskName Vt2RigNightly`.

The report goes into `qa/runtime/reports/` of the checkout that holds these scripts (`-ReportDir` overrides it), so register the task from a checkout no one else commits from; nothing commits the report by itself.
