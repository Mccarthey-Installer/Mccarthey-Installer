#!/bin/bash

# Leer KEY desde argumentos
KEY="$1"

# Validar que se envió una key
if [ -z "$KEY" ]; then
    echo "ERROR: No se proporcionó una key."
    exit 1
fi

# Validar la key con tu API
RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/installer.sh "http://45.33.63.196:5000/validate?key=$KEY")

# Revisar si fue exitosa
if [ "$RESPONSE" != "200" ]; then
    echo "ERROR: Key inválida, expirada o ya utilizada."
    exit 1
fi

# Ejecutar el script descargado desde el API
chmod +x /tmp/installer.sh
bash /tmp/installer.sh
