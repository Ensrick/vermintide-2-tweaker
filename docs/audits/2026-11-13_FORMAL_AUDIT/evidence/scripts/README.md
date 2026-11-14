# Audit evidence scripts

Scripts the auditors wrote to produce the figures quoted in the stream reports one folder up (`A1.md` to `E1.md`). The prefix of a file name is the stream that owns it. This folder is an archive: it records how a figure was measured on 2026-11-13 and is not maintained.

Two things differ from the auditors' working copies:

- **Lua files end in `.lua.txt`.** The repository's Lua gates treat every `*.lua` below a folder named `scripts` as mod source, and `qa/check_logging.ps1` blocks on the offline `printf` stubs that two of these files carry. To run one, copy it and remove the `.txt` suffix.
- **Machine paths and account names are placeholders**, for example `<repos>`, `<audit-workspace>` and `%USERPROFILE%`.

For the same reason two prototype files under `rig/bootstrap/package-src/` in this audit folder carry a `.txt` suffix: `itemV2.cfg.txt` and `vt2_rig_driver.lua.txt`.
