##############################################################################
# 04-domain-join.ps1
# Run via  : az vm run-command (NOT manually -- called by configure-lab.ps1)
# Runs on  : FS01, then CLIENT01 (same script, both machines)
# Purpose  : Point DNS at DC01 and join the lab.local domain
#
# Token    : ADMIN_PASSWORD is replaced by configure-lab.ps1 at runtime
##############################################################################

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# -- Point DNS at DC01 (required before the domain can be resolved) ----------
Write-Host "Setting DNS to DC01 (10.0.1.4)..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "10.0.1.4"

# -- Wait until lab.local can be resolved ------------------------------------
# DC01 may still be finishing up -- retry for up to 3 minutes before giving up.
Write-Host "Waiting for lab.local DNS to resolve..." -ForegroundColor Yellow
$retries = 0
$resolved = $false

do {
    Start-Sleep -Seconds 15
    $retries++
    $resolved = [bool](Resolve-DnsName "lab.local" -ErrorAction SilentlyContinue)
    Write-Host "  Attempt $retries -- resolved: $resolved"
} while (-not $resolved -and $retries -lt 12)   # Max 3 minutes

if (-not $resolved) {
    throw "Could not resolve lab.local after 3 minutes. Check that DC01 is running and AD DS is healthy."
}

Write-Host "lab.local resolved successfully." -ForegroundColor Green

# -- Join the domain and restart ---------------------------------------------
Write-Host "Joining lab.local..." -ForegroundColor Yellow

$domainCred = New-Object PSCredential(
    "LAB\azureadmin",
    (ConvertTo-SecureString "ADMIN_PASSWORD" -AsPlainText -Force)
)

Add-Computer -DomainName "lab.local" -Credential $domainCred -Restart -Force

# VM restarts here -- configure-lab.ps1 waits for it to come back online.
