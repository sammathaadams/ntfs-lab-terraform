# NTFS File Server Lab

Azure IaC for Windows Server administration — Active Directory, NTFS access control, SMB file services, and Group Policy. Deployed with Terraform, configured with PowerShell.

---

## What You'll Learn

- Deploying Windows Server infrastructure on Azure using Terraform
- Promoting a server to an Active Directory Domain Controller
- Configuring NTFS permissions and SMB file shares
- Implementing group-based access control
- Managing Group Policy Objects (GPO) for RDP access
- Joining Windows clients to a domain

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Azure VNet                             │
│                    10.0.0.0/16                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Subnet: 10.0.1.0/24                      │  │
│  │                                                       │  │
│  │   ┌─────────┐    ┌─────────┐    ┌─────────────┐       │  │
│  │   │  DC01   │    │  FS01   │    │  CLIENT01   │       │  │
│  │   │ (AD DS) │◄───│ (Files) │◄───│ (Workstation)│      │  │
│  │   └─────────┘    └─────────┘    └─────────────┘       │  │
│  │                                                       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

| VM        | Role               | OS                   |
|-----------|--------------------|----------------------|
| DC01      | Domain Controller  | Windows Server 2022  |
| FS01      | File Server        | Windows Server 2022  |
| CLIENT01  | Client Workstation | Windows 11 Pro       |

- **Domain:** `lab.local`
- **Region:** Central US
- **VM Size:** Standard_D2s_v3

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- An active Azure subscription

> **Cost Estimate:** Running all three VMs costs approximately $0.30–0.50/hour. Remember to run `terraform destroy` when finished to avoid unexpected charges.

---

## Deploy Infrastructure

```bash
# 1. Login to Azure
az login

# 2. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialize and deploy
terraform init
terraform apply
```

> **Security Note:** `terraform.tfvars` is excluded from git. Never commit passwords or sensitive data.

**Deployment time:** Approximately 10–15 minutes.

After deployment, Terraform outputs the public IPs for all three VMs.

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
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "10.0.1.4"

# Join the domain
Add-Computer -DomainName "lab.local" -Credential (Get-Credential) -Restart
```

> **Note:** Use `LAB\azureadmin` credentials when prompted. DC01's private IP is statically set to `10.0.1.4`.

---

### Step 3 — Create AD Users and Groups

RDP into **DC01** and run:

```powershell
.\scripts\01-create-ad-users-groups.ps1
```

This creates:

- **OUs:** `Lab Users`, `Lab Groups`, `Lab Computers`
- **Groups:** `GRP_Finance`, `GRP_HR`, `GRP_Sales`, `GRP_IT`
- **Users:** 5 test users (see table below)

---

### Step 4 — Configure File Shares and NTFS Permissions

RDP into **FS01** and run:

```powershell
.\scripts\02-configure-shares-and-permissions.ps1
```

Creates shares at `C:\Shares\` and applies NTFS permissions.

---

### Step 5 — Configure RDP Access via GPO

RDP into **DC01** and run:

```powershell
.\scripts\03-configure-rdp-gpo.ps1
```

Then on **CLIENT01** run:

```powershell
gpupdate /force
```

---

## Test Users

| User         | Password       | Group       | Finance      | HR      | Sales   | IT           |
|--------------|----------------|-------------|--------------|---------|---------|--------------|
| john.smith   | P@ssw0rd123!   | GRP_IT      | Full Control | Full    | Full    | Full Control |
| sarah.jones  | P@ssw0rd123!   | GRP_Finance | Modify       | Denied  | Denied  | Denied       |
| mike.brown   | P@ssw0rd123!   | GRP_Finance | Modify       | Denied  | Denied  | Denied       |
| lisa.white   | P@ssw0rd123!   | GRP_HR      | Read         | Modify  | Denied  | Denied       |
| tom.davis    | P@ssw0rd123!   | GRP_Sales   | Denied       | Denied  | Modify  | Denied       |

---

## NTFS Permission Reference

| Flag   | Meaning                                         |
|--------|-------------------------------------------------|
| `F`    | Full Control                                    |
| `M`    | Modify (read, write, delete — cannot change permissions) |
| `R`    | Read only                                       |
| `(OI)` | Object Inherit — subfiles inherit this ACE      |
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

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Domain join fails | Verify DNS is pointing to DC01's private IP. Run `nslookup lab.local` to test. |
| Cannot RDP to VMs | Check NSG rules allow port 3389 from your IP. Verify VM is running in Azure portal. |
| "Access Denied" on shares | Confirm user is in the correct group. Run `whoami /groups` to verify. |
| GPO not applying | Run `gpupdate /force` and wait 2–5 minutes. Check `gpresult /r` for errors. |
| Scripts fail to run | Set execution policy: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process` |

---

## Teardown

Use the Azure CLI to delete the resource group — this is faster and more reliable than `terraform destroy` as Azure handles resource deletion in the correct order automatically:

```bash
az group delete -n RG-FileServerLab --yes --no-wait
```

Then clear the Terraform state to keep it in sync:

```bash
terraform state rm $(terraform state list | tr '\n' ' ')
```

> **Important:** Always destroy resources when finished to avoid ongoing charges.

---

## Project Structure

```
ntfs-lab-terraform/
├── main.tf                    # Core infrastructure resources
├── variables.tf               # Input variable definitions
├── outputs.tf                 # Output values (IPs, etc.)
├── versions.tf                # Provider version constraints
├── terraform.tfvars.example   # Example variable values
└── scripts/
    ├── 01-create-ad-users-groups.ps1
    ├── 02-configure-shares-and-permissions.ps1
    └── 03-configure-rdp-gpo.ps1
```

---

## License

MIT
