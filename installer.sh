#!/bin/bash

API_URL="http://102.129.137.174:3000"
PORT=2222

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

mark_key_used() {
    KEY=$1
    curl -s -X POST "$API_URL/keys/$KEY/use"
}

if [ $# -lt 1 ]; then
    echo "Uso: ./installer.sh <clave> --mccpanel"
    exit 1
fi

KEY=$1
OPTION=$2

if [ "$OPTION" == "--mccpanel" ]; then
    check_key $KEY
    while netstat -tuln | grep -q ":$PORT"; do
        PORT=$((PORT + 1))
    done
    echo "Instalando panel SSH en el puerto $PORT..."
    apt update -y
    apt install -y openssh-server
    sed -i "s/#Port 22/Port $PORT/" /etc/ssh/sshd_config
    systemctl restart sshd
    apt install -y cockpit
    systemctl enable --now cockpit.socket
    mark_key_used $KEY
    echo "Panel SSH instalado. Accede en: http://$(hostname -I | awk '{print $1}'):9090"
    echo "También puedes usar SSH en el puerto $PORT con: ssh root@$(hostname -I | awk '{print $1}')"
else
    echo "Opción inválida. Usa --mccpanel."
    exit 1
fi
