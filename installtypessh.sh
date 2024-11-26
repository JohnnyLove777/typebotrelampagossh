#!/bin/bash

# Função para instalar pacotes básicos e dependências
function instalar_dependencias {
    echo "🔄 Atualizando pacotes e instalando dependências básicas..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y software-properties-common apt-transport-https ca-certificates curl \
                        gnupg lsb-release ufw
}

# Função para instalar Docker e Docker Compose
function instalar_docker {
    echo "🐳 Instalando Docker e Docker Compose..."
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg

    # Adicionar repositório do Docker
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Instalar pacotes Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Iniciar Docker e adicionar usuário ao grupo Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo "✅ Docker instalado com sucesso!"
}

# Função para instalar NGINX e configurar firewall
function instalar_nginx {
    echo "🌐 Instalando e configurando NGINX..."
    sudo apt install -y nginx
    sudo ufw allow 'Nginx Full'
    sudo systemctl enable nginx
    sudo systemctl start nginx
    echo "✅ NGINX instalado e configurado!"
}

# Função para instalar Certbot
function instalar_certbot {
    echo "🔒 Instalando Certbot..."
    sudo apt install -y certbot python3-certbot-nginx
    echo "✅ Certbot instalado com sucesso!"
}

# Função para configurar NGINX como proxy reverso
function configurar_nginx {
    echo "🔧 Configurando NGINX para proxy reverso..."
    local dominio=$1

    # Criar arquivos de configuração para o Typebot
    sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    sudo bash -c "cat > /etc/nginx/sites-available/typebot" <<EOF
server {
    server_name typebot.${dominio} bot.${dominio} storage.${dominio};

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }

    location /viewer/ {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    sudo ln -sf /etc/nginx/sites-available/typebot /etc/nginx/sites-enabled/typebot
    sudo systemctl restart nginx
    echo "✅ Configuração do NGINX concluída!"
}

# Função para configurar SSL com Certbot
function configurar_ssl {
    echo "🔒 Configurando SSL com Certbot..."
    local email=$1
    local dominio=$2
    sudo certbot --nginx --email "$email" --redirect --agree-tos -d "typebot.$dominio" -d "bot.$dominio" -d "storage.$dominio"
    echo "✅ SSL configurado com sucesso!"
}

# Função para configurar o Typebot
function configurar_typebot {
    echo "⚙️ Configurando Typebot..."
    local dominio=$1
    local email=$2
    local senha=$3

    # Baixar docker-compose.yml e .env
    wget https://raw.githubusercontent.com/baptisteArno/typebot.io/latest/docker-compose.yml
    wget https://raw.githubusercontent.com/baptisteArno/typebot.io/latest/.env.example -O .env

    # Gerar chave de criptografia
    local encryption_secret=$(openssl rand -base64 24 | tr -d '\n')

    # Editar arquivo .env
    sed -i "s|ENCRYPTION_SECRET=.*|ENCRYPTION_SECRET=${encryption_secret}|" .env
    sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot|" .env
    sed -i "s|NEXTAUTH_URL=.*|NEXTAUTH_URL=https://typebot.${dominio}|" .env
    sed -i "s|NEXT_PUBLIC_VIEWER_URL=.*|NEXT_PUBLIC_VIEWER_URL=https://bot.${dominio}|" .env
    sed -i "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${email}|" .env
    sed -i "s|SMTP_USERNAME=.*|SMTP_USERNAME=${email}|" .env
    sed -i "s|SMTP_PASSWORD=.*|SMTP_PASSWORD=${senha}|" .env

    # Iniciar serviços com Docker Compose
    docker compose up -d
    echo "✅ Typebot configurado e rodando!"
}

# Função principal
function instalar_typebot {
    # Solicitar informações ao usuário
    echo "🔍 Por favor, forneça as informações solicitadas."
    read -p "Digite o domínio (exemplo: seu-dominio.com): " dominio
    read -p "Digite o e-mail para SSL e configuração do Typebot: " email
    read -p "Digite a senha de app do Gmail (16 caracteres): " senha

    # Executar funções
    instalar_dependencias
    instalar_docker
    instalar_nginx
    instalar_certbot
    configurar_nginx "$dominio"
    configurar_ssl "$email" "$dominio"
    configurar_typebot "$dominio" "$email" "$senha"

    echo "🎉 Instalação concluída! Typebot configurado em https://typebot.$dominio"
}

# Executar função principal
instalar_typebot
