#!/usr/bin/env bash
set -e

ENCRYPTED_FILE="payload.enc"
UNLOCK_FILE="/tmp/.mccarthey_unlocked"

# Si ya está desbloqueado, no pedir contraseña otra vez
if [[ -f "$UNLOCK_FILE" ]]; then
    exec bash -c "$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
        -in "$ENCRYPTED_FILE" \
        -pass pass:"$(cat "$UNLOCK_FILE")")"
fi

read -s -p "🔐 Contraseña: " PASS
echo ""

# Probar descifrado SIN guardar
SCRIPT="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
    -in "$ENCRYPTED_FILE" \
    -pass pass:"$PASS" 2>/dev/null)" || {
        echo "❌ Contraseña incorrecta"
        exit 1
}

# Guardar solo la contraseña (no el código)
echo "$PASS" > "$UNLOCK_FILE"
chmod 600 "$UNLOCK_FILE"

exec bash -c "$SCRIPT"
