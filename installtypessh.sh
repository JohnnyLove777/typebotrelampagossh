#!/bin/bash

# Função para solicitar informações ao usuário e armazená-las em variáveis
function solicitar_informacoes {

    # Loop para solicitar e verificar o subdomínio do viewer
    while true; do
    read -p "Digite o subdomínio para o viewer (por exemplo, viewer.johnny.com.br): " SUBDOMINIO_VIEWER
    # Verifica se o subdomínio tem um formato válido
    if [[ $SUBDOMINIO_VIEWER =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo "Por favor, insira um subdomínio válido no formato 'bot.johnny.com.br'."
    fi
    done

    # Loop para solicitar e verificar o subdomínio do builder
    while true; do
    read -p "Digite o subdomínio para o builder (por exemplo, builder.johnny.com.br): " SUBDOMINIO_BUILDER
    # Verifica se o subdomínio tem um formato válido
    if [[ $SUBDOMINIO_BUILDER =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo "Por favor, insira um subdomínio válido no formato 'bot.johnny.com.br'."
    fi
    done

    # Loop para solicitar e verificar o e-mail do Gmail
    while true; do
        read -p "Digite o e-mail do Gmail para cadastro do Typebot (sem espaços): " EMAIL_GMAIL
        # Verifica se o e-mail tem o formato correto e não contém espaços
        if [[ $EMAIL_GMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um endereço de e-mail válido sem espaços."
        fi
    done

    # Loop para solicitar e verificar a senha de app do Gmail
    while true; do
        read -p "Digite a senha de app do Gmail (sem espaços, exatamente 16 caracteres): " SENHA_APP_GMAIL
        echo
        # Verifica se a senha não contém espaços e tem exatamente 16 caracteres
        if [[ ! $SENHA_APP_GMAIL =~ [[:space:]] && ${#SENHA_APP_GMAIL} -eq 16 ]]; then
            break
        else
            echo "A senha de app deve ter exatamente 16 caracteres e não pode conter espaços."
        fi
    done

    # Armazena as informações inseridas pelo usuário nas variáveis globais
    EMAIL_GMAIL_INPUT=$EMAIL_GMAIL
    SENHA_APP_GMAIL_INPUT=$SENHA_APP_GMAIL
    SUBDOMINIO_VIEWER_INPUT=$SUBDOMINIO_VIEWER
    SUBDOMINIO_BUILDER_INPUT=$SUBDOMINIO_BUILDER
}

# Função para instalar o Typebot de acordo com os comandos fornecidos
function instalar_typebot {
    # Atualização e upgrade do sistema
    #sudo apt update
    sudo apt upgrade -y
    sudo apt-add-repository universe

    # Instalação das dependências
    sudo apt install -y python2-minimal nodejs npm git curl apt-transport-https ca-certificates software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
    sudo apt update
    sudo apt install -y docker-ce docker-compose

    # Adiciona usuário ao grupo Docker
    sudo usermod -aG docker ${USER}

    # Solicita informações ao usuário
    solicitar_informacoes    

    # Criação do arquivo docker-compose.yml com base nas informações fornecidas
    cat <<EOF > docker-compose.yml
# Johnny Typebot Installer Without Domain
# Version 1.0

version: '3.3'
services:
  caddy-gen:
    container_name: caddy-gen
    image: 'wemakeservices/caddy-gen:latest'
    restart: always
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - {$PWD}/.typebot/caddy-certificates:/data/caddy
    ports:
      - '80:80'
      - '443:443'
    depends_on:
      - typebot-builder
      - typebot-viewer

  typebot-db:
    image: postgres:13
    restart: always
    volumes:
      - db_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=typebot
      - POSTGRES_PASSWORD=typebot

  typebot-builder:
    ports:
      - 3001:3000
    image: baptistearno/typebot-builder:latest
    restart: always
    depends_on:
      - typebot-db
    environment: 
      - DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot
      - NEXTAUTH_URL=https://${SUBDOMINIO_BUILDER_INPUT}:3001
      - NEXT_PUBLIC_VIEWER_URL=https://${SUBDOMINIO_VIEWER_INPUT}:3002
      - ENCRYPTION_SECRET=875c916244442f7d89a8f376d9d33cac
      - ADMIN_EMAIL=${EMAIL_GMAIL_INPUT}
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=465
      - SMTP_USERNAME=${EMAIL_GMAIL_INPUT}
      - SMTP_PASSWORD=${SENHA_APP_GMAIL_INPUT}
      - SMTP_SECURE=true
      - NEXT_PUBLIC_SMTP_FROM='Suporte Typebot' <${EMAIL_GMAIL_INPUT}>
      - S3_ACCESS_KEY=minio
      - S3_SECRET_KEY=minio123
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://${SUBDOMINIO_BUILDER_INPUT}:9000

  typebot-viewer:
    ports:
      - 3002:3000
    image: baptistearno/typebot-viewer:latest
    restart: always
    environment:
      - DATABASE_URL=postgresql://postgres:typebot@typebot-db:5432/typebot
      - NEXT_PUBLIC_VIEWER_URL=https://${SUBDOMINIO_VIEWER_INPUT}:3002
      - NEXTAUTH_URL=https://${SUBDOMINIO_BUILDER_INPUT}:3001
      - ENCRYPTION_SECRET=875c916244442f7d89a8f376d9d33cac
      - S3_ACCESS_KEY=minio
      - S3_SECRET_KEY=minio123
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://${SUBDOMINIO_BUILDER_INPUT}:9000

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
      - s3_data:/data

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
  db_data:
  s3_data:
EOF

    # Inicia os contêineres
    docker-compose up -d
    cd ..

    echo "Typebot instalado e configurado com sucesso!"
}

# Chamada das funções
instalar_typebot
