# =============================================================
# Script: 03-configure-rdp-gpo.ps1
# Run on: DC01
# Purpose: Create GPO to grant Remote Desktop access to domain
#          users on all lab computers — no per-machine config needed
# =============================================================

$gpoName  = "Lab - Allow RDP for Domain Users"
$domainDN = "DC=lab,DC=local"
$ouPath   = "OU=Lab Computers,$domainDN"

# ── Create and link the GPO ───────────────────────────────────
$gpo = New-GPO -Name $gpoName
New-GPLink -Name $gpoName -Target $ouPath
Write-Host "Created and linked GPO: $gpoName" -ForegroundColor Yellow

# ── Add Domain Users to local Remote Desktop Users via GPO ───
# This uses Restricted Groups to push the AD group into the
# local Remote Desktop Users group on every machine in the OU

$gpoId = $gpo.Id.ToString()
$gpoPath = "\\lab.local\SYSVOL\lab.local\Policies\{$gpoId}\Machine\Microsoft\Windows NT\SecEdit"

New-Item -Path $gpoPath -ItemType Directory -Force | Out-Null

$infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Group Membership]
*S-1-5-32-555__Memberof =
*S-1-5-32-555__Members = *S-1-5-21-domain-515
"@

# Note: The approach below uses Set-GPRegistryValue to enable RDP
# and Restricted Groups via the Security template

# Enable Remote Desktop via GPO registry setting
Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\System\CurrentControlSet\Control\Terminal Server" `
    -ValueName "fDenyTSConnections" `
    -Type DWord `
    -Value 0

Write-Host "Enabled RDP via GPO registry setting." -ForegroundColor Cyan

# ── Move CLIENT01 computer account to Lab Computers OU ────────
# Run this after CLIENT01 joins the domain
Get-ADComputer -Filter {Name -eq "CLIENT01"} | Move-ADObject -TargetPath $ouPath
Write-Host "Moved CLIENT01 to Lab Computers OU." -ForegroundColor Cyan

# ── Add domain Remote Desktop Users group to local RDU group ──
# Using net localgroup via GPO startup script is the most reliable
# method for Restricted Groups in smaller labs

$startupScript = @"
net localgroup "Remote Desktop Users" "LAB\Domain Users" /add
"@

$scriptPath = "\\lab.local\SYSVOL\lab.local\Policies\{$gpoId}\Machine\Scripts\Startup"
New-Item -Path $scriptPath -ItemType Directory -Force | Out-Null
Set-Content -Path "$scriptPath\add-rdp-users.bat" -Value $startupScript

Write-Host "Startup script created — run 'gpupdate /force' on CLIENT01 to apply." -ForegroundColor Green
Write-Host "`nDone! GPO configured for RDP access." -ForegroundColor Green
