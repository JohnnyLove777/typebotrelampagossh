#!/bin/bash

# Função para solicitar informações ao usuário e armazená-las em variáveis
function solicitar_informacoes {
    # Loop para solicitar e verificar o domínio
    while true; do
        read -p "Digite o domínio (por exemplo, johnny.com.br): " DOMINIO
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um domínio válido no formato, por exemplo 'johnny.com.br'."
        fi
    done    

    # Loop para solicitar e verificar o e-mail do Gmail
    while true; do
        read -p "Digite o e-mail do Gmail para cadastro do Typebot (sem espaços): " EMAIL_GMAIL
        if [[ $EMAIL_GMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um endereço de e-mail válido sem espaços."
        fi
    done

    # Loop para solicitar e verificar a senha de app do Gmail
    while true; do
        read -p "Digite a senha de app do Gmail (sem espaços, exatamente 16 caracteres): " SENHA_APP_GMAIL
        if [[ ! $SENHA_APP_GMAIL =~ [[:space:]] && ${#SENHA_APP_GMAIL} -eq 16 ]]; then
            break
        else
            echo "A senha de app deve ter exatamente 16 caracteres e não pode conter espaços."
        fi
    done

    # Armazena as informações inseridas pelo usuário nas variáveis globais
    EMAIL_GMAIL_INPUT=$EMAIL_GMAIL
    SENHA_APP_GMAIL_INPUT=$SENHA_APP_GMAIL
    DOMINIO_INPUT=$DOMINIO
}

# Função para instalar o Typebot de acordo com os comandos fornecidos
function instalar_typebot {
    # Atualiza e instala dependências necessárias
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y software-properties-common apt-transport-https ca-certificates curl \
                        python3-certbot-nginx nodejs npm git nginx docker.io docker-compose

    # Adiciona usuário ao grupo Docker
    sudo usermod -aG docker ${USER}

    # Solicita informações ao usuário
    solicitar_informacoes

    # Criação dos arquivos de configuração do NGINX
    for app in typebot viewbot minio; do
        port=""
        case $app in
            typebot) port=3001 ;;
            viewbot) port=3002 ;;
            minio) port=9000 ;;
        esac
        cat <<EOF > /etc/nginx/sites-available/$app
server {
    server_name ${app}.$DOMINIO_INPUT;
    location / {
        proxy_pass http://127.0.0.1:$port;
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
        sudo ln -s /etc/nginx/sites-available/$app /etc/nginx/sites-enabled
    done

    # Reinicia o NGINX para aplicar configurações
    sudo systemctl restart nginx

    # Solicita e instala certificados SSL usando Certbot
    sudo certbot --nginx --email $EMAIL_GMAIL_INPUT --redirect --agree-tos \
                 -d typebot.$DOMINIO_INPUT -d bot.$DOMINIO_INPUT -d storage.$DOMINIO_INPUT

    # Criação do arquivo docker-compose.yml com base nas informações fornecidas
    cat <<EOF > docker-compose.yml
version: '3.3'
services:
  typebot-db:
    image: postgres:13
    restart: always
    volumes:
      - db_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=typebot
      - POSTGRES_PASSWORD=typebot

  typebot-builder:
    image: baptistearno/typebot-builder:latest
    restart: always
    ports:
      - 3001:3000
    depends_on:
      - typebot-db
    environment: 
      - DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot
      - NEXTAUTH_URL=https://typebot.$DOMINIO_INPUT
      - NEXT_PUBLIC_VIEWER_URL=https://bot.$DOMINIO_INPUT
      - ENCRYPTION_SECRET=$(openssl rand -hex 16)
      - ADMIN_EMAIL=$EMAIL_GMAIL_INPUT
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=465
      - SMTP_USERNAME=$EMAIL_GMAIL_INPUT
      - SMTP_PASSWORD=$SENHA_APP_GMAIL_INPUT
      - SMTP_SECURE=true
      - NEXT_PUBLIC_SMTP_FROM="Suporte Typebot <$EMAIL_GMAIL_INPUT>"
      - S3_ACCESS_KEY=minio
      - S3_SECRET_KEY=minio123
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://storage.$DOMINIO_INPUT

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    restart: always
    ports:
      - 3002:3000
    environment:
      - DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot
      - NEXT_PUBLIC_VIEWER_URL=https://bot.$DOMINIO_INPUT
      - NEXTAUTH_URL=https://typebot.$DOMINIO_INPUT
      - ENCRYPTION_SECRET=$(openssl rand -hex 16)
      - S3_ACCESS_KEY=minio
      - S3_SECRET_KEY=minio123
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://storage.$DOMINIO_INPUT

  minio:
    image: minio/minio
    command: server /data
    restart: always
    ports:
      - 9000:9000
    environment:
      - MINIO_ROOT_USER=minio
      - MINIO_ROOT_PASSWORD=minio123
    volumes:
      - s3_data:/data
volumes:
  db_data:
  s3_data:
EOF

    # Inicia os contêineres
    docker compose up -d

    echo "Typebot instalado e configurado com sucesso!"
}

# Chamada das funções
instalar_typebot
