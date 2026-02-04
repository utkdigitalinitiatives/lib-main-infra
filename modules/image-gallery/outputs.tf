output "gallery_id" {
  description = "ID of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.drupal.id
}

output "gallery_name" {
  description = "Name of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.drupal.name
}

output "gallery_unique_name" {
  description = "Unique name of the gallery (for Packer)"
  value       = azurerm_shared_image_gallery.drupal.unique_name
}

output "image_definition_id" {
  description = "ID of the image definition"
  value       = azurerm_shared_image.drupal.id
}

output "image_definition_name" {
  description = "Name of the image definition"
  value       = azurerm_shared_image.drupal.name
}
