#!/bin/bash

# Verificar que se haya proporcionado una KEY
KEY="$1"
if [ -z "$KEY" ]; then
    echo -e "\n\033[1;31m[ERROR]\033[0m No se proporcionó una KEY válida."
    echo "Uso correcto: bash installer.sh <KEY> [opciones]"
    exit 1
fi

# Validar la KEY contra tu API y seguir redirecciones
echo -e "\n\033[1;34m[INFO]\033[0m Validando KEY con el servidor..."
RESPONSE=$(curl -s -w "%{http_code}" -L -o /tmp/real_installer.sh "http://45.33.63.196:5000/validate?key=$KEY")

# Revisar si fue exitosa
if [ "$RESPONSE" != "200" ]; then
    echo -e "\n\033[1;31m[ERROR]\033[0m KEY inválida, expirada o ya utilizada."
    exit 1
fi

# Permitir ejecución del script descargado
chmod +x /tmp/real_installer.sh

# Ejecutar el script descargado con todos los parámetros que se pasaron
echo -e "\n\033[1;32m[OK]\033[0m Ejecutando instalador principal..."
bash /tmp/real_installer.sh "$@"
