# release-identity.ps1 - shared newest-first release identity helpers.
#
# Both blocking QA and the live ship preflight dot-source this file. Keep it
# ASCII and side-effect free so Windows PowerShell 5.1 can parse it safely.

function Get-NewestChangelogRelease {
    param([Parameter(Mandatory = $true)][string]$ChangelogText)

    $headerMatch = [regex]::Match($ChangelogText, '(?m)^##[ \t]+(?<header>[^\r\n]+)')
    if (-not $headerMatch.Success) {
        return [pscustomobject]@{
            Ok      = $false
            Version = $null
            Header  = $null
            Message = 'CHANGELOG has no level-2 release header'
        }
    }

    $header = $headerMatch.Groups['header'].Value.Trim()
    $versionMatch = [regex]::Match(
        $header,
        '^v?(?<version>\d+\.\d+\.\d+(?:-(?:alpha|beta|dev|rc)\d*)?)(?=$|[ \t(:-])',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $versionMatch.Success) {
        return [pscustomobject]@{
            Ok      = $false
            Version = $null
            Header  = $header
            Message = "newest CHANGELOG header has no leading release version: ## $header"
        }
    }

    return [pscustomobject]@{
        Ok      = $true
        Version = $versionMatch.Groups['version'].Value
        Header  = $header
        Message = 'newest CHANGELOG release parsed'
    }
}

function Test-ReleaseIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$SourceVersion,
        [Parameter(Mandatory = $true)][string]$ChangelogText
    )

    $newest = Get-NewestChangelogRelease -ChangelogText $ChangelogText
    if (-not $newest.Ok) {
        return [pscustomobject]@{
            Ok               = $false
            SourceVersion    = $SourceVersion
            ChangelogVersion = $null
            Header           = $newest.Header
            Message          = $newest.Message
        }
    }
    if ($newest.Version -cne $SourceVersion) {
        return [pscustomobject]@{
            Ok               = $false
            SourceVersion    = $SourceVersion
            ChangelogVersion = $newest.Version
            Header           = $newest.Header
            Message          = "MOD_VERSION '$SourceVersion' does not equal newest CHANGELOG release '$($newest.Version)'"
        }
    }

    return [pscustomobject]@{
        Ok               = $true
        SourceVersion    = $SourceVersion
        ChangelogVersion = $newest.Version
        Header           = $newest.Header
        Message          = 'MOD_VERSION equals newest CHANGELOG release'
    }
}
