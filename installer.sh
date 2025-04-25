#!/bin/bash
KEY=$1
DB_PATH="/root/telegram_bot/keys.db"

# Verifica si sqlite3 está instalado
if ! command -v sqlite3 &> /dev/null; then
    apt update -y && apt install -y sqlite3
fi

# Consulta la base de datos
VALID=$(sqlite3 "$DB_PATH" "SELECT used, created_at FROM keys WHERE key='$KEY'")
if [ -z "$VALID" ]; then
    echo "Key no encontrada"
    exit 1
fi

USED=$(echo $VALID | cut -d'|' -f1)
CREATED_AT=$(echo $VALID | cut -d'|' -f2)
CURRENT_TIME=$(date +%s)

if [ "$USED" -eq 1 ]; then
    echo "Key ya usada"
    exit 1
fi

if [ $(( CURRENT_TIME - CREATED_AT )) -gt 10800 ]; then
    echo "Key expirada"
    sqlite3 "$DB_PATH" "DELETE FROM keys WHERE key='$KEY'"
    exit 1
fi

# Marca la key como usada
sqlite3 "$DB_PATH" "UPDATE keys SET used=1 WHERE key='$KEY'"
echo "Key válida, procediendo con la instalación..."

# Agrega aquí el resto de tu script de instalación
