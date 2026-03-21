##############################################################################
# keyvault.tf
#
# Purpose : Store the VM admin password in Azure Key Vault so it never
#           appears in plaintext in tfvars, CLI args, or process listings.
#
# Access  : Uses Azure RBAC (not legacy access policies) -- this ties directly
#           into Lab 2 concepts and is the modern recommended approach.
#
# After apply:
#   terraform output key_vault_name  -> pass this to configure-lab.ps1
##############################################################################

# -- Random suffix so the Key Vault name is globally unique ------------------
# Key Vault names must be globally unique across all of Azure (3-24 chars).
resource "random_id" "kv_suffix" {
  byte_length = 4
}

# -- Key Vault ----------------------------------------------------------------
resource "azurerm_key_vault" "lab_kv" {
  name                = "kv-fslab-${random_id.kv_suffix.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Use Azure RBAC instead of legacy vault access policies.
  enable_rbac_authorization = true

  # Prevent accidental deletion during the lab
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# -- Grant the deploying user access to manage secrets -----------------------
resource "azurerm_role_assignment" "kv_deployer_access" {
  scope                = azurerm_key_vault.lab_kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -- Store the VM admin password as a secret ---------------------------------
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.lab_kv.id

  depends_on = [azurerm_role_assignment.kv_deployer_access]

  tags = {
    ManagedBy = "Terraform"
  }
}
