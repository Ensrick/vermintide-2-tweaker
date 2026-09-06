# Shared subordinate lock. Callers already hold the owning machine transaction.
# Recovery and publication both fetch GitHub afresh after acquiring this lock.
function Enter-VtGitHubReleaseMutationMutex {
    param([string]$MutexName = 'Global\VT2_GitHubReleaseMutation')
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    try {
        $held = $false
        try { $held = $mutex.WaitOne([TimeSpan]::FromMinutes(15)) }
        catch [System.Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) {
            throw 'Timed out waiting for the machine-global GitHub release mutation lock. Another ship is still preparing or updating the shared release manifest.'
        }
        return $mutex
    }
    catch { $mutex.Dispose(); throw }
}
