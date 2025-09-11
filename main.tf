provider "google" {
  project = var.project_id
  region  = var.region
  
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_openssh
  filename        = "${path.module}/terraform_gcp"
  file_permission = "0600"
}

# Сохранение публичного ключа локально
resource "local_file" "public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "${path.module}/terraform_gcp.pub"
}

resource "google_compute_instance" "prod_vm" {
  count        = 2
  name         = "prod-${count.index + 1}"
  machine_type = "e2-standard-2"
  zone         = element(var.prod_zones, count.index)
  tags         = ["http-server", "prod"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 35
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }

  metadata = {
    ssh-keys       = "ubuntu:${tls_private_key.ssh_key.public_key_openssh}"
    startup-script = file("${path.module}/scripts/website_setup_script.sh")
  }
}

resource "google_compute_instance" "dev_vm" {
  count        = 2
  name         = "dev-${count.index + 1}"
  machine_type = "e2-small"
  zone         = element(var.dev_zones, count.index)
  tags         = ["http-server", "dev"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 15
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }

  metadata = {
    ssh-keys       = "ubuntu:${tls_private_key.ssh_key.public_key_openssh}"
    startup-script = file("${path.module}/scripts/website_setup_script.sh")
  }
}

resource "google_compute_instance" "monitoring_vm" {
  name         = "monitoring"
  machine_type = "e2-medium"
  zone         = "europe-west2-a"
  tags         = ["monitoring", "http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh_key.public_key_openssh}"
    startup-script = templatefile("${path.module}/scripts/monitoring_setup.sh", {
      prod_vm_1_ip      = google_compute_instance.prod_vm[0].network_interface.0.network_ip
      prod_vm_2_ip      = google_compute_instance.prod_vm[1].network_interface.0.network_ip
      dev_vm_1_ip       = google_compute_instance.dev_vm[0].network_interface.0.network_ip
      dev_vm_2_ip       = google_compute_instance.dev_vm[1].network_interface.0.network_ip
      dashboard_content = filebase64("${path.module}/monitoring/my-dashboard.json")
    })}

  timeouts {
    create = "20m" 
    update = "20m"
  }

  # Копируем файл дашборда через provisioner
  provisioner "file" {
    source      = "${path.module}/monitoring/my-dashboard.json"
    destination = "/tmp/my-dashboard.json"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh_key.private_key_openssh
      host        = self.network_interface[0].access_config[0].nat_ip
      timeout     = "20m"
    }
  }

  # Перемещаем файл в нужную директорию
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/monitoring/dashboards",
      "sudo mv /tmp/my-dashboard.json /opt/monitoring/dashboards/",
      "sudo chown ubuntu:ubuntu /opt/monitoring/dashboards/my-dashboard.json"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh_key.private_key_openssh
      host        = self.network_interface[0].access_config[0].nat_ip
      timeout     = "20m"
    }
  }
}

resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"] # В продакшене ограничьте доступ определенным IP
  target_tags   = ["monitoring", "prod", "dev"]
}

resource "google_compute_firewall" "grafana" {
  name    = "allow-grafana"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = ["0.0.0.0/0"] # В продакшене ограничьте доступ
  target_tags   = ["monitoring"]
}

resource "google_compute_firewall" "prometheus" {
  name    = "allow-prometheus"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["9090"]
  }

  source_ranges = ["0.0.0.0/0"] # В продакшене ограничьте доступ
  target_tags   = ["monitoring"]
}

resource "google_compute_firewall" "node_exporter" {
  name    = "allow-node-exporter"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["9100"]
  }

  source_ranges = ["0.0.0.0/0"] # Разрешаем доступ изнутри VPC
  target_tags   = ["prod", "dev"]
}

# Добавляем выводы для мониторинга
output "monitoring_vm_ip" {
  description = "IP-адрес виртуальной машины мониторинга"
  value       = google_compute_instance.monitoring_vm.network_interface.0.access_config.0.nat_ip
}

output "grafana_url" {
  description = "URL для доступа к Grafana"
  value       = "http://${google_compute_instance.monitoring_vm.network_interface.0.access_config.0.nat_ip}:3000"
}

output "prometheus_url" {
  description = "URL для доступа к Prometheus"
  value       = "http://${google_compute_instance.monitoring_vm.network_interface.0.access_config.0.nat_ip}:9090"
}

# Создаем правило firewall для HTTP
resource "google_compute_firewall" "http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

# Создаем health check для балансировщика
resource "google_compute_health_check" "http_health_check" {
  name = "http-health-check"

  http_health_check {
    port = 80
  }
}

# Создаем бэкенд-сервис для PROD
resource "google_compute_backend_service" "prod_backend" {
  name          = "prod-backend"
  protocol      = "HTTP"
  port_name     = "http"
  timeout_sec   = 10
  health_checks = [google_compute_health_check.http_health_check.id]

  dynamic "backend" {
    for_each = google_compute_instance_group.prod_groups
    content {
      group = backend.value.id
    }
  }
}

# Создаем бэкенд-сервис для DEV
resource "google_compute_backend_service" "dev_backend" {
  name          = "dev-backend"
  protocol      = "HTTP"
  port_name     = "http"
  timeout_sec   = 10
  health_checks = [google_compute_health_check.http_health_check.id]

  dynamic "backend" {
    for_each = google_compute_instance_group.dev_groups
    content {
      group = backend.value.id
    }
  }
}

resource "google_compute_instance_group" "prod_groups" {
  count = 2
  name  = "prod-group-${count.index + 1}"
  zone  = element(var.prod_zones, count.index)

  instances = [google_compute_instance.prod_vm[count.index].id]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_instance_group" "dev_groups" {
  count = 2
  name  = "dev-group-${count.index + 1}"
  zone  = element(var.dev_zones, count.index)

  instances = [google_compute_instance.dev_vm[count.index].id]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_url_map" "prod_url_map" {
  name            = "prod-load-balancer"
  default_service = google_compute_backend_service.prod_backend.id
}

resource "google_compute_url_map" "dev_url_map" {
  name            = "dev-load-balancer"
  default_service = google_compute_backend_service.dev_backend.id
}

# Создаем target HTTP proxy для PROD
resource "google_compute_target_http_proxy" "prod_http_proxy" {
  name    = "prod-http-proxy"
  url_map = google_compute_url_map.prod_url_map.id
}

# Создаем target HTTP proxy для DEV
resource "google_compute_target_http_proxy" "dev_http_proxy" {
  name    = "dev-http-proxy"
  url_map = google_compute_url_map.dev_url_map.id
}

# Создаем глобальный адрес для PROD
resource "google_compute_global_address" "prod_lb_ip" {
  name = "prod-lb-ip"
}

# Создаем глобальный адрес для DEV
resource "google_compute_global_address" "dev_lb_ip" {
  name = "dev-lb-ip"
}

# Создаем правило перенаправления для PROD
resource "google_compute_global_forwarding_rule" "prod_http_forwarding_rule" {
  name       = "prod-http-forwarding-rule"
  target     = google_compute_target_http_proxy.prod_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.prod_lb_ip.address
}

# Создаем правило перенаправления для DEV
resource "google_compute_global_forwarding_rule" "dev_http_forwarding_rule" {
  name       = "dev-http-forwarding-rule"
  target     = google_compute_target_http_proxy.dev_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.dev_lb_ip.address
}