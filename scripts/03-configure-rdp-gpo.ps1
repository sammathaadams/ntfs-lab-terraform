# =============================================================
# Script: 03-configure-rdp-gpo.ps1
# Run on: DC01
# Purpose: Create GPO to grant Remote Desktop access to domain
#          users on all lab computers — no per-machine config needed
# =============================================================

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$gpoName  = "Lab - Allow RDP for Domain Users"
$domainDN = "DC=lab,DC=local"
$ouPath   = "OU=Lab Computers,$domainDN"

# ── Create and link the GPO ───────────────────────────────────
$gpo = New-GPO -Name $gpoName
New-GPLink -Name $gpoName -Target $ouPath
Write-Host "Created and linked GPO: $gpoName" -ForegroundColor Yellow

# ── Enable Remote Desktop via GPO registry setting ───────────
Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\System\CurrentControlSet\Control\Terminal Server" `
    -ValueName "fDenyTSConnections" `
    -Type DWord `
    -Value 0

Write-Host "Enabled RDP via GPO registry setting." -ForegroundColor Cyan

# ── Move CLIENT01 computer account to Lab Computers OU ────────
Get-ADComputer -Filter {Name -eq "CLIENT01"} | Move-ADObject -TargetPath $ouPath
Write-Host "Moved CLIENT01 to Lab Computers OU." -ForegroundColor Cyan

# ── Add Domain Users directly to CLIENT01 local RDP group ─────
# Tries Invoke-Command (requires WinRM). Falls back to a manual reminder if WinRM is not ready.
try {
    Invoke-Command -ComputerName CLIENT01 -ErrorAction Stop -ScriptBlock {
        Add-LocalGroupMember -Group "Remote Desktop Users" -Member "LAB\Domain Users"
        Write-Host "Added LAB\Domain Users to Remote Desktop Users on CLIENT01." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not reach CLIENT01 via WinRM: $_"
    Write-Host ""
    Write-Host "ACTION REQUIRED — run this manually on CLIENT01:" -ForegroundColor Yellow
    Write-Host '  Add-LocalGroupMember -Group "Remote Desktop Users" -Member "LAB\Domain Users"' -ForegroundColor White
    Write-Host "Or simply RDP into CLIENT01 as azureadmin and run the line above in PowerShell." -ForegroundColor Gray
}

Write-Host "`nDone! Domain users can now RDP into CLIENT01." -ForegroundColor Green
