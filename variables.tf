variable "location" {
  description = "Azure region (example: West US)."
  type        = string
  default     = "West US"
}

variable "resource_group_name" {
  description = "Resource Group name."
  type        = string
  default     = "RG-FileServerLab"
}

variable "vnet_name" {
  description = "Virtual Network (VNet = Virtual Network) name."
  type        = string
  default     = "VNET-FileServerLab"
}

variable "subnet_name" {
  description = "Subnet name."
  type        = string
  default     = "Subnet-Servers"
}

variable "vnet_cidr" {
  description = "Virtual Network CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR."
  type        = string
  default     = "10.0.1.0/24"
}

variable "nsg_name" {
  description = "Network Security Group (NSG) name."
  type        = string
  default     = "NSG-RDP"
}

variable "rdp_source" {
  description = "Source CIDR allowed to Remote Desktop Protocol (RDP) port 3389. Use your public IP /32 for best security."
  type        = string
  default     = "*"
}

variable "admin_username" {
  description = "Local Windows Administrator username on all VMs."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Local Windows Administrator password on all VMs."
  type        = string
  sensitive   = true
}

variable "server_vm_size" {
  description = "VM size for DC01 and FS01."
  type        = string
  default     = "Standard_B2as_v2"
}

variable "client_vm_size" {
  description = "VM size for CLIENT01."
  type        = string
  default     = "Standard_B2as_v2"
}