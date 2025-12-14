#!/bin/bash

set -e
export TZ="America/El_Salvador"
echo "🛠️ Instalando dependencias..."
apt update -y && apt upgrade -y
apt install -y git cmake build-essential screen curl unzip wget python3 python3-pip \
    stunnel4 dropbear openssl locales

# Configuración de Locales a Español El Salvador
sed -i '/es_SV.UTF-8/s/^# //g' /etc/locale.gen
locale-gen
update-locale LANG=es_SV.UTF-8
timedatectl set-timezone America/El_Salvador

# ===========================
# 1. INSTALAR PROXY PYTHON EN PUERTO 80
# ===========================
echo "🌀 Configurando proxy Python en puerto 80..."

cat > /root/PDirect80.py << 'EOF'
#!/usr/bin/env python3
import socket, threading

LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 80
DEST_HOST = '127.0.0.1'
DEST_PORT = 22
RESPONSE = b"HTTP/1.1 101 Web Socket Protocol\r\nContent-length: 999999999\r\n\r\n"

def forward(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data: break
            dst.sendall(data)
    except: pass
    finally:
        src.close()
        dst.close()

def handle_client(sock, addr):
    try:
        data = sock.recv(1024)
        if b"HTTP" in data: sock.sendall(RESPONSE)
        remote = socket.create_connection((DEST_HOST, DEST_PORT))
        threading.Thread(target=forward, args=(sock, remote)).start()
        threading.Thread(target=forward, args=(remote, sock)).start()
    except: sock.close()

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(100)
    print("🔁 Proxy activo en puerto 80 redirigiendo a 22")
    while True:
        client, addr = server.accept()
        threading.Thread(target=handle_client, args=(client, addr)).start()

if __name__ == "__main__":
    main()
EOF

chmod +x /root/PDirect80.py
screen -dmS ws80 python3 /root/PDirect80.py

# ===========================
# 2. STUNNEL4 PUERTO 443 → 80 CON CERTIFICADO PERSONALIZADO
# ===========================
echo "🔐 Generando certificado SSL autofirmado para Stunnel con tu firma personalizada..."
mkdir -p /etc/stunnel/certs

openssl req -x509 -nodes -days 1095 -newkey rsa:2048 \
  -keyout /etc/stunnel/certs/stunnel.key \
  -out /etc/stunnel/certs/stunnel.crt \
  -subj "/C=SV/ST=San Salvador/L=Santa Ana/O=McCartheyVPN/OU=McCPanel/CN=SSLService/emailAddress=admin@mccarthey.net"

cat /etc/stunnel/certs/stunnel.key /etc/stunnel/certs/stunnel.crt > /etc/stunnel/certs/stunnel.pem
chmod 600 /etc/stunnel/certs/stunnel.pem

echo "🧩 Configurando Stunnel..."
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

systemctl restart stunnel4
systemctl enable stunnel4

# ===========================
# 3. BADVPN PUERTOS 7200 Y 7300 VIA SCREEN
# ===========================
echo "📡 Compilando y configurando BadVPN..."

rm -rf /opt/badvpn
git clone https://github.com/ambrop72/badvpn.git /opt/badvpn
mkdir -p /opt/badvpn/build && cd /opt/badvpn/build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j$(nproc)
cp udpgw/badvpn-udpgw /usr/bin/
chmod +x /usr/bin/badvpn-udpgw

# Matar screen viejos si existen
screen -S badvpn -X quit || true
screen -S badUDP72 -X quit || true

# Levantar BadVPN
screen -dmS badvpn /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 \
    --max-clients 1000 --max-connections-for-client 10
screen -dmS badUDP72 /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7200 \
    --max-clients 1000 --max-connections-for-client 10

# ===========================
# 4. AUTOINICIO CON /etc/rc.local
# ===========================
echo "🧩 Configurando autoarranque vía rc.local..."

cat > /etc/rc.local <<'EOF'
#!/bin/bash
sleep 10
screen -dmS ws80 python3 /root/PDirect80.py
screen -dmS badvpn /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
screen -dmS badUDP72 /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 1000 --max-connections-for-client 10
exit 0
EOF

chmod +x /etc/rc.local

cat > /etc/systemd/system/rc-local.service <<EOF
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

systemctl daemon-reload
systemctl enable rc-local
systemctl start rc-local

# ===========================
# 5. MENSAJE FINAL CLARO Y BONITO
# ===========================
echo ""
echo "======================================"
echo "✅ INSTALACIÓN COMPLETA DE MCCARTHY VPN"
echo "📦 Puertos activos:"
ss -tulnp | grep -E ':80|:443|:444|:7200|:7300' || true
echo ""
echo "🛡️  SSL + Python Directo (80->22): ACTIVO"
echo "🎯 Puedes probarlo desde HTTP Injector o curl: 443 -> SSH"
echo "🧠 Listo para usar con WebSocket SSL"
echo "======================================"
echo ""

exit 0
