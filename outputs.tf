output "dc01_public_ip" {
  description = "Public IP for DC01 (Remote Desktop Protocol RDP)."
  value       = azurerm_public_ip.dc01.ip_address
}

output "dc01_private_ip" {
  description = "Private IP for DC01 (DNS / domain controller address)."
  value       = azurerm_network_interface.dc01.private_ip_address
}

output "fs01_public_ip" {
  description = "Public IP for FS01 (Remote Desktop Protocol RDP)."
  value       = azurerm_public_ip.fs01.ip_address
}

output "fs01_private_ip" {
  description = "Private IP for FS01."
  value       = azurerm_network_interface.fs01.private_ip_address
}

output "client01_public_ip" {
  description = "Public IP for CLIENT01 (Remote Desktop Protocol RDP)."
  value       = azurerm_public_ip.client01.ip_address
}

output "client01_private_ip" {
  description = "Private IP for CLIENT01."
  value       = azurerm_network_interface.client01.private_ip_address
}