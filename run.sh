#!/bin/bash
set -e

ENCRYPTED_FILE="payload.enc"

read -s -p "Contraseña: " PASS
echo

# Pasar la contraseña por STDIN (forma segura)
printf "%s" "$PASS" | openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
  -in "$ENCRYPTED_FILE" \
  -pass stdin | bash
