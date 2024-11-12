#!/bin/bash

# Função para solicitar informações ao usuário e armazená-las em variáveis
function solicitar_informacoes {
    while true; do
        read -p "Digite o domínio (por exemplo, johnny.com.br): " DOMINIO
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um domínio válido no formato, por exemplo 'johnny.com.br'."
        fi
    done    

    while true; do
        read -p "Digite o e-mail do Gmail para cadastro do Typebot (sem espaços): " EMAIL_GMAIL
        if [[ $EMAIL_GMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um endereço de e-mail válido sem espaços."
        fi
    done

    while true; do
        read -p "Digite a senha de app do Gmail (sem espaços, exatamente 16 caracteres): " SENHA_APP_GMAIL
        echo
        if [[ ! $SENHA_APP_GMAIL =~ [[:space:]] && ${#SENHA_APP_GMAIL} -eq 16 ]]; then
            break
        else
            echo "A senha de app deve ter exatamente 16 caracteres e não pode conter espaços."
        fi
    done

    EMAIL_GMAIL_INPUT=$EMAIL_GMAIL
    SENHA_APP_GMAIL_INPUT=$SENHA_APP_GMAIL
    DOMINIO_INPUT=$DOMINIO
}

# Função para instalar o Typebot com bibliotecas atualizadas
function instalar_typebot {
    sudo apt update
    sudo apt upgrade -y
    sudo apt install -y software-properties-common curl apt-transport-https ca-certificates nginx certbot python3-certbot-nginx
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update
    sudo apt install -y docker-ce docker-compose

    sudo usermod -aG docker ${USER}

    solicitar_informacoes

    # Criação do arquivo .env
cat <<EOF > .env
ENCRYPTION_SECRET=$(openssl rand -base64 32)
DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot
NEXTAUTH_URL=https://typebot.$DOMINIO_INPUT
NEXT_PUBLIC_VIEWER_URL=https://bot.$DOMINIO_INPUT
ADMIN_EMAIL=$EMAIL_GMAIL_INPUT
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USERNAME=$EMAIL_GMAIL_INPUT
SMTP_PASSWORD=$SENHA_APP_GMAIL_INPUT
SMTP_SECURE=true
NEXT_PUBLIC_SMTP_FROM="Suporte Typebot <$EMAIL_GMAIL_INPUT>"
S3_ACCESS_KEY=minio
S3_SECRET_KEY=minio123
S3_BUCKET=typebot
S3_ENDPOINT=https://storage.$DOMINIO_INPUT
EOF

    # Criação do arquivo docker-compose.yml
    cat <<EOF > docker-compose.yml
version: '3.3'

services:
  typebot-db:
    image: postgres:16
    restart: always
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=typebot
      - POSTGRES_PASSWORD=typebot
    healthcheck:
        test: ["CMD-SHELL", "pg_isready -U postgres"]
        interval: 5s
        timeout: 5s
        retries: 5

  typebot-builder:
    image: baptistearno/typebot-builder:latest
    restart: always
    depends_on:
      typebot-db:
        condition: service_healthy
    ports:
      - '8080:3000'
    extra_hosts:
      - 'host.docker.internal:host-gateway'
    env_file: .env

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    depends_on:
      typebot-db:
        condition: service_healthy
    restart: always
    ports:
      - '8081:3000'
    env_file: .env

  mail:
    image: bytemark/smtp
    restart: always

  minio:
    image: minio/minio
    command: server /data
    ports:
      - '9000:9000'
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: minio123
    volumes:
      - s3-data:/data

  createbuckets:
    image: minio/mc
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      sleep 10;
      /usr/bin/mc config host add minio http://minio:9000 minio minio123;
      /usr/bin/mc mb minio/typebot;
      /usr/bin/mc anonymous set public minio/typebot/public;
      exit 0;
      "

volumes:
  db-data:
  s3-data:

EOF

    # Configuração do Nginx
    cat <<EOF > /etc/nginx/sites-available/typebot
server {
    server_name typebot.$DOMINIO_INPUT;
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
EOF

    cat <<EOF > /etc/nginx/sites-available/viewbot
server {
    server_name bot.$DOMINIO_INPUT;
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
EOF

    cat <<EOF > /etc/nginx/sites-available/minio
server {
    server_name storage.$DOMINIO_INPUT;
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

    # Ativa os sites no Nginx
    sudo ln -s /etc/nginx/sites-available/typebot /etc/nginx/sites-enabled
    sudo ln -s /etc/nginx/sites-available/viewbot /etc/nginx/sites-enabled
    sudo ln -s /etc/nginx/sites-available/minio /etc/nginx/sites-enabled

    # Configuração do SSL com Certbot
    sudo certbot --nginx --email $EMAIL_GMAIL_INPUT --redirect --agree-tos -d typebot.$DOMINIO_INPUT -d bot.$DOMINIO_INPUT -d storage.$DOMINIO_INPUT

    # Inicia os contêineres
    docker compose up -d

    echo "Typebot instalado e configurado com sucesso!"
}

instalar_typebot
