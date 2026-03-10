output "dc01_public_ip" {
  description = "Public IP for DC01 (Remote Desktop Protocol RDP)."
  value       = azurerm_public_ip.dc01.ip_address
}

output "fs01_public_ip" {
  description = "Public IP for FS01 (Remote Desktop Protocol RDP)."
  value       = azurerm_public_ip.fs01.ip_address
}

output "client01_public_ip" {
  description = "Public IP for CLIENT01 (Remote Desktop Protocol RDP)."
  value       = azurerm_public_ip.client01.ip_address
}