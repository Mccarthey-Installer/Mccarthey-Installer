#!/bin/bash

#========================
# 1. ACTUALIZAR SISTEMA Y PAQUETES
#========================
apt update -y && apt upgrade -y

# Configurar locales para idioma y formato de El Salvador
apt install -y locales
sed -i '/es_SV.UTF-8/s/^# //g' /etc/locale.gen
locale-gen
update-locale LANG=es_SV.UTF-8

# Establecer zona horaria de El Salvador
timedatectl set-timezone America/El_Salvador

apt install -y curl unzip wget screen nginx nload htop python3 python3-pip \
nodejs npm lsof psmisc socat bc net-tools cowsay nmap jq iptables openssh-server \
dropbear stunnel4 cmake make g++ git

#========================
# 2. CAMBIAR PUERTO NGINX DE 80 A 81 PARA LIBERAR PUERTO 80
#========================
if [ -f /etc/nginx/sites-available/default ]; then
    sed -i 's/listen 80 default_server;/listen 81 default_server;/' /etc/nginx/sites-available/default
    sed -i 's/listen \[::\]:80 default_server;/listen [::]:81 default_server;/' /etc/nginx/sites-available/default
    echo "Puerto nginx cambiado a 81"
    systemctl restart nginx
fi

#========================
# 3. CONFIGURAR DROPBEAR EN PUERTO 444
#========================
echo "/bin/bash" > /etc/shells
echo "/usr/sbin/dropbear" >> /etc/shells
sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear || echo "DROPBEAR_PORT=444" >> /etc/default/dropbear
systemctl enable dropbear
systemctl restart dropbear

#========================
# 4. PROXY PYTHON: 80 → 22
#========================
mkdir -p /etc/mccproxy

cat > /etc/mccproxy/proxy.py << 'EOF'
#!/usr/bin/env python3
import socket
import threading
import logging
import os
import signal
import sys
from queue import Queue
from collections import defaultdict
import time

# Configuración del logger
logging.basicConfig(
    level=logging.DEBUG,  # Nivel DEBUG para mayor detalle
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(), logging.FileHandler('/var/log/mccproxy.log')]
)
logger = logging.getLogger(__name__)

# Configuración desde variables de entorno
LISTEN_HOST = os.getenv('LISTEN_HOST', '0.0.0.0')
LISTEN_PORT = int(os.getenv('LISTEN_PORT', 80))
DEST_HOST = os.getenv('DEST_HOST', '127.0.0.1')
DEST_PORT = int(os.getenv('DEST_PORT', 22))
MAX_CONNECTIONS = int(os.getenv('MAX_CONNECTIONS', 100))
SOCKET_TIMEOUT = float(os.getenv('SOCKET_TIMEOUT', 120.0))  # Mayor para túneles
MAX_CONNECTIONS_PER_IP = int(os.getenv('MAX_CONNECTIONS_PER_IP', 5))

# Respuesta WebSocket para HTTP Injector
RESPONSE = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nContent-Length: 999999999\r\n\r\n"

# Control de conexiones
connection_queue = Queue(maxsize=MAX_CONNECTIONS)
ip_connections = defaultdict(int)  # Contador de conexiones por IP
running = True

def forward(source, destination, addr, direction):
    """Transfiere datos entre source y destination, con manejo robusto de EOF."""
    try:
        source.settimeout(SOCKET_TIMEOUT)
        destination.settimeout(SOCKET_TIMEOUT)
        while running:
            try:
                data = source.recv(8192)  # Buffer más grande
                if not data:
                    logger.debug(f"EOF detectado en {direction} para {addr}")
                    break
                destination.sendall(data)
                logger.debug(f"Enviados {len(data)} bytes en {direction} para {addr}")
            except socket.timeout:
                logger.debug(f"Timeout en {direction} para {addr}, manteniendo conexión")
                continue  # No cerrar en timeout, mantener conexión
            except BrokenPipeError:
                logger.warning(f"Broken pipe en {direction} para {addr}")
                break
            except Exception as e:
                logger.error(f"Error en forward {direction} para {addr}: {e}")
                break
    finally:
        try:
            source.shutdown(socket.SHUT_RDWR)
            source.close()
            destination.shutdown(socket.SHUT_RDWR)
            destination.close()
        except:
            pass

def handle_client(client_socket, addr):
    """Maneja una conexión de cliente, optimizada para HTTP Injector."""
    ip = addr[0]
    try:
        # Verificar límite de conexiones por IP
        if ip_connections[ip] >= MAX_CONNECTIONS_PER_IP:
            logger.warning(f"Límite de conexiones alcanzado para IP {ip}")
            client_socket.close()
            return
        
        connection_queue.put(1)
        ip_connections[ip] += 1
        client_socket.settimeout(SOCKET_TIMEOUT)
        
        # Leer solicitud inicial
        req = client_socket.recv(1024)
        if not req:
            logger.warning(f"Solicitud vacía desde {addr}")
            client_socket.close()
            return
        
        # Validación de solicitud WebSocket
        if not (b"GET" in req and b"HTTP" in req and b"Upgrade: websocket" in req and b"Connection: Upgrade" in req):
            logger.warning(f"Solicitud no válida desde {addr}: {req[:100]}")
            client_socket.close()
            return
        
        # Enviar respuesta WebSocket
        client_socket.sendall(RESPONSE)
        logger.debug(f"Respuesta WebSocket enviada a {addr}")
        
        # Conectar al servidor SSH
        try:
            remote = socket.create_connection((DEST_HOST, DEST_PORT), timeout=SOCKET_TIMEOUT)
        except Exception as e:
            logger.error(f"No se pudo conectar a {DEST_HOST}:{DEST_PORT} desde {addr}: {e}")
            client_socket.close()
            return
        
        # Crear hilos para transferencia bidireccional
        threading.Thread(target=forward, args=(client_socket, remote, addr, "client->remote"), daemon=True).start()
        threading.Thread(target=forward, args=(remote, client_socket, addr, "remote->client"), daemon=True).start()
        
    except socket.timeout:
        logger.warning(f"Timeout en conexión inicial desde {addr}")
    except Exception as e:
        logger.error(f"Error manejando cliente {addr}: {e}")
    finally:
        try:
            client_socket.close()
        except:
            pass
        ip_connections[ip] -= 1
        connection_queue.get()
        connection_queue.task_done()

def signal_handler(sig, frame):
    """Maneja la señal de terminación."""
    global running
    logger.info("Cerrando el servidor...")
    running = False
    sys.exit(0)

def main():
    """Inicia el servidor proxy optimizado para HTTP Injector."""
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    server = socket.socket(socket.AF_INET6 if ':' in LISTEN_HOST else socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    try:
        server.bind((LISTEN_HOST, LISTEN_PORT))
        server.listen(MAX_CONNECTIONS)
        logger.info(f"Proxy escuchando en {LISTEN_HOST}:{LISTEN_PORT} y redirigiendo a {DEST_HOST}:{DEST_PORT}")
        
        while running:
            try:
                server.settimeout(1.0)
                client, addr = server.accept()
                logger.debug(f"Nueva conexión desde {addr}")
                threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
            except socket.timeout:
                continue
            except Exception as e:
                logger.error(f"Error aceptando conexión: {e}")
    except Exception as e:
        logger.error(f"Error iniciando el servidor: {e}")
    finally:
        server.close()
        logger.info("Servidor cerrado")

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
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mccproxy
systemctl restart mccproxy

#========================
# 5. BADVPN-UDPGW PUERTO 7300 (con systemd avanzado)
#========================

# Crear usuario y grupo badvpn si no existen
id badvpn &>/dev/null || useradd -r -s /usr/sbin/nologin badvpn

git clone https://github.com/ambrop72/badvpn.git /opt/badvpn
mkdir -p /opt/badvpn/build && cd /opt/badvpn/build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j$(nproc)
cp udpgw/badvpn-udpgw /usr/bin/badvpn-udpgw
chown badvpn:badvpn /usr/bin/badvpn-udpgw
chmod 755 /usr/bin/badvpn-udpgw

cat > /etc/systemd/system/badvpn.service <<EOF
[Unit]
Description=Badvpn UDPGW Service for VPN Tunneling on Port 7300
After=network.target

[Service]
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 \\
  --max-clients 2048 \\
  --max-connections-for-client 64
Type=simple
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
User=badvpn
Group=badvpn
LimitNOFILE=4096
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictAddressFamilies=AF_INET AF_INET6
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
Alias=badvpn.service
EOF

systemctl daemon-reload
systemctl enable badvpn
systemctl restart badvpn

#========================
# 6. STUNNEL CONFIG Y CERTIFICADO
#========================
mkdir -p /etc/stunnel/certs

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/stunnel/certs/stunnel.key \
  -out /etc/stunnel/certs/stunnel.crt \
  -subj "/"

cat /etc/stunnel/certs/stunnel.key /etc/stunnel/certs/stunnel.crt > /etc/stunnel/certs/stunnel.pem
chmod 600 /etc/stunnel/certs/stunnel.pem

cat > /etc/stunnel/stunnel.conf <<EOF
cert = /etc/stunnel/certs/stunnel.pem
pid = /var/run/stunnel4.pid
client = no
foreground = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[python-https]
accept = 443
connect = 80
EOF

sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
systemctl enable stunnel4
systemctl restart stunnel4

#========================
# 7. VERIFICACIÓN FINAL
#========================
echo -e "\n✅ Todo instalado correctamente"
ss -tulnp | grep -E ':22|:80|:81|:443|:444|:7300'
