#!/bin/bash
KEY=$1
API_URL="http://172.233.189.223:9090/validate?key=$KEY"

# Validar la key vía API remota
RESPONSE=$(curl -s "$API_URL")

if [[ "$RESPONSE" == "VALID" ]]; then
    echo "Key válida, procediendo con la instalación..."
elif [[ "$RESPONSE" == "USED" ]]; then
    echo "Key ya usada"
    exit 1
elif [[ "$RESPONSE" == "EXPIRED" ]]; then
    echo "Key expirada"
    exit 1
else
    echo "Key no encontrada"
    exit 1
fi

# Aquí comienza el resto de tu instalación personalizada...
# Por ejemplo:
# apt install -y dropbear screen python3 ...
