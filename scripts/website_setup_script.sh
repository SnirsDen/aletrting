 #!/bin/bash
  
  # Установка nginx 
  sudo apt-get update
  sudo apt-get install -y nginx
  sudo apt-get install -y nginx google-cloud-sdk

  sudo mkdir -p /var/www/html
  sudo rm -f /var/www/html/index.nginx-debian.html
  sudo git clone https://github.com/SnirsDen/HTML_test.git /var/www/html
  
  # Перезапускаем nginx
  sudo systemctl restart nginx
  sudo systemctl enable nginx

  # Установка Node Exporter для мониторинга
wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
tar xzf node_exporter-1.3.1.linux-amd64.tar.gz
cd node_exporter-1.3.1.linux-amd64
./node_exporter &

# Добавляем Node Exporter в автозагрузку
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/root/node_exporter-1.3.1.linux-amd64/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter