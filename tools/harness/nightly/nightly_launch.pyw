"""Windowless start of the rig's nightly run (WP-H-11 step 4).

The scheduled task starts this file with pythonw.exe, which has no console. It starts
tools/harness/Invoke-NightlyRun.ps1 with pwsh and CREATE_NO_WINDOW, so no console window ever
appears (pwsh -WindowStyle Hidden still flashes one). Arguments after the script path are passed
through. Output goes to <RigRoot>\\nightly.log through the script itself.
"""
import os
import subprocess
import sys

CREATE_NO_WINDOW = 0x08000000


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    script = os.path.join(here, "..", "Invoke-NightlyRun.ps1")
    pwsh = os.environ.get("VT2_RIG_PWSH", "pwsh.exe")
    command = [pwsh, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script] + sys.argv[1:]
    return subprocess.call(command, creationflags=CREATE_NO_WINDOW, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    sys.exit(main())
