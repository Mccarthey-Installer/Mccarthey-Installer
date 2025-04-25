#!/bin/bash

KEY="$1"
ARG2="$2"

# Verifica si se proporcionó una key
if [[ -z "$KEY" ]]; then
  echo "Uso: ./installer.sh MCC-KEY{xxxx-xxxx-xxxx-xxxx} --mccpanel"
  exit 1
fi

# Instalar dependencias necesarias
apt update -y && apt upgrade -y
apt install -y jq wget curl

# Validar la MCC-KEY
encoded_key=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$KEY'))")
response=$(curl -s "http://127.0.0.1:7555/validate/$encoded_key")

valida=$(echo "$response" | jq -r '.valida')
motivo=$(echo "$response" | jq -r '.motivo')

if [[ "$valida" != "true" ]]; then
  echo "KEY inválida: $motivo"
  exit 1
fi

echo "KEY válida: $KEY"

# Descargar y ejecutar el menú si se pidió --mccpanel
if [[ "$ARG2" == "--mccpanel" ]]; then
  wget -q -O /usr/bin/menu.sh https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/menu.sh
  chmod +x /usr/bin/menu.sh
  /usr/bin/menu.sh
fi
