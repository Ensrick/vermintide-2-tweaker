# deploy_ct.ps1 - Deploy Chaos Wastes Tweaker (VMB build) to Workshop content folder
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$root\deploy_all.ps1" -Mods @("chaos_wastes_tweaker")
