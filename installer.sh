#!/bin/bash

# ==========================
# McCarthey Installer Script
# ==========================

KEY="$1"
ARG="$2"
API="http://127.0.0.1:7555/validate"

# Verificar si se pasó una key
if [[ -z "$KEY" ]]; then
  echo "Uso: ./installer.sh MCC-KEY{xxxx-xxxx-xxxx-xxxx} --mccpanel"
  exit 1
fi

# Codificar la key para URL
KEY_URLENCODED=$(echo "$KEY" | jq -s -R -r @uri)

# Verificar si jq está instalado
if ! command -v jq &> /dev/null; then
  echo "Instalando dependencia: jq"
  apt update -y && apt install jq -y
fi

# Validar la key vía API
VALIDATION_URL="${API}/${KEY_URLENCODED}"
RESPUESTA=$(curl -s "$VALIDATION_URL")
VALIDEZ=$(echo "$RESPUESTA" | jq -r '.valida')
MOTIVO=$(echo "$RESPUESTA" | jq -r '.motivo')

if [[ "$VALIDEZ" != "true" ]]; then
  echo "KEY inválida: $MOTIVO"
  exit 1
else
  echo "KEY válida: $MOTIVO"
fi

# Continuar con instalación
echo "Instalando paquetes necesarios..."
apt update -y && apt upgrade -y
apt install -y net-tools curl wget jq

# Crear estructura de carpetas
mkdir -p /etc/mccproxy/
cd /etc/mccproxy/

# Descargar el menú
wget -q https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/menu.sh -O /usr/bin/menu
chmod +x /usr/bin/menu

# Descargar el proxy
wget -q https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/etc/mccproxy/proxy.py -O /etc/mccproxy/proxy.py
chmod +x /etc/mccproxy/proxy.py

# Mostrar mensaje final
echo -e "\nInstalación completa."
echo "Usa el comando: menu"

# Lanzar menú si se pasó --mccpanel
if [[ "$ARG" == "--mccpanel" ]]; then
  /usr/bin/menu
fi
