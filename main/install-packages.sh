#!/bin/bash

#========================
# 0. PRELIMINARY SETUP AND ERROR HANDLING
#========================
set -e # Exit on error
exec 1>/var/log/setup-script.log 2>&1 # Redirect output to log file
trap 'echo "❌  Error occurred at line $LINENO"; exit 1' ERR

# Ensure script runs as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Este script debe ejecutarse como root"
    exit 1
fi

#========================
# 1. UPDATE SYSTEM AND PACKAGES
#========================
echo "📦 Actualizando sistema y paquetes..."
apt-get update -y && apt-get upgrade -y

# Install required packages with retry mechanism
max_retries=3
for pkg in locales curl unzip wget screen nginx nload htop python3 python3-pip nodejs npm lsof psmisc socat bc net-tools cowsay nmap jq iptables openssh-server dropbear stunnel4 cmake make g++ git; do
    for ((i=1; i<=max_retries; i++)); do
        if apt-get install -y $pkg; then
            break
        else
            echo "⚠️ Fallo al instalar $pkg, reintentando ($i/$max_retries)..."
            sleep 5
        fi
        [ $i -eq $max_retries ] && { echo "❌ No se pudo instalar $pkg"; exit 1; }
    done
done

#========================
# 1.1 CONFIGURE LOCALES FOR EL SALVADOR (FIXED)
#========================
echo "🌐 Configurando locales para El Salvador..."

# Agrega el locale si no existe
if ! grep -q "^es_SV.UTF-8 UTF-8" /etc/locale.gen; then
    echo "es_SV.UTF-8 UTF-8" >> /etc/locale.gen
fi

# Genera el locale y verifica que se creó correctamente
locale-gen es_SV.UTF-8

# Verifica que el locale esté disponible antes de actualizar
if locale -a | grep -q "es_SV.utf8"; then
    update-locale LANG=es_SV.UTF-8
else
    echo "⚠️ No se pudo generar el locale es_SV.UTF-8, usando es_MX.UTF-8 como fallback."
    if ! grep -q "^es_MX.UTF-8 UTF-8" /etc/locale.gen; then
        echo "es_MX.UTF-8 UTF-8" >> /etc/locale.gen
        locale-gen es_MX.UTF-8
    fi
    update-locale LANG=es_MX.UTF-8
fi

# Set El Salvador timezone
echo "⏰ Configurando zona horaria..."
timedatectl set-timezone America/El_Salvador

#========================
# 2. CHANGE NGINX PORT FROM 80 TO 81
#========================
if [ -f /etc/nginx/sites-available/default ]; then
    echo "🔄 Cambiando puerto de nginx a 81..."
    sed -i 's/listen 80 default_server;/listen 81 default_server;/' /etc/nginx/sites-available/default
    sed -i 's/listen \[::\]:80 default_server;/listen [::]:81 default_server;/' /etc/nginx/sites-available/default
    if nginx -t; then
        systemctl restart nginx
        echo "✅ Nginx reiniciado en puerto 81"
    else
        echo "❌ Error en la configuración de Nginx"
        exit 1
    fi
else
    echo "⚠️ Archivo de configuración de Nginx no encontrado"
fi

#========================
# 3. CONFIGURE DROPBEAR ON PORT 444
#========================
echo "🔐 Configurando Dropbear en puerto 444..."
echo "/bin/bash" > /etc/shells
echo "/usr/sbin/dropbear" >> /etc/shells
sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
if ! grep -q "^DROPBEAR_PORT=" /etc/default/dropbear; then
    echo "DROPBEAR_PORT=444" >> /etc/default/dropbear
else
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear
fi
systemctl enable dropbear
if systemctl restart dropbear; then
    echo "✅ Dropbear reiniciado en puerto 444"
else
    echo "❌ Error al reiniciar Dropbear"
    exit 1
fi

#========================
# 4. PYTHON PROXY: 80 → 22
#========================
echo "🔌 Configurando proxy Python (80 → 22)..."
mkdir -p /etc/mccproxy

cat > /etc/mccproxy/proxy.py << 'EOF'
#!/usr/bin/env python3
import socket
import threading
import logging
import time

# Configure logging
logging.basicConfig(
    filename='/var/log/mccproxy.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 80
DEST_HOST = '127.0.0.1'
DEST_PORT = 22

RESPONSE = b"HTTP/1.1 101 Web Socket Protocol\r\nContent-length: 999999999\r\n\r\n"

def forward(source, destination, direction):
    try:
        while True:
            data = source.recv(4096)
            if not data:
                logging.info(f"Conexión cerrada en dirección {direction}")
                break
            destination.sendall(data)
    except Exception as e:
        logging.error(f"Error en forward {direction}: {e}")
    finally:
        try:
            source.close()
            destination.close()
        except:
            pass

def handle_client(client_socket, addr):
    try:
        logging.info(f"Nueva conexión desde {addr}")
        req = client_socket.recv(1024)
        if b"HTTP" in req:
            client_socket.sendall(RESPONSE)
        remote = socket.create_connection((DEST_HOST, DEST_PORT), timeout=10)
        threading.Thread(target=forward, args=(client_socket, remote, "client->server")).start()
        threading.Thread(target=forward, args=(remote, client_socket, "server->client")).start()
    except Exception as e:
        logging.error(f"Error manejando cliente {addr}: {e}")
        client_socket.close()

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.settimeout(30)  # Timeout to prevent hanging
    try:
        server.bind((LISTEN_HOST, LISTEN_PORT))
        server.listen(100)
        logging.info(f"Proxy escuchando en {LISTEN_HOST}:{LISTEN_PORT} y redirigiendo a {DEST_HOST}:{DEST_PORT}")
        print(f"Proxy escuchando en {LISTEN_HOST}:{LISTEN_PORT}>{DEST_PORT}")
        while True:
            try:
                client, addr = server.accept()
                threading.Thread(target=handle_client, args=(client, addr)).start()
            except socket.timeout:
                logging.warning("Timeout en servidor, continuando...")
                continue
            except Exception as e:
                logging.error(f"Error en servidor: {e}")
                time.sleep(1)  # Prevent tight loop on errors
    except Exception as e:
        logging.error(f"Error iniciando servidor: {e}")
    finally:
        server.close()

if __name__ == "__main__":
    main()
EOF

chmod +x /etc/mccproxy/proxy.py

cat > /etc/systemd/system/mccproxy.service <<EOF
[Unit]
Description=Proxy TCP McCarthey (80 → 22)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /etc/mccproxy/proxy.py
Restart=always
RestartSec=5
User=root
LimitNOFILE=65535
TimeoutStartSec=10
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mccproxy
if systemctl restart mccproxy; then
    echo "✅ Proxy Python iniciado"
else
    echo "❌ Error al iniciar proxy Python"
    exit 1
fi

#========================
# 5. BADVPN-UDPGW ON PORT 7300
#========================
echo "🌐 Configurando Badvpn-UDPGW en puerto 7300..."
if [ ! -d /opt/badvpn ]; then
    git clone https://github.com/ambrop72/badvpn.git /opt/badvpn
fi
mkdir -p /opt/badvpn/build && cd /opt/badvpn/build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j$(nproc)
cp udpgw/badvpn-udpgw /usr/bin/badvpn-udpgw
chmod +x /usr/bin/badvpn-udpgw

cat > /etc/systemd/system/badvpn.service <<EOF
[Unit]
Description=Badvpn UDPGW Service
After=network.target

[Service]
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --client-socket-sndbuf 65535
Restart=always
RestartSec=5
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable badvpn
if systemctl start badvpn; then
    echo "✅ Badvpn iniciado"
else
    echo "❌ Error al iniciar Badvpn"
    exit 1
fi

#========================
# 6. STUNNEL CONFIG AND CERTIFICATE
#========================
echo "🔒 Configurando Stunnel..."
mkdir -p /etc/stunnel/certs

if [ ! -f /etc/stunnel/certs/stunnel.pem ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/stunnel/certs/stunnel.key \
        -out /etc/stunnel/certs/stunnel.crt \
        -subj "/C=SV/ST=San Salvador/L=San Salvador/O=Default/OU=Default/CN=localhost"
    cat /etc/stunnel/certs/stunnel.key /etc/stunnel/certs/stunnel.crt > /etc/stunnel/certs/stunnel.pem
    chmod 600 /etc/stunnel/certs/stunnel.pem
fi

cat > /etc/stunnel/stunnel.conf <<EOF
cert = /etc/stunnel/certs/stunnel.pem
pid = /var/run/stunnel4.pid
client = no
foreground = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
output = /var/log/stunnel4.log

[python-https]
accept = 443
connect = 80
TIMEOUTidle = 30
TIMEOUTclose = 10
EOF

sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
systemctl enable stunnel4
if systemctl restart stunnel4; then
    echo "✅ Stunnel reiniciado"
else
    echo "❌ Error al reiniciar Stunnel"
    exit 1
fi

#========================
# 7. SYSTEM OPTIMIZATION
#========================
echo "⚙️ Optimizando configuración del sistema..."
echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf
echo "net.ipv4.tcp_rmem=4096 87380 16777216" >> /etc/sysctl.conf
echo "net.ipv4.tcp_wmem=4096 65536 16777216" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=htcp" >> /etc/sysctl.conf
sysctl -p

#========================
# 8. MONITORING SERVICE
#========================
echo "🛠️ Configurando monitoreo de servicios..."
cat > /usr/local/bin/monitor-services.sh <<EOF
#!/bin/bash
for service in nginx dropbear mccproxy badvpn stunnel4; do
    if ! systemctl is-active --quiet \$service; then
        echo "⚠️ Servicio \$service detenido, reiniciando..."
        systemctl restart \$service
        logger "Servicio \$service reiniciado"
    fi
done
EOF

chmod +x /usr/local/bin/monitor-services.sh

cat > /etc/systemd/system/monitor-services.timer <<EOF
[Unit]
Description=Timer para monitoreo de servicios

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/monitor-services.service <<EOF
[Unit]
Description=Monitoreo de servicios críticos

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor-services.sh
EOF

systemctl daemon-reload
systemctl enable monitor-services.timer
systemctl start monitor-services.timer

#========================
# 9. FINAL VERIFICATION
#========================
echo -e "\n✅ Configuración completada"
echo "📡 Verificando puertos activos..."
ss -tulnp | grep -E ':22|:80|:81|:443|:444|:7300'

# Display log file location
echo "📜 Registro disponible en /var/log/setup-script.log"
