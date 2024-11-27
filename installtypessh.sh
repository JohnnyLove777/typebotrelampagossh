#!/bin/bash

# Função para exibir mensagens com emojis
function print_info {
  echo -e "ℹ️  $1"
}

function print_success {
  echo -e "✅ $1"
}

function print_error {
  echo -e "❌ $1"
}

function print_step {
  echo -e "👉 $1"
}

# Título do script
echo -e "\n🚀 Bem-vindo ao instalador automático do Typebot!\n"

# Solicitar informações do usuário
print_step "Por favor, insira as informações necessárias para a configuração:\n"

read -p "🌐 Qual é o domínio principal (exemplo: johnnytype.fun)? " DOMAIN
read -p "📧 Qual é o seu e-mail do Gmail para configuração de SMTP? " GMAIL
read -p "🔑 Qual é a senha de app do Gmail? (Você pode gerar em https://myaccount.google.com/security) " GMAIL_APP_PASSWORD
echo

# Confirmar dados
print_info "\n📋 Resumo das informações fornecidas:"
echo "  - Domínio principal: $DOMAIN"
echo "  - E-mail do Gmail: $GMAIL"
echo "  - Senha de app do Gmail: $GMAIL_APP_PASSWORD"
read -p "Está tudo correto? (s/n): " CONFIRM

if [[ "$CONFIRM" != "s" ]]; then
  print_error "Instalação cancelada pelo usuário. Tente novamente."
  exit 1
fi

# Instalar dependências
print_step "1. Instalando dependências básicas... 🍀"
sudo apt update && sudo apt upgrade -y
sudo apt install -y software-properties-common apt-transport-https ca-certificates curl wget git nano nginx python3-certbot-nginx

# Configurar Docker
print_step "2. Instalando Docker... 🐳"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER
print_success "Docker instalado com sucesso!"

# Instalar Docker Compose
print_step "3. Instalando Docker Compose... 🔧"
sudo curl -L "https://github.com/docker/compose/releases/download/2.26.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
print_success "Docker Compose instalado com sucesso!"

# Configurar Typebot
print_step "4. Baixando e configurando o Typebot... 🤖"
wget https://raw.githubusercontent.com/baptisteArno/typebot.io/latest/docker-compose.yml
wget https://raw.githubusercontent.com/baptisteArno/typebot.io/latest/.env.example -O .env

# Gerar chave de criptografia
print_step "🔒 Gerando chave de criptografia..."
ENCRYPTION_SECRET=$(openssl rand -base64 24 | tr -d '\n' ; echo)

# Configurar .env
print_step "✍️ Configurando variáveis de ambiente..."
cat <<EOF > .env
ENCRYPTION_SECRET=$ENCRYPTION_SECRET
DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot
NODE_OPTIONS=--no-node-snapshot

# URLs do Typebot
NEXTAUTH_URL=https://typebot.$DOMAIN
NEXT_PUBLIC_VIEWER_URL=https://bot.$DOMAIN

# Email do administrador
ADMIN_EMAIL=$GMAIL

# Configurações de SMTP
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USERNAME=$GMAIL
SMTP_PASSWORD=$GMAIL_APP_PASSWORD
SMTP_SECURE=true

# Configuração do bucket S3 para armazenamento de arquivos
S3_ACCESS_KEY=minio
S3_SECRET_KEY=minio123
S3_BUCKET=typebot
S3_ENDPOINT=https://storage.$DOMAIN

# Nome do remetente de emails
NEXT_PUBLIC_SMTP_FROM="Suporte Typebot <$GMAIL>"
EOF

print_success "Variáveis de ambiente configuradas!"

# Subir os serviços
print_step "5. Subindo os contêineres do Typebot... 🚢"
docker compose up -d

# Configurar Nginx
print_step "6. Configurando o Nginx como proxy reverso... 🌐"
cat <<EOF | sudo tee /etc/nginx/sites-available/typebot > /dev/null
# Painel administrativo (Typebot Admin)
server {
    listen 80;
    server_name typebot.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Interface pública (Typebot Viewer)
server {
    listen 80;
    server_name bot.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8091;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Armazenamento S3
server {
    listen 80;
    server_name storage.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/typebot /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx
print_success "Nginx configurado com sucesso!"

# Configurar SSL
print_step "7. Configurando SSL com Certbot... 🔐"
sudo certbot --nginx -d typebot.$DOMAIN -d bot.$DOMAIN -d storage.$DOMAIN --non-interactive --agree-tos -m $GMAIL
print_success "Certificados SSL configurados!"

# Conclusão
print_success "🎉 Instalação completa! Acesse os seguintes URLs:"
echo "  - Painel administrativo: https://typebot.$DOMAIN"
echo "  - Interface pública: https://bot.$DOMAIN"
echo "  - Armazenamento S3: https://storage.$DOMAIN"

print_info "ℹ️  Certifique-se de reiniciar seu terminal ou executar 'newgrp docker' para usar o Docker sem sudo."
