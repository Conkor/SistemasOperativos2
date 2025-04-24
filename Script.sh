#!/bin/bash

set -e

echo "Verificando e instalando dependencias..."

# Instalar Docker si no está
if ! command -v docker &> /dev/null; then
    echo " Instalando Docker..."
    sudo apt update
    sudo apt install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
else
    echo "Docker ya instalado."
fi

# Instalar Docker Compose si no está
if ! command -v docker-compose &> /dev/null; then
    echo "Instalando Docker Compose..."
    sudo apt install -y docker-compose
else
    echo "Docker Compose ya instalado."
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
server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;

    location / {
        proxy_pass http://haproxy:80;
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
docker compose up --build -d

echo "Entorno desplegado correctamente."
echo "Accede desde https://localhost o la IP de tu VM (aceptá el certificado auto-firmado)."
