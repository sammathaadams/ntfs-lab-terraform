##############################################################################
# 05-verify-shares.ps1
# Run via  : az vm run-command (NOT manually -- called by configure-lab.ps1)
# Runs on  : FS01
# Purpose  : Confirm SMB shares exist and NTFS ACLs match expected config
##############################################################################

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$basePath = "C:\Shares"
$pass = $true

Write-Host "`n=== Share and NTFS Permission Verification ===" -ForegroundColor Cyan

# -- Expected NTFS permissions per share -------------------------------------
$expectedACLs = @{
    "Finance" = @(
        @{ Identity = "LAB\GRP_Finance"; Right = [System.Security.AccessControl.FileSystemRights]::Modify      }
        @{ Identity = "LAB\GRP_HR";      Right = [System.Security.AccessControl.FileSystemRights]::Read        }
        @{ Identity = "LAB\GRP_IT";      Right = [System.Security.AccessControl.FileSystemRights]::FullControl }
    )
    "HR"      = @(
        @{ Identity = "LAB\GRP_HR";      Right = [System.Security.AccessControl.FileSystemRights]::Modify      }
        @{ Identity = "LAB\GRP_IT";      Right = [System.Security.AccessControl.FileSystemRights]::FullControl }
    )
    "Sales"   = @(
        @{ Identity = "LAB\GRP_Sales";   Right = [System.Security.AccessControl.FileSystemRights]::Modify      }
        @{ Identity = "LAB\GRP_IT";      Right = [System.Security.AccessControl.FileSystemRights]::FullControl }
    )
    "IT"      = @(
        @{ Identity = "LAB\GRP_IT";      Right = [System.Security.AccessControl.FileSystemRights]::FullControl }
    )
}

foreach ($share in $expectedACLs.Keys) {
    Write-Host "`n[ $share ]" -ForegroundColor White
    $sharePath = "$basePath\$share"

    # -- Check SMB share exists -----------------------------------------------
    $smbShare = Get-SmbShare -Name $share -ErrorAction SilentlyContinue
    if ($smbShare) {
        Write-Host "  [PASS] SMB share \\FS01\$share exists" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] SMB share \\FS01\$share is MISSING" -ForegroundColor Red
        $pass = $false
        continue
    }

    # -- Check NTFS ACL entries -----------------------------------------------
    $acl = (Get-Acl $sharePath).Access

    foreach ($expected in $expectedACLs[$share]) {

        # Use .Value to get the string representation for reliable comparison.
        $matchingAce = $acl | Where-Object {
            $_.IdentityReference.Value -eq $expected.Identity -and
            $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow
        }

        if (-not $matchingAce) {
            Write-Host "  [FAIL] $($expected.Identity) has NO entry on $share" -ForegroundColor Red
            $pass = $false
            continue
        }

        # FileSystemRights is a flags enum -- use bitwise AND to confirm bits are present.
        $hasRight = ($matchingAce.FileSystemRights -band $expected.Right) -eq $expected.Right

        if ($hasRight) {
            Write-Host "  [PASS] $($expected.Identity) -> $($expected.Right) on $share" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($expected.Identity) has '$($matchingAce.FileSystemRights)' but expected '$($expected.Right)' on $share" -ForegroundColor Red
            $pass = $false
        }
    }

    # -- Show full ACL for reference ------------------------------------------
    Write-Host "  -- Raw ACL --" -ForegroundColor DarkGray
    $acl | Where-Object { $_.IdentityReference.Value -notmatch "BUILTIN|NT AUTHORITY|CREATOR" } |
        ForEach-Object {
            Write-Host "     $($_.IdentityReference.Value) -> $($_.FileSystemRights)" -ForegroundColor DarkGray
        }
}

# -- Check for overly permissive entries -------------------------------------
Write-Host "`n[ Checking for overly permissive entries ]" -ForegroundColor White
$dangerous = @("Everyone", "BUILTIN\Users", "NT AUTHORITY\Authenticated Users")

foreach ($share in $expectedACLs.Keys) {
    $acl = (Get-Acl "$basePath\$share").Access
    foreach ($d in $dangerous) {
        $found = $acl | Where-Object {
            $_.IdentityReference.Value -eq $d -and
            $_.AccessControlType -eq "Allow"
        }
        if ($found) {
            Write-Host "  [WARN] '$d' still has access on $share -- should be removed" -ForegroundColor Yellow
        }
    }
}

# -- Summary -----------------------------------------------------------------
$status = if ($pass) { "PASSED" } else { "FAILED -- review output above" }
$color  = if ($pass) { "Green"  } else { "Red" }
Write-Host "`n=== Permission Verification $status ===" -ForegroundColor $color

if ($pass) {
    Write-Host @"

Lab is ready. RDP into CLIENT01 as any test user to verify access in File Explorer:

  User          Share      Expected
  ------------  ---------  --------------------
  sarah.jones   Finance    Modify  (can write)
  sarah.jones   HR         Denied  (no HR access)
  lisa.white    Finance    Read    (read-only)
  lisa.white    HR         Modify  (can write)
  john.smith    IT         Full    (full control)
  tom.davis     Sales      Modify  (can write)
  tom.davis     Finance    Denied  (no Finance access)
"@ -ForegroundColor Cyan
}
