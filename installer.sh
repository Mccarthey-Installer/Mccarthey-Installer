#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # Sin color

# Verificar si se pasó una key
if [[ -z "$1" ]]; then
    echo -e "${RED}Uso correcto:${NC} ./installer.sh MCC-KEY{xxxx-xxxx-xxxx-xxxx} [--mccpanel]"
    exit 1
fi

KEY="$1"
ARG="$2"
API="http://127.0.0.1:7555/validate"

# Actualizar sistema y dependencias
apt update -y && apt upgrade -y
apt install -y jq wget curl

# Codificar la key para la URL
KEY_URLENCODED=$(echo "$KEY" | jq -s -R -r @uri)

# Validar la key con el API
VALIDATION_URL="${API}/${KEY_URLENCODED}"
RESPUESTA=$(curl -s "$VALIDATION_URL")

# Verificar si es válida
VALIDA=$(echo "$RESPUESTA" | grep -o '"valida":true')

if [[ -z "$VALIDA" ]]; then
    echo -e "${RED}KEY inválida:${NC}"
    echo "$RESPUESTA"
    exit 1
fi

echo -e "${GREEN}KEY válida. Continuando con la instalación...${NC}"

# Crear directorios necesarios
mkdir -p /etc/mccproxy

# Descargar el script menu.sh desde tu repo
wget -q -O /usr/bin/menu.sh "https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/menu.sh"
chmod +x /usr/bin/menu.sh

# Copiar archivos adicionales si los hubiera
# cp proxy.py /etc/mccproxy/

# Ejecutar el panel si se pasó el flag --mccpanel
if [[ "$ARG" == "--mccpanel" ]]; then
    clear
    bash /usr/bin/menu.sh
fi
