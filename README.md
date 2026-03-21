# NTFS File Server Lab

Azure IaC for Windows Server administration — Active Directory, NTFS access control, SMB file services, and Group Policy. Deployed with Terraform, configured automatically with PowerShell and Azure Run Command.

---

## What You'll Learn

- Deploying Windows Server infrastructure on Azure using Terraform
- Storing secrets securely with Azure Key Vault (RBAC-based)
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
│   ┌─────────────────────┐                                   │
│   │   Azure Key Vault   │  ← VM credentials stored here     │
│   └─────────────────────┘                                   │
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

## Step 1 — Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and set your values:

```hcl
location       = "Central US"
rdp_source     = "YOUR_PUBLIC_IP/32"   # Find yours at whatismyip.com
admin_password = "YourStrongPassword!" # Min 12 chars, upper+lower+number+symbol
server_vm_size = "Standard_B2as_v2"
client_vm_size = "Standard_B2as_v2"
```

> **Security Note:** `terraform.tfvars` is excluded from git via `.gitignore`. Never commit passwords or sensitive data. The password you set here will be stored in Azure Key Vault during deployment.

---

## Step 2 — Deploy Infrastructure

```bash
# Login to Azure
az login

# Initialise providers
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

This single command replaces all manual RDP sessions. It pushes PowerShell scripts to each VM through the Azure agent — no WinRM, no firewall changes needed.

```powershell
.\configure-lab.ps1 -KeyVaultName "kv-fslab-a1b2c3d4"
```

The script runs through these stages automatically:

| Stage | What Happens | VM |
|-------|-------------|----|
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

---

## Pause the Lab

If you plan to continue with [Lab 2 — Azure RBAC Access Control](https://github.com/sammathaadams/rbac-lab-terraform), keep the resource group and VMs in place. Stop them to avoid compute charges while you're not actively using them:

```bash
az vm stop --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait
```

Restart them before picking up Lab 2:

```bash
az vm start --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait
```

> **Note:** Stopped (deallocated) VMs do not incur compute charges, but managed disks and the Key Vault continue to accrue minimal storage costs.

---

## Teardown

Delete the resource group when finished — this removes all VMs, disks, NICs, the VNet, and the Key Vault:

```bash
az group delete -n RG-FileServerLab --yes --no-wait
```

Then clear Terraform state to keep it in sync:

```bash
terraform state rm $(terraform state list | tr '\n' ' ')
```

> **Important:** Always destroy resources when finished to avoid ongoing charges.

---

## Project Structure

```
ntfs-lab-terraform/
├── main.tf                                   # VMs, networking, NSG
├── variables.tf                              # Input variable definitions
├── outputs.tf                                # Output values (IPs, Key Vault name)
├── versions.tf                               # Provider version constraints
├── keyvault.tf                               # Azure Key Vault + RBAC access
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
