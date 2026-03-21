##############################################################################
# 03-configure-rdp-gpo.ps1  -- UPDATED VERSION
# Run via  : az vm run-command (NOT manually -- called by configure-lab.ps1)
# Runs on  : DC01
# Purpose  : Create and link a GPO that enables RDP on machines in the
#            Lab Computers OU, and moves CLIENT01's computer account into it.
#
# WHAT CHANGED FROM THE ORIGINAL:
#   Removed the Invoke-Command -ComputerName CLIENT01 block.
#   The NSG only allows port 3389 -- WinRM (5985/5986) is blocked between VMs,
#   so that block always failed with a warning. Adding LAB\Domain Users to the
#   Remote Desktop Users group is now handled separately by configure-lab.ps1
#   calling 06-add-rdp-users.ps1 directly on CLIENT01 via az vm run-command.
##############################################################################

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$gpoName   = "Lab - Allow RDP for Domain Users"
$domainDN  = "DC=lab,DC=local"
$ouPath    = "OU=Lab Computers,$domainDN"

# -- Create and link the GPO --------------------------------------------------
$gpo = New-GPO -Name $gpoName
New-GPLink -Name $gpoName -Target $ouPath
Write-Host "Created and linked GPO: $gpoName" -ForegroundColor Yellow

# -- Enable Remote Desktop via GPO registry setting --------------------------
# This sets fDenyTSConnections = 0 on all computers in the Lab Computers OU.
# Note: CLIENT01 already has RDP enabled by Terraform's CustomScriptExtension,
# so this is reinforcement / applies to any future machines added to the OU.
Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\System\CurrentControlSet\Control\Terminal Server" `
    -ValueName "fDenyTSConnections" `
    -Type DWord `
    -Value 0

Write-Host "Enabled RDP via GPO registry setting." -ForegroundColor Cyan

# -- Move CLIENT01 computer account to Lab Computers OU ----------------------
$computer = Get-ADComputer -Filter { Name -eq "CLIENT01" } -ErrorAction SilentlyContinue

if ($computer) {
    $computer | Move-ADObject -TargetPath $ouPath
    Write-Host "Moved CLIENT01 to OU=Lab Computers." -ForegroundColor Cyan
} else {
    Write-Warning "CLIENT01 computer account not found in AD yet. It may still be joining the domain. Re-run this step if needed."
}

Write-Host "`nGPO configuration complete." -ForegroundColor Green
Write-Host "Note: LAB\Domain Users -> Remote Desktop Users is handled by" -ForegroundColor DarkGray
Write-Host "      configure-lab.ps1 Step 5b (06-add-rdp-users.ps1 on CLIENT01)." -ForegroundColor DarkGray
