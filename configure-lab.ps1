##############################################################################
# configure-lab.ps1
# Purpose : One-shot lab orchestration -- runs from YOUR LOCAL machine
#           Replaces all 7 manual RDP sessions with a single script
#
# Method  : Uses "az vm run-command invoke" to push PowerShell to each VM
#           through the Azure agent. No WinRM, no firewall changes, no RDP.
#
# Usage   : .\configure-lab.ps1 -KeyVaultName "kv-fslab-XXXX"
#           (KeyVaultName comes from: terraform output key_vault_name)
#
# Prerequisites:
#   - Azure CLI installed: winget install Microsoft.AzureCLI
#   - Logged in: az login
#   - terraform apply already completed
##############################################################################

param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,                     # From: terraform output key_vault_name

    [string]$ResourceGroup = "RG-FileServerLab"
)

$startTime = Get-Date

# -- Retrieve admin password from Key Vault -----------------------------------
# Password is never passed as a CLI arg or visible in process listings.
Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Retrieving credentials from Key Vault..." -ForegroundColor Cyan
$AdminPassword = az keyvault secret show `
    --vault-name $KeyVaultName `
    --name "vm-admin-password" `
    --query "value" -o tsv

if (-not $AdminPassword -or $LASTEXITCODE -ne 0) {
    throw "Could not retrieve admin password from Key Vault '$KeyVaultName'. " +
          "Ensure az login is complete and you have 'Key Vault Secrets User' role on the vault."
}
Write-Host "  Credentials retrieved." -ForegroundColor Green

# -- Helper: Run a script on a VM via Azure Run Command -----------------------
function Invoke-VMScript {
    param(
        [string]$VMName,
        [string]$ScriptPath,
        [string]$Description,
        [hashtable]$Replacements = @{}
    )

    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] >>> $Description" -ForegroundColor Cyan

    $script = Get-Content $ScriptPath -Raw

    foreach ($key in $Replacements.Keys) {
        $script = $script -replace $key, [regex]::Escape($Replacements[$key])
    }

    # Write to temp file -- avoids all quoting/escaping issues with inline --scripts
    $tempFile = [System.IO.Path]::GetTempPath() + [System.IO.Path]::GetRandomFileName() + ".ps1"
    $script | Out-File -FilePath $tempFile -Encoding UTF8

    try {
        $jsonLines = az vm run-command invoke `
            --resource-group $ResourceGroup `
            --name $VMName `
            --command-id RunPowerShellScript `
            --scripts "@$tempFile" `
            --output json `
            --only-show-errors

        if ($LASTEXITCODE -ne 0) {
            throw "az vm run-command failed on $VMName (exit code $LASTEXITCODE)"
        }

        $result = ($jsonLines -join "`n") | ConvertFrom-Json

        $stdout = ($result.value | Where-Object { $_.code -like "*StdOut*" }).message
        $stderr = ($result.value | Where-Object { $_.code -like "*StdErr*" }).message

        if ($stdout) { Write-Host $stdout }
        if ($stderr -and $stderr.Trim() -ne "") {
            Write-Warning "  VM StdErr: $stderr"
        }
    }
    finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

# -- Helper: Wait for a VM to return to "VM running" -------------------------
function Wait-VMOnline {
    param(
        [string]$VMName,
        [int]$TimeoutSeconds = 360
    )

    Write-Host "  Waiting for $VMName to come back online..." -ForegroundColor Yellow
    $elapsed = 0

    do {
        Start-Sleep -Seconds 15
        $elapsed += 15

        $state = ""
        try {
            $state = (az vm show -g $ResourceGroup -n $VMName -d `
                --query "powerState" -o tsv --only-show-errors 2>$null)
            if ($state) { $state = $state.Trim() }
        } catch { }

        Write-Host "    $VMName -> '$state'  ($elapsed s elapsed)" -ForegroundColor DarkGray

    } while ($state -ne "VM running" -and $elapsed -lt $TimeoutSeconds)

    if ($state -ne "VM running") {
        throw "Timeout: $VMName did not return to running state within ${TimeoutSeconds}s"
    }

    Write-Host "  $VMName is online." -ForegroundColor Green
}

# ============================================================================
# STEP 1 -- Promote DC01 to Domain Controller
# ============================================================================
Write-Host "`n[STEP 1] Promoting DC01 to Domain Controller" -ForegroundColor Magenta

try {
    Invoke-VMScript -VMName "DC01" `
        -ScriptPath ".\scripts\00-promote-dc.ps1" `
        -Description "Installing AD DS and promoting DC01 to lab.local" `
        -Replacements @{ "SAFE_MODE_PASSWORD" = $AdminPassword }
} catch {
    Write-Host "  DC01 disconnected -- this is expected after domain promotion." -ForegroundColor Yellow
    Write-Host "  Detail: $($_.Exception.Message)" -ForegroundColor DarkGray
}

Write-Host "`n  Waiting 60s for DC01 to begin restarting..." -ForegroundColor Yellow
Start-Sleep -Seconds 60
Wait-VMOnline -VMName "DC01" -TimeoutSeconds 360
Write-Host "  Waiting 90s for Active Directory services to fully initialise..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

# ============================================================================
# STEP 2 -- Create OUs, Security Groups, and Test Users
# ============================================================================
Write-Host "`n[STEP 2] Creating OUs, Security Groups, and Test Users" -ForegroundColor Magenta

Invoke-VMScript -VMName "DC01" `
    -ScriptPath ".\scripts\01-create-ad-users-groups.ps1" `
    -Description "Creating AD objects on DC01"

# ============================================================================
# STEP 3 -- Join FS01 to lab.local
# ============================================================================
Write-Host "`n[STEP 3] Joining FS01 to lab.local" -ForegroundColor Magenta

Invoke-VMScript -VMName "FS01" `
    -ScriptPath ".\scripts\04-domain-join.ps1" `
    -Description "Joining FS01 to lab.local" `
    -Replacements @{ "ADMIN_PASSWORD" = $AdminPassword }

Start-Sleep -Seconds 30
Wait-VMOnline -VMName "FS01" -TimeoutSeconds 240
Start-Sleep -Seconds 30

# ============================================================================
# STEP 4 -- Configure SMB Shares and NTFS Permissions on FS01
# ============================================================================
Write-Host "`n[STEP 4] Configuring shares and NTFS permissions on FS01" -ForegroundColor Magenta

Invoke-VMScript -VMName "FS01" `
    -ScriptPath ".\scripts\02-configure-shares-and-permissions.ps1" `
    -Description "Creating SMB shares and applying NTFS permissions on FS01"

# ============================================================================
# STEP 5 -- Join CLIENT01 to lab.local
# ============================================================================
Write-Host "`n[STEP 5] Joining CLIENT01 to lab.local" -ForegroundColor Magenta

Invoke-VMScript -VMName "CLIENT01" `
    -ScriptPath ".\scripts\04-domain-join.ps1" `
    -Description "Joining CLIENT01 to lab.local" `
    -Replacements @{ "ADMIN_PASSWORD" = $AdminPassword }

Start-Sleep -Seconds 30
Wait-VMOnline -VMName "CLIENT01" -TimeoutSeconds 240
Start-Sleep -Seconds 30

# ============================================================================
# STEP 5b -- Add Domain Users to Remote Desktop Users on CLIENT01
# NOTE: This replaces the broken Invoke-Command -ComputerName CLIENT01 block
# that was in 03-configure-rdp-gpo.ps1. WinRM (port 5985) is blocked by the
# NSG -- az vm run-command bypasses the NSG entirely via the Azure agent.
# ============================================================================
Write-Host "`n[STEP 5b] Granting Domain Users RDP access on CLIENT01" -ForegroundColor Magenta

Invoke-VMScript -VMName "CLIENT01" `
    -ScriptPath ".\scripts\06-add-rdp-users.ps1" `
    -Description "Adding LAB\Domain Users to Remote Desktop Users on CLIENT01"

# ============================================================================
# STEP 6 -- Configure RDP GPO on DC01
# ============================================================================
Write-Host "`n[STEP 6] Configuring RDP GPO on DC01" -ForegroundColor Magenta

Invoke-VMScript -VMName "DC01" `
    -ScriptPath ".\scripts\03-configure-rdp-gpo.ps1" `
    -Description "Creating and linking RDP GPO on DC01"

# ============================================================================
# STEP 7 -- Automated Verification
# ============================================================================
Write-Host "`n[STEP 7] Running automated verification" -ForegroundColor Magenta

Invoke-VMScript -VMName "DC01" `
    -ScriptPath ".\scripts\05-verify-ad.ps1" `
    -Description "Verifying AD users, groups, and OUs on DC01"

Invoke-VMScript -VMName "FS01" `
    -ScriptPath ".\scripts\05-verify-shares.ps1" `
    -Description "Verifying SMB shares and NTFS permissions on FS01"

# ============================================================================
$duration = (Get-Date) - $startTime
Write-Host "`n=== LAB FULLY CONFIGURED ($([math]::Round($duration.TotalMinutes, 1)) min) ===" -ForegroundColor Green
Write-Host "RDP into CLIENT01 as a test user to explore the lab:" -ForegroundColor Yellow
Write-Host "  Username : LAB\sarah.jones   Password: P@ssw0rd123!"
Write-Host "  Try: \\FS01\Finance  (Expect: Modify access)"
Write-Host "  Try: \\FS01\HR       (Expect: Access Denied)`n"
