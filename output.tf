
output "prod_load_balancer_url" {
  description = "URL для доступа к PROD окружению"
  value       = "http://${google_compute_global_address.prod_lb_ip.address}"
}

output "dev_load_balancer_url" {
  description = "URL для доступа к DEV окружению"
  value       = "http://${google_compute_global_address.dev_lb_ip.address}"
}

output "prod_vm_urls" {
  description = "URL для доступа к PROD виртуальным машинам"
  value       = [for vm in google_compute_instance.prod_vm : "http://${vm.network_interface[0].access_config[0].nat_ip}"]
}

output "dev_vm_urls" {
  description = "URL для доступа к DEV виртуальным машинам"
  value       = [for vm in google_compute_instance.dev_vm : "http://${vm.network_interface[0].access_config[0].nat_ip}"]
}

output "node_exporter_url" {
  description = "URL для доступа к Node Exporter на PROD виртуальных машинах"
  value       = [for vm in google_compute_instance.prod_vm : "http://${vm.network_interface[0].access_config[0].nat_ip}:9100"]
}

output "prod_vm_ips" {
  description = "IP-адреса PROD виртуальных машин"
  value       = google_compute_instance.prod_vm[*].network_interface[0].access_config[0].nat_ip
}

output "dev_vm_ips" {
  description = "IP-адреса DEV виртуальных машин"
  value       = google_compute_instance.dev_vm[*].network_interface[0].access_config[0].nat_ip
}

output "grafana_credentials" {
  description = "Учетные данные для входа в Grafana"
  value       = "Логин: admin, Пароль: admin"
  sensitive   = true
}

output "ssh_private_key" {
  description = "Содержимое приватного SSH ключа"
  value       = tls_private_key.ssh_key.private_key_openssh
  sensitive   = true
}

output "ssh_public_key" {
  description = "Содержимое публичного SSH ключа"
  value       = tls_private_key.ssh_key.public_key_openssh
}

output "ssh_private_key_path" {
  description = "Путь к сохраненному приватному SSH ключу"
  value       = local_file.private_key.filename
}

output "ssh_public_key_path" {
  description = "Путь к сохраненному публичному SSH ключу"
  value       = local_file.public_key.filename
}

output "prod_vm_zones" {
  description = "Зоны размещения PROD виртуальных машин"
  value       = google_compute_instance.prod_vm[*].zone
}

output "dev_vm_zones" {
  description = "Зоны размещения DEV виртуальных машин"
  value       = google_compute_instance.dev_vm[*].zone
}