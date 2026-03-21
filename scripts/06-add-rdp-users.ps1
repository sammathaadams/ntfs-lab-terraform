##############################################################################
# 06-add-rdp-users.ps1
# Run via  : az vm run-command (NOT manually -- called by configure-lab.ps1)
# Runs on  : CLIENT01 (after domain join + restart in Step 5b)
#
# Purpose  : Add LAB\Domain Users to the local Remote Desktop Users group
#            so all domain users can RDP into CLIENT01.
#
# WHY THIS FILE EXISTS:
#   The original 03-configure-rdp-gpo.ps1 tried to do this with:
#     Invoke-Command -ComputerName CLIENT01 { ... }
#   That fails because the NSG only allows port 3389 (RDP) between VMs.
#   WinRM (port 5985) is blocked at the NSG level, so Invoke-Command
#   from DC01 to CLIENT01 is silently dropped.
#   We bypass the NSG entirely by using az vm run-command on CLIENT01 directly.
##############################################################################

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Check if the group member already exists (safe to re-run)
$rdpGroup    = "Remote Desktop Users"
$domainUsers = "LAB\Domain Users"

$existing = Get-LocalGroupMember -Group $rdpGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $domainUsers }

if ($existing) {
    Write-Host "$domainUsers is already in $rdpGroup -- skipping." -ForegroundColor Yellow
} else {
    Add-LocalGroupMember -Group $rdpGroup -Member $domainUsers
    Write-Host "Added $domainUsers to $rdpGroup on CLIENT01." -ForegroundColor Green
}

# Confirm final group membership
Write-Host "`nCurrent members of '$rdpGroup':" -ForegroundColor Cyan
Get-LocalGroupMember -Group $rdpGroup | Select-Object Name, ObjectClass | Format-Table -AutoSize
