#!/bin/bash

KEY="$1"
MODE="$2"

# Colores para mensajes
RED="\033[1;31m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
NC="\033[0m"

# Validar KEY
if [ -z "$KEY" ]; then
    echo -e "\n${RED}[ERROR]${NC} No se proporcionó una KEY válida."
    echo -e "Uso: bash installer.sh <KEY> [--mccpanel]"
    exit 1
fi

echo -e "\n${BLUE}[INFO]${NC} Validando KEY con el servidor..."
RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/real_installer.sh "http://45.33.63.196:5000/validate?key=$KEY")

if [ "$RESPONSE" != "200" ]; then
    echo -e "\n${RED}[ERROR]${NC} KEY inválida, expirada o ya utilizada."
    exit 1
fi

chmod +x /tmp/real_installer.sh

if [ "$MODE" == "--mccpanel" ]; then
    echo -e "\n${GREEN}[OK]${NC} Ejecutando en modo panel SSH (sin limpiar VPS)..."
    bash /tmp/real_installer.sh --mccpanel
else
    echo -e "\n${GREEN}[OK]${NC} Ejecutando instalación completa..."
    bash /tmp/real_installer.sh
fi
