# NTFS File Server Lab

Azure IaC for Windows Server administration — Active Directory, NTFS access control, SMB file services, and Group Policy. Deployed with Terraform, configured automatically with PowerShell and Azure Run Command.

---

## What You'll Learn

- Deploying Windows Server infrastructure on Azure using Terraform
- Storing secrets securely with Azure Key Vault (RBAC-based)
- Managing Terraform state remotely in Azure Blob Storage
- Promoting a server to an Active Directory Domain Controller
- Automating VM configuration without RDP using `az vm run-command`
- Configuring NTFS permissions and SMB file shares
- Implementing group-based access control
- Managing Group Policy Objects (GPO) for RDP access
- Joining Windows clients to a domain

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Azure VNet                           │
│                        10.0.0.0/16                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  Subnet: 10.0.1.0/24                  │  │
│  │                                                       │  │
│  │   ┌─────────┐    ┌─────────┐    ┌─────────────┐      │  │
│  │   │  DC01   │    │  FS01   │    │  CLIENT01   │      │  │
│  │   │ (AD DS) │◄───│ (Files) │◄───│ (Workstation│      │  │
│  │   └─────────┘    └─────────┘    └─────────────┘      │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────┐   ┌──────────────────────────┐   │
│   │   Azure Key Vault   │   │  Azure Storage Account   │   │
│   │  (VM credentials)   │   │   (Terraform state)      │   │
│   └─────────────────────┘   └──────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

| VM       | Role               | OS                   |
|----------|--------------------|----------------------|
| DC01     | Domain Controller  | Windows Server 2022  |
| FS01     | File Server        | Windows Server 2022  |
| CLIENT01 | Client Workstation | Windows 11 Pro       |

- **Domain:** `lab.local`
- **Region:** Central US
- **VM Size:** Standard_B2as_v2

> **Cost Estimate:** Running all three VMs costs approximately $0.15–0.25/hour. Run `az group delete -n RG-FileServerLab --yes` when finished to avoid unexpected charges.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.5.0 | [Download](https://developer.hashicorp.com/terraform/downloads) |
| Azure CLI | Latest | `winget install Microsoft.AzureCLI` |
| Active Azure subscription | — | [portal.azure.com](https://portal.azure.com) |

---

## Pre-Setup — Remote State Backend (One Time)

Terraform state is stored in Azure Blob Storage so it is encrypted at rest, never sits on local disk, and can be shared across machines.

```bash
# Create a dedicated resource group for state storage
az group create --name RG-TerraformState --location "Central US"

# Create a storage account (name must be globally unique, 3-24 lowercase chars)
az storage account create --name <YOUR_STORAGE_ACCOUNT_NAME> \
    --resource-group RG-TerraformState \
    --sku Standard_LRS \
    --encryption-services blob

# Create the container
az storage container create --name tfstate \
    --account-name <YOUR_STORAGE_ACCOUNT_NAME>
```

Then open `backend.tf` and replace `REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME` with the name you chose above.

> **Note:** This step only needs to be done once. If you are continuing from Lab 1 and already have a `RG-TerraformState` storage account, skip this and just update `backend.tf` with that account name.

---

## Step 1 — Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and set your values:

```hcl
location       = "Central US"
rdp_source     = "YOUR_PUBLIC_IP/32"   # Find yours at whatismyip.com
server_vm_size = "Standard_B2as_v2"
client_vm_size = "Standard_B2as_v2"
```

Set the admin password as an environment variable — it never touches disk:

```powershell
# PowerShell
$env:TF_VAR_admin_password = "YourStrongPassword!"
```

```bash
# Bash / Azure Cloud Shell
export TF_VAR_admin_password="YourStrongPassword!"
```

> **Why env var?** Terraform automatically reads any `TF_VAR_*` environment variable as the matching input variable. The password exists in memory only — it is never written to disk, never appears in `terraform.tfvars`, and never risks being committed to source control. This is the enterprise-standard approach.
>
> **Password requirements:** Min 12 chars, upper + lower + number + symbol.

> **Security Note:** `terraform.tfvars` is excluded from git via `.gitignore`. The password is also stored in Azure Key Vault during deployment, so you never need to type it again after `terraform apply`.

---

## Step 2 — Deploy Infrastructure

```bash
# Login to Azure
az login

# Initialise providers and connect to remote state backend
terraform init

# Preview what will be created
terraform plan

# Deploy (approx. 10–15 minutes)
terraform apply
```

After `terraform apply` completes, note the Key Vault name from the output:

```
Outputs:

key_vault_name     = "kv-fslab-a1b2c3d4"   ← copy this
dc01_public_ip     = "20.x.x.x"
fs01_public_ip     = "20.x.x.x"
client01_public_ip = "20.x.x.x"
```

> **What gets deployed:** 3 VMs (DC01, FS01, CLIENT01), a VNet, NSG, public IPs, and an Azure Key Vault that holds the admin password. From this point forward you never need to type the password again — the automation retrieves it from Key Vault automatically.

---

## Step 3 — Configure the Lab (Automated)

This single command replaces all manual RDP sessions. It pushes PowerShell scripts to each VM through the Azure agent using `az vm run-command` — no WinRM, no firewall changes needed.

```powershell
.\configure-lab.ps1 -KeyVaultName "kv-fslab-a1b2c3d4"
```

The script runs through these stages automatically:

| Stage | What Happens | VM |
|-------|-------------|-----|
| 1 | Promotes DC01 to Domain Controller for `lab.local` | DC01 |
| 2 | Creates OUs, security groups, and test users in AD | DC01 |
| 3 | Joins FS01 to `lab.local` | FS01 |
| 4 | Creates SMB shares and applies NTFS permissions | FS01 |
| 5 | Joins CLIENT01 to `lab.local` | CLIENT01 |
| 5b | Grants domain users RDP access on CLIENT01 | CLIENT01 |
| 6 | Creates and links RDP GPO | DC01 |
| 7 | Automated verification of AD objects and share permissions | DC01 + FS01 |

**Total time: approximately 15–20 minutes, fully unattended.**

You will see live output as each stage completes. A `[PASS]` / `[FAIL]` report prints at the end confirming everything is configured correctly.

---

## Step 4 — Verify the Lab

RDP into **CLIENT01** using the public IP from `terraform output`:

```
Username : LAB\sarah.jones
Password : P@ssw0rd123!
```

Open **File Explorer** and navigate to `\\FS01`. Test the access scenarios below:

| User | Share | Expected Result |
|------|-------|----------------|
| sarah.jones (GRP_Finance) | `\\FS01\Finance` | ✅ Can read and write |
| sarah.jones (GRP_Finance) | `\\FS01\HR` | ❌ Access Denied |
| lisa.white (GRP_HR) | `\\FS01\Finance` | ✅ Read only |
| lisa.white (GRP_HR) | `\\FS01\HR` | ✅ Can read and write |
| john.smith (GRP_IT) | `\\FS01\IT` | ✅ Full Control |
| tom.davis (GRP_Sales) | `\\FS01\Finance` | ❌ Access Denied |

---

## Test Users

| User | Password | Group | Finance | HR | Sales | IT |
|-------------|--------------|-------------|--------------|--------|--------|--------------|
| john.smith | P@ssw0rd123! | GRP_IT | Full Control | Full | Full | Full Control |
| sarah.jones | P@ssw0rd123! | GRP_Finance | Modify | Denied | Denied | Denied |
| mike.brown | P@ssw0rd123! | GRP_Finance | Modify | Denied | Denied | Denied |
| lisa.white | P@ssw0rd123! | GRP_HR | Read | Modify | Denied | Denied |
| tom.davis | P@ssw0rd123! | GRP_Sales | Denied | Denied | Modify | Denied |

---

## NTFS Permission Reference

| Flag | Meaning |
|------|---------|
| `F` | Full Control |
| `M` | Modify (read, write, delete — cannot change permissions) |
| `R` | Read only |
| `(OI)` | Object Inherit — subfiles inherit this ACE |
| `(CI)` | Container Inherit — subfolders inherit this ACE |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `configure-lab.ps1` fails on Key Vault step | Run `az login` and confirm your account has `Key Vault Secrets User` role |
| Domain join fails | DC01 may still be initialising — wait 2 minutes and re-run from Step 3 |
| Cannot RDP to VMs | Check NSG rules allow port 3389 from your IP (`rdp_source` in tfvars) |
| "Access Denied" on shares | Confirm user is in the correct group. Run `whoami /groups` to verify |
| GPO not applying | Run `gpupdate /force` and wait 2–5 minutes. Check `gpresult /r` for errors |
| Scripts fail to run manually | Set execution policy: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process` |
| `az vm run-command` times out | VM may have restarted — `configure-lab.ps1` handles this automatically |
| `terraform init` fails | Ensure `backend.tf` has a valid storage account name and the container exists |

---

## Step 5 — Stop the VMs (End of Lab 1)

[Lab 2 — Azure RBAC Access Control](https://github.com/sammathaadams/rbac-lab-terraform) builds directly on this infrastructure — it assigns Azure RBAC roles to the FS01 VM. **Do not destroy the resource group.** Instead, stop the VMs to avoid compute charges while you move on to Lab 2:

```bash
az vm stop --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait
```

> **Note:** Stopped (deallocated) VMs do not incur compute charges, but managed disks and the Key Vault continue to accrue minimal storage costs.

When you're ready to start Lab 2, restart the VMs and give them 3–5 minutes to fully boot:

```bash
az vm start --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait
```

---

## Teardown (After Completing Both Labs)

Only destroy Lab 1 infrastructure after you have finished Lab 2. Run the Lab 2 `terraform destroy` first to remove RBAC assignments, then delete the Lab 1 resource group:

```bash
az group delete -n RG-FileServerLab --yes --no-wait
```

> **Important:** The `RG-TerraformState` resource group and storage account are shared between both labs. Delete it separately only when you are completely done with all labs:
> ```bash
> az group delete -n RG-TerraformState --yes --no-wait
> ```

---

## Project Structure

```
ntfs-lab-terraform/
├── main.tf                                   # VMs, networking, NSG
├── variables.tf                              # Input variable definitions
├── outputs.tf                                # Output values (IPs, Key Vault name)
├── versions.tf                               # Provider version constraints
├── keyvault.tf                               # Azure Key Vault + RBAC access
├── backend.tf                                # Remote state backend (Azure Blob Storage)
├── terraform.tfvars.example                  # Safe template — commit this
├── terraform.tfvars                          # Your real values — DO NOT commit
├── .gitignore                                # Excludes tfvars, state, .terraform/
├── configure-lab.ps1                         # One-shot automation (run after terraform apply)
└── scripts/
    ├── 00-promote-dc.ps1                     # Promotes DC01 to Domain Controller
    ├── 01-create-ad-users-groups.ps1         # Creates OUs, groups, and test users
    ├── 02-configure-shares-and-permissions.ps1  # SMB shares + NTFS ACLs
    ├── 03-configure-rdp-gpo.ps1              # GPO for RDP access
    ├── 04-domain-join.ps1                    # Joins FS01 and CLIENT01 to domain
    ├── 05-verify-ad.ps1                      # Automated AD verification
    ├── 05-verify-shares.ps1                  # Automated share + permission verification
    └── 06-add-rdp-users.ps1                  # Grants domain users RDP on CLIENT01
```

---

## License

MIT
