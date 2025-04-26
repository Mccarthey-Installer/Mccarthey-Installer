#!/bin/bash

API_URL="http://45.33.63.196:3000"
PORT=22

# Función para verificar la clave
check_key() {
    KEY=$1
    RESPONSE=$(curl -s "$API_URL/keys/$KEY")
    if [[ $RESPONSE == *"expiration"* ]]; then
        EXPIRATION=$(echo $RESPONSE | grep -oP '"expiration":\K[^,]+')
        CURRENT_TIME=$(date +%s)
        if (( $(echo "$EXPIRATION > $CURRENT_TIME" | bc -l) )); then
            if [[ $RESPONSE == *"used\":false"* ]]; then
                echo "Clave válida. Instalando..."
                return 0
            else
                echo "Error: Clave ya usada."
                exit 1
            fi
        else
            echo "Error: Clave expirada."
            exit 1
        fi
    else
        echo "Error: Clave no encontrada."
        exit 1
    fi
}

# Función para marcar la clave como usada
mark_key_used() {
    KEY=$1
    curl -s -X POST "$API_URL/keys/$KEY/use" >/dev/null
}

# Verificar argumentos
if [ $# -lt 2 ]; then
    echo "Uso: bash installer.sh <KEY> --mccpanel"
    exit 1
fi

KEY=$1
OPTION=$2

if [ "$OPTION" == "--mccpanel" ]; then
    check_key $KEY
    echo "Actualizando VPS..."
    apt update -y && apt upgrade -y

    echo "Instalando paquetes base..."
    apt install -y wget curl net-tools bc screen nmap unzip

    echo "Instalando OpenSSH..."
    apt install -y openssh-server
    systemctl enable ssh
    systemctl restart ssh

    echo "Instalando Dropbear..."
    apt install -y dropbear
    sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
    sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=90/' /etc/default/dropbear
    systemctl enable dropbear
    systemctl restart dropbear

    echo "Instalando SSLH (multiplexor 443)..."
    apt install -y sslh
    cat > /etc/default/sslh << EOF
RUN=yes
DAEMON=/usr/sbin/sslh
DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 --ssh 127.0.0.1:22 --openvpn 127.0.0.1:1194 --http 127.0.0.1:80 --ssl 127.0.0.1:443 --pidfile /var/run/sslh/sslh.pid"
EOF
    systemctl enable sslh
    systemctl restart sslh

    echo "Instalando BadVPN..."
    wget -O /usr/bin/badvpn-udpgw https://raw.githubusercontent.com/McClaneBVPN/McClane-Installer/main/badvpn-udpgw
    chmod +x /usr/bin/badvpn-udpgw
    screen -dmS badvpn /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7200
    screen -dmS badvpn2 /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300

    echo "Instalando Nginx..."
    apt install -y nginx
    systemctl enable nginx
    systemctl restart nginx

    # Crear comando 'menu'
    cat > /usr/bin/menu << 'EOF'
#!/bin/bash
clear
IP=$(wget -qO- ipv4.icanhazip.com)
RAM_TOTAL=$(free -m | awk '/Mem:/ { print $2 }')
RAM_USO=$(free -m | awk '/Mem:/ { print $3 }')
RAM_LIBRE=$(free -m | awk '/Mem:/ { print $4 }')
CPU_USO=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
BUFFER=$(free -m | awk '/Mem:/ {print $6}')

echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e " ∘ ONLINES: 0 ∘ EXP: 0 ∘ KILL: 0 ∘ TOTAL: 0"
echo -e " ∘ S.O: UBUNTU 22.04.5 ∘ Base:x86_64 ∘ CPU's:1"
echo -e " ∘ IP: $IP ∘ FECHA: $(date +%d/%m/%Y-%H:%M)"
echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e " Key: Verified【  📚Mccarthey🐾 © 】 (V2.8)"
echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e " ∘ SSH: 22            ∘ System-DNS: 53"
echo -e " ∘ SOCKS/PYTHON: 80   ∘ WEB-NGinx: 81"
echo -e " ∘ DROPBEAR: 90       ∘ SSL: 443"
echo -e " ∘ BadVPN: 7200       ∘ BadVPN: 7300"
echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e " ∘ TOTAL: $(bc <<< "scale=1; $RAM_TOTAL/1024")G ∘ M|LIBRE: $(bc <<< "scale=1; $RAM_LIBRE/1024")G ∘ EN USO: ${RAM_USO}M"
echo -e " ∘ U/RAM: $(bc <<< "scale=2; $RAM_USO*100/$RAM_TOTAL")% ∘ U/CPU: ${CPU_USO}% ∘ BUFFER: ${BUFFER}M"
echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e " [01] ➮ CONTROL USUARIOS (SSH/SSL/VMESS)"
echo -e " [02] ➮ [!] OPTIMIZAR VPS  [OFF]"
echo -e " [03] ➮ CONTADOR ONLINE USERS [ON]"
echo -e " [04] ➮ AUTOINICIAR SCRIPT  [ON]"
echo -e " [05] ➮ INSTALADOR DE PROTOCOLOS"
echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e " [06] ➮ [!] UPDATE / REMOVE  |  [0] ⇦ [ SALIR ]"
echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
read -p " ► Opcion : " opc
EOF
    chmod +x /usr/bin/menu

    # Crear comando 'update'
    cat > /usr/bin/update << 'EOF'
#!/bin/bash
cd $HOME
wget -q -O installer.sh https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/installer.sh
bash installer.sh update
EOF
    chmod +x /usr/bin/update

    mark_key_used $KEY
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " PANEL SSH instalado exitosamente."
    echo " Escribe \e[1;32mmenu\e[0m para abrir el panel."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "Opción inválida. Usa --mccpanel"
    exit 1
fi
