# tools/harness/slots.psd1 - the rig's private Workshop "slot" items (WP-H-07).
#
# A slot is a private item the rig owns. stage-build.ps1 overwrites its content with a locally built mod so a
# plan can test an unshipped build; real mod folders are never written. Only the ids listed here may be staged
# into; an empty Id means the item has not been created yet (tools/harness/New-RigSlotItems.ps1 prints the
# one-time create and subscribe commands, then put the published id here).
# Pure data file: no executable statements.
@{
    Slots = @(
        @{ Slot = 1; Id = '3840301411'; Title = 'VT2 Rig Slot 1' }
        @{ Slot = 2; Id = '3840301616'; Title = 'VT2 Rig Slot 2' }
        @{ Slot = 3; Id = '3840301649'; Title = 'VT2 Rig Slot 3' }
        @{ Slot = 4; Id = '3840301687'; Title = 'VT2 Rig Slot 4' }
        @{ Slot = 5; Id = '3840301709'; Title = 'VT2 Rig Slot 5' }
        @{ Slot = 6; Id = '3840301739'; Title = 'VT2 Rig Slot 6' }
    )
}
