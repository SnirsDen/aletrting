#!/bin/bash

# Получаем IP адреса из переменных
PROD_VM_1_IP=${prod_vm_1_ip}
PROD_VM_2_IP=${prod_vm_2_ip}
DEV_VM_1_IP=${dev_vm_1_ip}
DEV_VM_2_IP=${dev_vm_2_ip}

echo "Starting monitoring setup..."
echo "Production VMs: $PROD_VM_1_IP, $PROD_VM_2_IP"
echo "Development VMs: $DEV_VM_1_IP, $DEV_VM_2_IP"

# Создаем директории
sudo mkdir -p /opt/monitoring/dashboards
sudo chown ubuntu:ubuntu /opt/monitoring/dashboards

# Настройка SSH
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

# Установка Docker
echo "Installing Docker..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Установка Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/v2.12.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Создаем директорию для конфигурации мониторинга
mkdir -p /opt/monitoring
cd /opt/monitoring

# Создаем конфигурационный файл Prometheus
cat > prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: /metrics

  - job_name: 'node'
    static_configs:
      - targets: 
        - '${prod_vm_1_ip}:9100'
        - '${prod_vm_2_ip}:9100'
        - '${dev_vm_1_ip}:9100'
        - '${dev_vm_2_ip}:9100'
    metrics_path: /metrics
    scrape_interval: 15s
    scrape_timeout: 10s

EOF

# Создаем docker-compose.yml
echo "Creating Docker Compose configuration..."
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    volumes:
      - grafana_data:/var/lib/grafana
      - ./dashboards:/var/lib/grafana/dashboards
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

volumes:
  prometheus_data:
  grafana_data:
EOF

# Запускаем контейнеры
echo "Starting Docker containers..."
/usr/local/bin/docker-compose up -d

# Установка jq для парсинга JSON
apt-get install -y jq

# Выводим информацию о targets
echo "Detailed targets status:"
sleep 10  # Даем время Prometheus запуститься
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl: .scrapeUrl, health: .health, lastError: .lastError}'

# Ждем немного перед настройкой Grafana
echo "Waiting for services to start..."
sleep 30

# Настраиваем источник данных Prometheus в Grafana
echo "Configuring Grafana data source..."
until curl -s -f http://localhost:3000 > /dev/null; do
  echo "Waiting for Grafana to be ready..."
  sleep 5
done

curl -X POST "http://localhost:3000/api/datasources" \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d '{
    "name":"Prometheus",
    "type":"prometheus",
    "url":"http://prometheus:9090",
    "access":"proxy",
    "isDefault":true
  }'

# Декодируем и сохраняем дашборд, если предоставлена переменная dashboard_content
if [ -n "${dashboard_content}" ]; then
    echo "Got dashboard content from variable, saving to file..."
    echo ${dashboard_content} | base64 -d > /opt/monitoring/dashboards/my-dashboard.json
    sudo chown ubuntu:ubuntu /opt/monitoring/dashboards/my-dashboard.json

    echo "Importing custom dashboard..."
    DASHBOARD_JSON=$(cat /opt/monitoring/dashboards/my-dashboard.json)
    
    # Получаем UID источника данных Prometheus
    datasource_uid=$(curl -s "http://localhost:3000/api/datasources/name/Prometheus" \
        -u admin:admin | grep -o '"uid":"[^"]*' | cut -d'"' -f4)
    
    if [ ! -z "$datasource_uid" ]; then
        # Заменяем переменные в дашборде - экранируем DS_PROMETHEUS для Terraform
        DASHBOARD_JSON=$(echo "$DASHBOARD_JSON" | sed "s/\\\$${DS_PROMETHEUS}/$datasource_uid/g")
    fi
    
    curl -X POST "http://localhost:3000/api/dashboards/db" \
        -H "Content-Type: application/json" \
        -u admin:admin \
        -d "{
            \"dashboard\": $DASHBOARD_JSON,
            \"overwrite\": true,
            \"folderId\": 0
        }"
else
    # Создаем простой дашборд по умолчанию
    echo "Creating default dashboard..."
    cat > /opt/monitoring/dashboards/default-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Default Monitoring Dashboard",
    "tags": ["monitoring"],
    "timezone": "browser",
    "panels": [],
    "schemaVersion": 16,
    "version": 0,
    "refresh": "5s"
  }
}
EOF
fi

echo "Monitoring setup completed successfully!"
echo "Prometheus: http://localhost:9090"
echo "Grafana: http://localhost:3000 (admin/admin)"