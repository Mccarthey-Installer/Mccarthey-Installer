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
# 5. AJUSTAR BUFFER UDP DEL SISTEMA OPERATIVO PARA TRÁFICO INTENSO
#========================
sysctl -w net.core.rmem_max=26214400
echo "net.core.rmem_max=26214400" >> /etc/sysctl.conf

#========================
# 6. BADVPN-UDPGW PUERTO 7300 (con systemd avanzado y buffer ampliado)
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
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 \
  --max-clients 2048 \
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
# 7. STUNNEL CONFIG Y CERTIFICADO
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
# 8. VERIFICACIÓN FINAL
#========================
echo -e "\n✅ Todo instalado correctamente"
ss -tulnp | grep -E ':22|:80|:81|:443|:444|:7300'
