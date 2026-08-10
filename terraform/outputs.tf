output "webapp_name" {
  value = azurerm_windows_web_app.webapp.name
}

output "webapp_url" {
  value = azurerm_windows_web_app.webapp.default_hostname
}
