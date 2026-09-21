# Bounded incident exceptions for the deployed-source authority
# (tools/verify/live_test_source_authority.ps1, Get-VtCardSourceAuthority).
#
# GRAMMAR - every entry carries exactly these seven non-empty strings:
#   Incident     '#<issue>'  the GitHub incident issue that owns the exception
#   ModId        canonical inventory ModId (tools/mod-inventory.psd1)
#   ModTree      full lowercase 40-hex hash of the deployed <mod>/scripts/mods
#                tree: git rev-parse <source_commit>:<dir>/scripts/mods
#   RelativePath repo-relative forward-slash Lua path the detector fires on
#   Detector     'global-printf-mutation' (the only suspendable detector)
#   ExpiresUtc   'yyyy-MM-ddTHH:mm:ssZ'; the entry is live strictly before it
#   Reason       why the throw is suspended and what removes the entry
#
# SEMANTICS: an entry suspends one fail-closed throw only when ModId, ModTree,
# RelativePath and Detector all match the deployed record exactly and the
# current UTC time is before ExpiresUtc. Any other tree (the next ship of that
# mod), path, mod or detector, or an elapsed expiry, restores the unchanged
# record-wide throw. Nothing here weakens any other detector. A malformed
# entry fails every authority run. The authority records each applied entry
# as IncidentExceptions and warns once; check-lifecycle-cardinality.ps1 prints
# the same line in its report.
#
# LIFECYCLE: entries are temporary and pinned to one deployed tree. Remove an
# entry with a follow-up PR as soon as the clean tree is deployed; an expired
# entry is dead weight, never a standing bypass. Keep Exceptions = @() when no
# incident is open.

@{
    Exceptions = @()
}
