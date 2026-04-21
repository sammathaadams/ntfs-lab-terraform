##############################################################################
# backend.tf
#
# Purpose : Store Terraform state remotely in Azure Blob Storage so the
#           state file never sits on a local disk and can be shared across
#           machines / team members.
#
# One-time setup (run once before terraform init):
#   az group create --name RG-TerraformState --location "Central US"
#   az storage account create --name <YOUR_STORAGE_ACCOUNT_NAME> \
#       --resource-group RG-TerraformState --sku Standard_LRS \
#       --encryption-services blob
#   az storage container create --name tfstate \
#       --account-name <YOUR_STORAGE_ACCOUNT_NAME>

# Then replace REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME below and run:
#   terraform init
##############################################################################

terraform {
  backend "azurerm" {
    resource_group_name  = "RG-TerraformState"
    storage_account_name = "tfstatentfslab"
    container_name       = "tfstate"
    key                  = "ntfs-lab.terraform.tfstate"
  }
}
