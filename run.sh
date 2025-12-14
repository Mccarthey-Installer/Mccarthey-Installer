#!/usr/bin/env bash
set -e

ENCRYPTED_FILE="payload.enc"
TMP_SCRIPT="/tmp/.payload_exec.sh"
UNLOCK_FILE="/tmp/.mccarthey_unlocked"

# ===============================
# SI YA ESTÁ DESBLOQUEADO
# ===============================
if [[ -f "$UNLOCK_FILE" && -x "$TMP_SCRIPT" ]]; then
    exec bash "$TMP_SCRIPT"
fi

# ===============================
# PEDIR CONTRASEÑA SOLO 1 VEZ
# ===============================
read -s -p "?? Contraseña: " PASS
echo ""

openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
  -in "$ENCRYPTED_FILE" \
  -pass pass:"$PASS" \
  -out "$TMP_SCRIPT" || {
    echo "❌ Contraseña incorrecta"
    rm -f "$TMP_SCRIPT"
    exit 1
}

chmod +x "$TMP_SCRIPT"

# Marcar como desbloqueado
touch "$UNLOCK_FILE"
chmod 600 "$UNLOCK_FILE"

# Ejecutar menú con TTY
exec bash "$TMP_SCRIPT"
