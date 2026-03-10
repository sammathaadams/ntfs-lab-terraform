# NTFS File Server Lab

Azure lab environment for practicing NTFS permissions, SMB file shares, and Active Directory group-based access control.

---

## Architecture

| VM | Role | OS |
|---|---|---|
| DC01 | Domain Controller | Windows Server 2022 |
| FS01 | File Server | Windows Server 2022 |
| CLIENT01 | Client Workstation | Windows 11 Pro |

- **Domain:** `lab.local`
- **VNet:** `10.0.0.0/16` — Subnet: `10.0.1.0/24`
- **Region:** Central US
- **VM Size:** Standard_D2s_v3

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- An active Azure subscription

---

## Deploy Infrastructure

```bash
# 1. Login to Azure
az login

# 2. Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars

# 3. Initialize and deploy
terraform init
terraform apply
```

> **Note:** `terraform.tfvars` is excluded from git. Never commit real passwords or IPs.

After deploy, Terraform outputs the public IPs for all three VMs.

---

## Lab Setup Steps

### Step 1 — Promote DC01 to Domain Controller

RDP into DC01 and run in PowerShell:

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetbiosName "LAB" `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDns:$true `
    -Force:$true
```

DC01 will restart automatically.

---

### Step 2 — Join FS01 and CLIENT01 to the Domain

RDP into each machine and run:

```powershell
# Set DNS to point to DC01's private IP
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "10.0.1.6"

# Join the domain
Add-Computer -DomainName "lab.local" -Credential (Get-Credential) -Restart
```

Use `LAB\azureadmin` credentials when prompted.

---

### Step 3 — Create AD Users and Groups

RDP into **DC01** and run:

```
scripts\02-create-ad-users-groups.ps1
```

This creates:
- OUs: `Lab Users`, `Lab Groups`, `Lab Computers`
- Groups: `GRP_Finance`, `GRP_HR`, `GRP_Sales`, `GRP_IT`
- 5 test users (see table below)

---

### Step 4 — Configure File Shares and NTFS Permissions

RDP into **FS01** and run:

```
scripts\01-configure-shares-and-permissions.ps1
```

Creates shares at `C:\Shares\` and applies NTFS permissions.

---

### Step 5 — Configure RDP Access via GPO

RDP into **DC01** and run:

```
scripts\03-configure-rdp-gpo.ps1
```

Then on **CLIENT01** run:

```powershell
gpupdate /force
```

---

## Test Users

| User | Password | Group | Finance | HR | Sales | IT |
|---|---|---|---|---|---|---|
| john.smith | P@ssw0rd123! | GRP_IT | Full Control | Full Control | Full Control | Full Control |
| sarah.jones | P@ssw0rd123! | GRP_Finance | Modify | Denied | Denied | Denied |
| mike.brown | P@ssw0rd123! | GRP_Finance | Modify | Denied | Denied | Denied |
| lisa.white | P@ssw0rd123! | GRP_HR | Read | Modify | Denied | Denied |
| tom.davis | P@ssw0rd123! | GRP_Sales | Denied | Denied | Modify | Denied |

---

## NTFS Permission Reference

| Flag | Meaning |
|---|---|
| `F` | Full Control |
| `M` | Modify (read, write, delete — cannot change permissions) |
| `R` | Read only |
| `(OI)` | Object Inherit — subfiles inherit this ACE |
| `(CI)` | Container Inherit — subfolders inherit this ACE |

---

## Verify Permissions

RDP into **CLIENT01** as any test user and browse to `\\FS01` in File Explorer.

To verify permissions from the CLI on FS01:

```powershell
$shares = @("Finance","HR","Sales","IT")
foreach ($share in $shares) {
    Write-Host "`n--- $share ---" -ForegroundColor Cyan
    icacls "C:\Shares\$share"
}
```

---

## Teardown

```bash
terraform destroy
```
