#!/bin/bash

API_URL="http://102.129.137.174:3000"

# Instalar jq si no está
if ! command -v jq &> /dev/null; then
    echo "Instalando jq..."
    apt update -y
    apt install -y jq
fi

check_key() {
    KEY=$1
    RESPONSE=$(curl -s "$API_URL/keys/$KEY")
    if echo "$RESPONSE" | jq -e '.error' >/dev/null; then
        echo "Error: $(echo "$RESPONSE" | jq -r '.error')"
        exit 1
    fi
    EXPIRATION=$(echo "$RESPONSE" | jq -r '.expiration')
    USED=$(echo "$RESPONSE" | jq -r '.used')
    CURRENT_TIME=$(date +%s)
    if (( $(echo "$EXPIRATION > $CURRENT_TIME" | bc -l) )); then
        if [ "$USED" = "false" ]; then
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
    echo "Instalando Mccarthey SSH Manager..."
    apt update -y
    apt install -y openssh-server
    # Instalar ssh_manager.sh como /mcc
    wget -q -O /usr/local/bin/mcc https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/ssh_manager.sh
    chmod +x /usr/local/bin/mcc
    mark_key_used $KEY
    echo "Mccarthey SSH Manager instalado. Accede con: /mcc <clave>"
    echo "También puedes usar SSH en el puerto 22 con: ssh root@$(hostname -I | awk '{print $1}')"
else
    echo "Opción inválida. Usa --mccpanel."
    exit 1
fi
