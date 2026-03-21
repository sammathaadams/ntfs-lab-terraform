##############################################################################
# 00-promote-dc.ps1
# Run via  : az vm run-command (NOT manually -- called by configure-lab.ps1)
# Runs on  : DC01
# Purpose  : Install AD DS features and promote DC01 to Domain Controller
#
# Token    : SAFE_MODE_PASSWORD is replaced by configure-lab.ps1 at runtime
##############################################################################

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# -- Install Active Directory Domain Services feature -------------------------
Write-Host "Installing AD DS feature..." -ForegroundColor Yellow
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Verbose:$false

# -- Promote DC01 to Domain Controller for lab.local --------------------------
Write-Host "Promoting DC01 to Domain Controller for lab.local..." -ForegroundColor Yellow

$safeModePassword = ConvertTo-SecureString "SAFE_MODE_PASSWORD" -AsPlainText -Force

Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName         "lab.local" `
    -DomainNetbiosName  "LAB" `
    -ForestMode         "WinThreshold" `
    -DomainMode         "WinThreshold" `
    -InstallDns:        $true `
    -SafeModeAdministratorPassword $safeModePassword `
    -Force:             $true `
    -NoRebootOnCompletion:$false   # VM restarts automatically here

# configure-lab.ps1 catches the disconnect and waits for DC01 to come back.
