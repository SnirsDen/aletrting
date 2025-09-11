pipeline {
    agent any
    environment {
        GOOGLE_CREDENTIALS = credentials('gcp-service-account-key')
        TF_VAR_project_id = 'doplom-471707'
        TF_VAR_region = 'europe-west2'
        TF_VAR_prod_zones = '["europe-west2-a", "europe-west2-b"]'
        TF_VAR_dev_zones = '["europe-west3-a", "europe-west3-b"]'
        TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
        TELEGRAM_CHAT_ID = credentials('telegram-chat-id')
    }
    stages {
        stage('Оповещение о начале') {
            steps {
                script {
                    sendTelegramMessage("🚀 Запуск сборки ${env.JOB_NAME} #${env.BUILD_NUMBER}")
                }
            }
        }
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/SnirsDen/aletrting.git'
            }
        }
        stage('Terraform Init') {
            steps {
                bat 'terraform init'
            }
        }
        stage('Terraform Validate') {
            steps {
                bat 'terraform validate'
            }
        }
        stage('Terraform Plan') {
            steps {
                bat 'terraform plan -out=tfplan'
            }
        }
        stage('Terraform Apply') {
            steps {
                bat 'terraform apply -auto-approve tfplan'
            }
        }
        stage('Получение выходных данных') {
            steps {
                bat 'terraform output -json > outputs.json'
                script {
                    def outputs = readJSON file: 'outputs.json'
                    env.GRAFANA_URL = outputs.grafana_url.value
                    env.PROMETHEUS_URL = outputs.prometheus_url.value
                    env.MONITORING_IP = outputs.monitoring_vm_ip.value
                }
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'outputs.json', fingerprint: true
        }
        success {
            script {
                def message = """
✅ Сборка ${env.JOB_NAME} #${env.BUILD_NUMBER} успешно завершена

📊 Доступ к мониторингу:
- Grafana: ${env.GRAFANA_URL}
- Prometheus: ${env.PROMETHEUS_URL}
- IP мониторинга: ${env.MONITORING_IP}

Подробности: ${env.BUILD_URL}
"""
                sendTelegramMessage(message)
            }
        }
        failure {
            script {
                def message = """
❌ Сборка ${env.JOB_NAME} #${env.BUILD_NUMBER} завершилась с ошибкой

Проверьте логи: ${env.BUILD_URL}console
"""
                sendTelegramMessage(message)
            }
        }
        cleanup {
            bat 'del /f /q terraform.tfstate* || true'
            bat 'del /f /q tfplan || true'
        }
    }
}


// Функция для отправки сообщения в Telegram
def sendTelegramMessage(String message, String parseMode = null) {
    def telegramUrl = "https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage"
    
    def body = [
        chat_id: env.TELEGRAM_CHAT_ID,
        text: message
    ]
    
    if (parseMode) {
        body.parse_mode = parseMode
    }
    
    def jsonBody = new groovy.json.JsonBuilder(body).toString()
    
    bat """
        powershell -Command "
            \$response = Invoke-RestMethod -Uri '${telegramUrl}' -Method Post -Body '\${jsonBody}' -ContentType 'application/json; charset=utf-8' -UseBasicParsing
            Write-Output \$response
        "
    """
}