#!/usr/bin/env bash
set -euo pipefail

ENCRYPTED_FILE="payload.enc"

decrypt_and_exec() {
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
        -in "$ENCRYPTED_FILE" \
        -pass pass:"$1" 2>/dev/null | bash
}

read -s -p "🔐 Contraseña: " PASS
echo ""

# Ejecutar directamente por pipe
if ! decrypt_and_exec "$PASS"; then
    echo "❌ Contraseña incorrecta o acceso revocado"
    exit 1
fi
