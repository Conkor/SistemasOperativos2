#!/bin/bash

set -e

echo "Verificando e instalando dependencias..."

# Verificar si curl está instalado
if ! command -v curl &> /dev/null
then
    echo "curl no está instalado. Instalándolo..."
    sudo apt update
    sudo apt install -y curl
fi

# Verificar si el usuario pertenece al grupo docker
if ! groups $USER | grep -q '\bdocker\b'; then
    echo "Tu usuario no está en el grupo docker. Agregándolo..."
    sudo usermod -aG docker $USER
    echo "✅Listo. Debes cerrar sesión y volver a entrar para que los cambios tomen efecto."
    exit 1
fi

# Instalar Docker si no está
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker CE oficial..."
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
else
    echo "✅ Docker ya instalado."
fi

# Instalar Docker Compose moderno si no está
if ! docker compose version &> /dev/null; then
    echo "Instalando Docker Compose plugin moderno..."
    mkdir -p ~/.docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose
    echo "✅ Docker Compose plugin instalado."
else
    echo "✅ Docker Compose ya disponible."
fi


echo "Verificando estructura del proyecto..."

# Crear carpetas necesarias
mkdir -p certs nginx apache haproxy

# Crear docker-compose.yml si no existe
if [ ! -f docker-compose.yml ]; then
    cat > docker-compose.yml <<EOF
version: '3.8'

services:
  web:
    build: ./nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./certs:/etc/nginx/certs
    networks:
      - webnet

  apache1:
    build: ./apache
    networks:
      - webnet

  apache2:
    build: ./apache
    networks:
      - webnet

  haproxy:
    build: ./haproxy
    ports:
      - "8080:80"
    networks:
      - webnet

networks:
  webnet:
EOF
    echo "docker-compose.yml creado."
fi

# Crear certificados si no existen
if [ ! -f certs/server.crt ] || [ ! -f certs/server.key ]; then
    echo "Generando certificados SSL auto-firmados..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout certs/server.key -out certs/server.crt \
        -subj "/C=CR/ST=SanJose/L=SanJose/O=ProyectoDocker/CN=localhost"
fi

# Crear archivos de Nginx
if [ ! -f nginx/nginx.conf ]; then
    cat > nginx/nginx.conf <<EOF
events {}

http {
    server {
        listen 443 ssl;
        server_name localhost;

        ssl_certificate /etc/nginx/certs/server.crt;
        ssl_certificate_key /etc/nginx/certs/server.key;

        location / {
            proxy_pass http://haproxy:80;
        }
    }
}
EOF
fi

if [ ! -f nginx/Dockerfile ]; then
    echo -e "FROM nginx:latest\nCOPY nginx.conf /etc/nginx/nginx.conf" > nginx/Dockerfile
fi

# Crear archivos de Apache
if [ ! -f apache/Dockerfile ]; then
    echo -e "FROM httpd:latest\nRUN echo '<h1>Hola desde Apache</h1>' > /usr/local/apache2/htdocs/index.html" > apache/Dockerfile
fi

# Crear archivos de HAProxy
if [ ! -f haproxy/haproxy.cfg ]; then
    cat > haproxy/haproxy.cfg <<EOF
global
    maxconn 2048

defaults
    mode http
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

frontend http-in
    bind *:80
    default_backend apache-backend

backend apache-backend
    balance roundrobin
    server apache1 apache1:80 check
    server apache2 apache2:80 check
EOF
fi

if [ ! -f haproxy/Dockerfile ]; then
    echo -e "FROM haproxy:latest\nCOPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg" > haproxy/Dockerfile
fi

# Verificar puertos
echo "Verificando puertos..."
for port in 80 443 8080; do
  if lsof -i:$port &> /dev/null; then
    echo "El puerto $port está en uso. Abortando."
    exit 1
  fi
done

# Desplegar contenedores
echo "Desplegando servicios..."
docker compose up -d --build 

echo "✅Entorno desplegado correctamente."
echo "Accede desde https://localhost o https://[IP_PUBLICA_VM] de tu VM (acepta el certificado auto-firmado)."
echo "Ejecuta 'docker ps' para ver los contenedores creados"
echo "Ejecuta 'docker --version' y "docker compose version" para validar las versiones instaladas"
echo "Ejecuta 'ls certs/' para ver los certificados creados"
echo "Ejecuta 'ss -tuln | grep LISTEN' para ver los certificados creados"

