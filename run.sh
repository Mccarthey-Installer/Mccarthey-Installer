#!/usr/bin/env bash
set -e

ENCRYPTED_FILE="payload.enc"
TMP_SCRIPT="/tmp/.payload_exec.sh"

read -s -p "🔐 Contraseña: " PASS
echo ""

openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
  -in "$ENCRYPTED_FILE" \
  -pass pass:"$PASS" \
  -out "$TMP_SCRIPT" || {
    echo "❌ Contraseña incorrecta"
    exit 1
}

chmod +x "$TMP_SCRIPT"

# 🔥 EJECUCIÓN REAL CON TTY
exec bash "$TMP_SCRIPT"
