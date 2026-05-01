# deploy_wt.ps1 - Deploy Weapon Tweaker (VMB build) to Workshop content folder
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$root\deploy_all.ps1" -Mods @("weapon_tweaker")
