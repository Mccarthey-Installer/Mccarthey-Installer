#!/usr/bin/env bash
set -e

# =========================
# CONFIG
# =========================
ENCRYPTED_FILE="payload.enc"
CIPHER_METHOD="aes-256-cbc"
PBKDF2_ITERATIONS=10000
MAX_ATTEMPTS=3

# ===== IP WHITELIST =====
USE_IP_CHECK=true
GITHUB_USER="Mccarthey-Installer"
GITHUB_REPO="Mccarthey-Installer"
GITHUB_BRANCH="main"

# =========================
# FUNCIONES
# =========================
error() { echo "❌  $1"; exit 1; }
success() { echo "✅  $1"; }

get_ip() {
    curl -s icanhazip.com || wget -qO- icanhazip.com
}

# =========================
# VALIDACIONES
# =========================
[ -f "$ENCRYPTED_FILE" ] || error "No se encontró $ENCRYPTED_FILE"

# =========================
# VALIDAR IP
# =========================
if $USE_IP_CHECK; then
    IP="$(get_ip | tr -d '\n\r')"
    WHITELIST_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/ip_whitelist.txt"
    WHITELIST="$(curl -fs "$WHITELIST_URL" || true)"

    echo "$WHITELIST" | sed 's/\r//g' | grep -qx "$IP" || error "IP no autorizada"
    success "IP autorizada"
fi

# =========================
# PEDIR CONTRASEÑA
# =========================
ATTEMPT=1
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    read -s -p "🔐 Contraseña: " PASS
    echo ""

    if openssl enc -d -"$CIPHER_METHOD" -pbkdf2 -iter $PBKDF2_ITERATIONS \
        -in "$ENCRYPTED_FILE" \
        -pass pass:"$PASS" 2>/dev/null | bash; then
        exit 0
    fi

    echo "❌  Contraseña incorrecta"
    ATTEMPT=$((ATTEMPT+1))
done

error "Máximo de intentos alcanzado"
