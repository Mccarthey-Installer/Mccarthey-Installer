#!/bin/bash
set -e

ENCRYPTED_FILE="run.sh"

read -s -p "Contraseña: " PASS
echo

openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 \
  -in "$ENCRYPTED_FILE" \
  -pass pass:"$PASS" | bash
