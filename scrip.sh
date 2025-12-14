#!/bin/bash
set -e

ENCRYPTED_FILE="scrip.enc"

read -s -p "Contraseña: " PASS
echo

openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 10000 \
  -in "$ENCRYPTED_FILE" \
  -pass pass:"$PASS" | bash
