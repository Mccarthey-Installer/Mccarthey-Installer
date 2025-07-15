#!/bin/bash

set -e

echo "🚀 Iniciando instalación y configuración..."

#========================
# 1. ACTUALIZAR SISTEMA Y PAQUETES
#========================
echo "📦 Actualizando paquetes e instalando dependencias..."
apt update && apt upgrade -y
apt install -y locales curl unzip wget screen nginx nload htop python3 python3-pip \
nodejs npm lsof psmisc socat bc net-tools cowsay nmap jq iptables openssh-server \
dropbear stunnel4 cmake make g++ git build-essential

# Configurar locales para El Salvador
sed -i '/es_SV.UTF-8/s/^# //g' /etc/locale.gen
locale-gen
update-locale LANG=es_SV.UTF-8

# Establecer zona horaria
timedatectl set-timezone America/El_Salvador

#========================
# 2. CAMBIAR PUERTO NGINX DE 80 A 81
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
# 4. PROXY PYTHON: 80 → 22 (EN SCREEN)
#========================
mkdir -p /etc/mccproxy

cat > /etc/mccproxy/proxy.py << 'EOF'
#!/usr/bin/env python3
import socket, threading

LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 80
DEST_HOST = '127.0.0.1'
DEST_PORT = 22

RESPONSE = b"HTTP/1.1 101 Web Socket Protocol\r\nContent-length: 999999999\r\n\r\n"

def forward(source, destination):
    try:
        while True:
            data = source.recv(4096)
            if not data: break
            destination.sendall(data)
    except: pass
    finally:
        source.close()
        destination.close()

def handle_client(client_socket, addr):
    try:
        req = client_socket.recv(1024)
        if b"HTTP" in req: client_socket.sendall(RESPONSE)
        remote = socket.create_connection((DEST_HOST, DEST_PORT))
        threading.Thread(target=forward, args=(client_socket, remote)).start()
        threading.Thread(target=forward, args=(remote, client_socket)).start()
    except: client_socket.close()

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(100)
    print(f"Proxy escuchando en {LISTEN_HOST}:{LISTEN_PORT} y redirigiendo a {DEST_HOST}:{DEST_PORT}")
    while True:
        client, addr = server.accept()
        threading.Thread(target=handle_client, args=(client, addr)).start()

if __name__ == "__main__":
    main()
EOF

chmod +x /etc/mccproxy/proxy.py
screen -dmS mccproxy /usr/bin/python3 /etc/mccproxy/proxy.py

#========================
# 5. BADVPN-UDPGW PUERTOS 7300 Y 7200 EN SCREEN + AUTOINICIO
#========================
echo "📥 Clonando repositorio Badvpn..."
rm -rf /opt/badvpn
git clone https://github.com/ambrop72/badvpn.git /opt/badvpn

echo "🛠️ Compilando Badvpn UDPGW..."
mkdir -p /opt/badvpn/build && cd /opt/badvpn/build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j$(nproc)

echo "📂 Copiando ejecutable a /usr/bin..."
cp udpgw/badvpn-udpgw /usr/bin/badvpn-udpgw
chmod +x /usr/bin/badvpn-udpgw

screen -dmS badvpn /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
screen -dmS badUDP72 /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 1000 --max-connections-for-client 10

# Autoinicio con rc.local
cat > /etc/rc.local <<'EOF'
#!/bin/bash
sleep 10
screen -dmS badvpn /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
screen -dmS badUDP72 /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 1000 --max-connections-for-client 10
screen -dmS mccproxy /usr/bin/python3 /etc/mccproxy/proxy.py
exit 0
EOF

chmod +x /etc/rc.local

# Crear servicio systemd para rc.local si no existe
if ! systemctl status rc-local &> /dev/null; then
  cat > /etc/systemd/system/rc-local.service <<'EOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable rc-local
  systemctl start rc-local
fi

#========================
# 6. STUNNEL CONFIG Y CERTIFICADO (443 EN SYSTEMD)
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
ss -tulnp | grep -E ':22|:80|:81|:443|:444|:7200|:7300'
echo "Puedes verificar screens con: screen -ls"
