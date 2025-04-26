#!/bin/bash

API_URL="http://45.33.63.196:3000"
PORT=2222  # Puerto inicial para SSH

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
                echo "Error: Clave ya usada. Genera una nueva con el bot."
                exit 1
            fi
        else
            echo "Error: Clave expirada. Genera una nueva con el bot."
            exit 1
        fi
    else
        echo "Error: Clave no encontrada. Genera una nueva con el bot."
        exit 1
    fi
}

# Función para marcar la clave como usada
mark_key_used() {
    KEY=$1
    curl -s -X POST "$API_URL/keys/$KEY/use"
}

# Verificar argumentos
if [ $# -lt 1 ]; then
    echo "Uso: ./installer.sh <clave> --mccpanel"
    exit 1
fi

KEY=$1
OPTION=$2

if [ "$OPTION" == "--mccpanel" ]; then
    check_key $KEY

    # Seleccionar puerto único
    while netstat -tuln | grep -q ":$PORT"; do
        PORT=$((PORT + 1))
    done

    echo "Instalando servidor SSH en el puerto $PORT..."
    apt update -y
    apt install -y openssh-server

    sed -i "s/#Port 22/Port $PORT/" /etc/ssh/sshd_config
    systemctl restart sshd

    echo "Instalando panel web (Cockpit)..."
    apt install -y cockpit
    systemctl enable --now cockpit.socket

    # Crear script de usuarios SSH
    cat << 'EOF' > /root/crear-usuario-ssh.sh
#!/bin/bash

clear
echo "======== CREAR USUARIO SSH PARA VPN/PAYLOAD ========"

read -p "Nombre del usuario: " username
read -p "Duración en días (ej: 30): " dias
read -p "¿Deseas una contraseña personalizada? (s/n): " custom_pass

if [ "$custom_pass" == "s" ]; then
    read -p "Introduce la contraseña: " password
else
    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
fi

exp_date=$(date -d "+$dias days" +"%Y-%m-%d")
useradd -e $exp_date -s /bin/false -M $username
echo "$username:$password" | chpasswd

ip=$(hostname -I | awk '{print $1}')

echo ""
echo "========= DATOS DEL USUARIO ========="
echo "Host/IP: $ip"
echo "Puerto SSH: $PORT"
echo "Usuario: $username"
echo "Contraseña: $password"
echo "Expira el: $exp_date"
echo "======================================"
EOF

    chmod +x /root/crear-usuario-ssh.sh

    mark_key_used $KEY

    IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "====== INSTALACIÓN COMPLETA ======"
    echo "Accede al Panel Web: http://$IP:9090"
    echo "SSH disponible en puerto: $PORT"
    echo ""
    echo "Script para crear usuarios SSH: /root/crear-usuario-ssh.sh"
    echo "================================="
else
    echo "Opción inválida. Usa --mccpanel."
    exit 1
fi
