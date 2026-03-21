##############################################################################
# 05-verify-ad.ps1
# Run via  : az vm run-command (NOT manually -- called by configure-lab.ps1)
# Runs on  : DC01
# Purpose  : Confirm that OUs, groups, and users were created correctly
#            Replaces manually logging into DC01 to check AD
##############################################################################

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Import-Module ActiveDirectory

$pass = $true

Write-Host "`n=== Active Directory Verification ===" -ForegroundColor Cyan

# -- Check OUs ----------------------------------------------------------------
$expectedOUs = @("Lab Users", "Lab Groups", "Lab Computers")
Write-Host "`n[ Organizational Units ]" -ForegroundColor White

foreach ($ou in $expectedOUs) {
    $exists = [bool](Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue)
    if ($exists) {
        Write-Host "  [PASS] OU: $ou" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] OU missing: $ou" -ForegroundColor Red
        $pass = $false
    }
}

# -- Check Groups -------------------------------------------------------------
$expectedGroups = @("GRP_Finance", "GRP_HR", "GRP_Sales", "GRP_IT")
Write-Host "`n[ Security Groups ]" -ForegroundColor White

foreach ($group in $expectedGroups) {
    $exists = [bool](Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue)
    if ($exists) {
        Write-Host "  [PASS] Group: $group" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Group missing: $group" -ForegroundColor Red
        $pass = $false
    }
}

# -- Check Users and Group Membership -----------------------------------------
$expectedUsers = @(
    @{ Username = "john.smith";  Group = "GRP_IT"      },
    @{ Username = "sarah.jones"; Group = "GRP_Finance"  },
    @{ Username = "mike.brown";  Group = "GRP_Finance"  },
    @{ Username = "lisa.white";  Group = "GRP_HR"       },
    @{ Username = "tom.davis";   Group = "GRP_Sales"    }
)

Write-Host "`n[ Users and Group Memberships ]" -ForegroundColor White

foreach ($u in $expectedUsers) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$($u.Username)'" -ErrorAction SilentlyContinue

    if (-not $user) {
        Write-Host "  [FAIL] User missing: $($u.Username)" -ForegroundColor Red
        $pass = $false
        continue
    }

    $members = Get-ADGroupMember -Identity $u.Group | Select-Object -ExpandProperty SamAccountName
    if ($members -contains $u.Username) {
        Write-Host "  [PASS] $($u.Username) -> $($u.Group)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($u.Username) not in $($u.Group)" -ForegroundColor Red
        $pass = $false
    }
}

# -- Check domain-joined computers --------------------------------------------
Write-Host "`n[ Domain-Joined Computers ]" -ForegroundColor White
$computers = Get-ADComputer -Filter * | Select-Object -ExpandProperty Name

foreach ($computer in @("FS01", "CLIENT01")) {
    if ($computers -contains $computer) {
        Write-Host "  [PASS] $computer is domain joined" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] $computer not yet visible in AD (may still be joining)" -ForegroundColor Yellow
    }
}

# -- Summary ------------------------------------------------------------------
Write-Host "`n=== AD Verification $(if ($pass) { 'PASSED' } else { 'FAILED -- review output above' }) ===" `
    -ForegroundColor $(if ($pass) { "Green" } else { "Red" })
