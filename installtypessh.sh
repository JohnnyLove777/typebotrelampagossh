#!/bin/bash

# Função para solicitar informações ao usuário
function solicitar_informacoes {
    while true; do
        read -p "Digite o domínio principal (exemplo: seu-dominio.com): " DOMINIO
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um domínio válido, como 'seu-dominio.com'."
        fi
    done

    read -p "Digite o e-mail do administrador (para login no painel): " ADMIN_EMAIL
    read -p "Digite a senha do app do Gmail para SMTP: " SENHA_APP_GMAIL
}

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
    wget https://raw.githubusercontent.com/baptisteArno/typebot.io/latest/docker-compose.yml
    wget https://raw.githubusercontent.com/baptisteArno/typebot.io/latest/.env.example -O .env

    ENCRYPTION_SECRET=$(openssl rand -base64 24 | tr -d '\n')
    cat <<EOF > .env
ENCRYPTION_SECRET=$ENCRYPTION_SECRET
DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot
NODE_OPTIONS=--no-node-snapshot
NEXTAUTH_URL=https://typebot.$DOMINIO
NEXT_PUBLIC_VIEWER_URL=https://bot.$DOMINIO
ADMIN_EMAIL=$ADMIN_EMAIL
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USERNAME=$ADMIN_EMAIL
SMTP_PASSWORD=$SENHA_APP_GMAIL
SMTP_SECURE=true
S3_ACCESS_KEY=minio
S3_SECRET_KEY=minio123
S3_BUCKET=typebot
S3_ENDPOINT=https://storage.$DOMINIO
NEXT_PUBLIC_SMTP_FROM="Suporte Typebot <$ADMIN_EMAIL>"
EOF

    echo "📦 Iniciando contêineres do Typebot..."
    docker compose up -d
    echo "✅ Typebot configurado e iniciado!"
}

# Fluxo principal
solicitar_informacoes
instalar_dependencias
instalar_docker
instalar_nginx
instalar_certbot
configurar_nginx "$DOMINIO"
configurar_ssl "$ADMIN_EMAIL" "$DOMINIO"
configurar_typebot

echo "🎉 Instalação concluída! Acesse https://typebot.$DOMINIO para usar o Typebot."
