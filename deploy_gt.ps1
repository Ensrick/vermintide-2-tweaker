# deploy_gt.ps1 - Deploy General Tweaker (VMB build) to Workshop content folder
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$root\deploy_all.ps1" -Mods @("general_tweaker")
