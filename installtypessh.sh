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

# Função para tentar obter o certificado SSL com retries
function certbot_retry {
    local retries=5
    local count=0
    while ((count < retries)); do
        echo "Tentando obter certificado SSL..."
        sudo certbot --nginx --email "$EMAIL_GMAIL_INPUT" --redirect --agree-tos \
                     -d "typebot.$DOMINIO_INPUT" -d "bot.$DOMINIO_INPUT" -d "storage.$DOMINIO_INPUT"
        if [ $? -eq 0 ]; then
            echo "✅ Certificado SSL obtido com sucesso!"
            return 0
        fi
        echo "⚠️ Certbot falhou. Tentando novamente... ($((count+1)) de $retries)"
        ((count++))
        sleep 5
    done
    echo "❌ Certbot falhou após $retries tentativas. Verifique se o Certbot está em uso ou se há problemas de configuração."
    exit 1
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

        cat <<EOF | sudo tee /etc/nginx/sites-available/$app > /dev/null
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
        sudo ln -sf /etc/nginx/sites-available/$app /etc/nginx/sites-enabled/
    done

    # Reinicia o NGINX para aplicar configurações
    sudo systemctl restart nginx

    # Chama a função de retry para o Certbot
    certbot_retry

    # Gera uma chave secreta para criptografia
    ENCRYPTION_SECRET=$(openssl rand -hex 16)

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
      - ENCRYPTION_SECRET=$ENCRYPTION_SECRET
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
      - ENCRYPTION_SECRET=$ENCRYPTION_SECRET
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

    # Inicia os contêineres com docker-compose
    docker-compose up -d

    # Etapa 2: Verificar a existência do schema.prisma
    SCHEMA_PATH="/app/packages/prisma/postgresql/schema.prisma"
    CONTAINER_NAME="typebotrelampagossh_typebot-builder_1"

    echo "🔍 Verificando a existência do schema.prisma no contêiner '$CONTAINER_NAME'..."
    docker exec -it "$CONTAINER_NAME" sh -c "test -f $SCHEMA_PATH"
    if [ $? -ne 0 ]; then
      echo "❌ O arquivo schema.prisma não foi encontrado no caminho esperado: $SCHEMA_PATH"
      exit 1
    fi
    echo "✅ schema.prisma encontrado!"

    # Etapa 3: Executar migrações do Prisma
    echo "📦 Executando migrações do Prisma no contêiner '$CONTAINER_NAME'..."
    docker exec -it "$CONTAINER_NAME" npx prisma migrate deploy --schema "$SCHEMA_PATH"
    if [ $? -ne 0 ]; then
      echo "❌ Falha ao aplicar migrações. Verifique a configuração e o caminho do schema."
      exit 1
    fi
    echo "✅ Migrações aplicadas com sucesso!"

    # Etapa 4: Confirmar status dos contêineres
    echo "🔄 Verificando o status dos contêineres..."
    docker-compose ps

    # Etapa 5: Checar logs para garantir que não há erros
    echo "📄 Checando logs do builder para garantir que tudo esteja funcionando corretamente..."
    docker logs "$CONTAINER_NAME" | tail -n 20

    echo "🎉 Typebot configurado com sucesso e migrações aplicadas! Sistema pronto para uso."
}

# Chamada das funções
instalar_typebot
