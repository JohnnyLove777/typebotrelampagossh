#!/bin/bash

# Função para instalar Docker e dependências
function instalar_docker_e_compose {
    echo "🔄 Atualizando pacotes e configurando repositórios..."

    # Atualizar pacotes e adicionar repositórios necessários
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y ca-certificates curl gnupg

    # Adicionar chave GPG do Docker
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Adicionar repositório do Docker
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Atualizar pacotes novamente e instalar o Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Iniciar Docker e adicionar o usuário ao grupo Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER

    echo "✅ Docker e Docker Compose Plugin instalados com sucesso!"
}

# Função para solicitar informações ao usuário
function solicitar_informacoes {
    while true; do
        read -p "Digite o domínio (ex: typebot.seudominio.com): " DOMINIO
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "❌ Por favor, insira um domínio válido (ex: typebot.seudominio.com)."
        fi
    done

    read -p "Digite o email para o Certbot e notificações (ex: seu-email@gmail.com): " ADMIN_EMAIL

    read -p "Digite a senha de aplicativo do Gmail para envio de emails: " SENHA_APP_GMAIL
}

# Função para configurar o NGINX
function configurar_nginx {
    echo "🔧 Configurando NGINX para proxy reverso..."
    sudo tee /etc/nginx/sites-available/typebot > /dev/null <<EOF
server {
    server_name typebot.$DOMINIO bot.$DOMINIO storage.$DOMINIO;

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
}
server {
    server_name bot.$DOMINIO;

    location / {
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
server {
    server_name storage.$DOMINIO;

    location / {
        proxy_pass http://127.0.0.1:9000;
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

    sudo ln -sf /etc/nginx/sites-available/typebot /etc/nginx/sites-enabled/
    sudo systemctl restart nginx
}

# Função para configurar o Certbot
function configurar_certbot {
    echo "🔒 Configurando SSL com Certbot..."
    sudo certbot --nginx --email $ADMIN_EMAIL --agree-tos --redirect \
        -d typebot.$DOMINIO -d bot.$DOMINIO -d storage.$DOMINIO
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
}

# Função principal
function instalar_typebot {
    instalar_dependencias
    solicitar_informacoes
    configurar_nginx
    configurar_certbot
    configurar_typebot

    echo "🎉 Instalação completa! Acesse:"
    echo " - Typebot Builder: https://typebot.$DOMINIO"
    echo " - Typebot Viewer: https://bot.$DOMINIO"
    echo " - Storage (MinIO): https://storage.$DOMINIO"
}

# Executa a função principal
instalar_typebot
