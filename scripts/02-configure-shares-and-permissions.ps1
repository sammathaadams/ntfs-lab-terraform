# =============================================================
# Script: 02-configure-shares-and-permissions.ps1
# Run on: FS01
# Purpose: Create SMB shares and apply NTFS permissions
# =============================================================

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$domain   = "LAB"
$basePath = "C:\Shares"

# ── Create base folder ────────────────────────────────────────
New-Item -Path $basePath -ItemType Directory -Force

# ── Create share folders ──────────────────────────────────────
$folders = @("Finance", "HR", "Sales", "IT")
foreach ($folder in $folders) {
    New-Item -Path "$basePath\$folder" -ItemType Directory -Force
    Write-Host "Created folder: $basePath\$folder" -ForegroundColor Yellow
}

# ── Create SMB shares (share-level: Everyone Full Control) ────
# Real security is enforced by NTFS permissions below
foreach ($folder in $folders) {
    New-SmbShare -Name $folder `
                 -Path "$basePath\$folder" `
                 -FullAccess "Everyone" `
                 -Description "$folder department share"
    Write-Host "Created share: \\FS01\$folder" -ForegroundColor Yellow
}

# ── Helper function to set NTFS permissions ───────────────────
function Set-FolderPermissions {
    param($path, $permissions)

    # Disable inheritance and remove inherited ACEs
    icacls $path /inheritance:d

    # Remove overly permissive default groups
    icacls $path /remove "BUILTIN\Users"
    icacls $path /remove "Everyone"
    icacls $path /remove "NT AUTHORITY\Authenticated Users"

    # Apply each permission entry
    foreach ($perm in $permissions) {
        icacls $path /grant "$($perm.Identity)`:$($perm.Rights)"
        Write-Host "  Granted $($perm.Rights) to $($perm.Identity)" -ForegroundColor Cyan
    }
}

# ── Apply NTFS permissions per share ─────────────────────────

Write-Host "`nSetting permissions on Finance..." -ForegroundColor Green
Set-FolderPermissions -path "$basePath\Finance" -permissions @(
    @{ Identity = "$domain\GRP_Finance";        Rights = "(OI)(CI)M" },   # Modify
    @{ Identity = "$domain\GRP_HR";             Rights = "(OI)(CI)R" },   # Read
    @{ Identity = "$domain\GRP_IT";             Rights = "(OI)(CI)F" },   # Full Control
    @{ Identity = "BUILTIN\Administrators";     Rights = "(OI)(CI)F" }
)

Write-Host "`nSetting permissions on HR..." -ForegroundColor Green
Set-FolderPermissions -path "$basePath\HR" -permissions @(
    @{ Identity = "$domain\GRP_HR";             Rights = "(OI)(CI)M" },   # Modify
    @{ Identity = "$domain\GRP_IT";             Rights = "(OI)(CI)F" },   # Full Control
    @{ Identity = "BUILTIN\Administrators";     Rights = "(OI)(CI)F" }
)

Write-Host "`nSetting permissions on Sales..." -ForegroundColor Green
Set-FolderPermissions -path "$basePath\Sales" -permissions @(
    @{ Identity = "$domain\GRP_Sales";          Rights = "(OI)(CI)M" },   # Modify
    @{ Identity = "$domain\GRP_IT";             Rights = "(OI)(CI)F" },   # Full Control
    @{ Identity = "BUILTIN\Administrators";     Rights = "(OI)(CI)F" }
)

Write-Host "`nSetting permissions on IT..." -ForegroundColor Green
Set-FolderPermissions -path "$basePath\IT" -permissions @(
    @{ Identity = "$domain\GRP_IT";             Rights = "(OI)(CI)F" },   # Full Control
    @{ Identity = "BUILTIN\Administrators";     Rights = "(OI)(CI)F" }
)

Write-Host "`nDone! All shares and NTFS permissions configured." -ForegroundColor Cyan
