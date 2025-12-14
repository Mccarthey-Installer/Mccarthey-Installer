#!/usr/bin/env bash
set -e

ENCRYPTED_FILE="payload.enc"
UNLOCK_FILE="/tmp/.mccarthey_unlocked"

decrypt_and_exec() {
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
        -in "$ENCRYPTED_FILE" \
        -pass pass:"$1" 2>/dev/null | bash
}

# ===============================
# YA DESBLOQUEADO (NO PEDIR PASS)
# ===============================
if [[ -f "$UNLOCK_FILE" ]]; then
    PASS="$(cat "$UNLOCK_FILE")"
    decrypt_and_exec "$PASS" || {
        rm -f "$UNLOCK_FILE"
        echo "🚫 Acceso revocado"
        exit 1
    }
    exit 0
fi

# ===============================
# PEDIR CONTRASEÑA
# ===============================
read -s -p "🔐 Contraseña: " PASS
echo ""

# Probar descifrado
if decrypt_and_exec "$PASS"; then
    echo "$PASS" > "$UNLOCK_FILE"
    chmod 600 "$UNLOCK_FILE"
    exit 0
else
    echo "❌ Contraseña incorrecta"
    exit 1
fi
