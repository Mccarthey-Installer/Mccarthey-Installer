#!/bin/bash

# Uso: ./crear_usuario_temporal.sh nombre_usuario contraseña dias_validez

USUARIO=$1
CLAVE=$2
DIAS=$3

# Verifica si se proporcionaron los 3 argumentos
if [ $# -ne 3 ]; then
  echo "Uso: $0 nombre_usuario contraseña dias_validez"
  exit 1
fi

# Verifica si el usuario ya existe
if id "$USUARIO" &>/dev/null; then
  echo "El usuario '$USUARIO' ya existe. No se puede crear."
  exit 1
fi

# Crear el usuario con shell bash y directorio home
useradd -m -s /bin/bash $USUARIO

# Asignar contraseña
echo "$USUARIO:$CLAVE" | chpasswd

# Calcular la fecha exacta de expiración
EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)

# Establecer la expiración
chage -E $EXPIRA $USUARIO

# Formatear fecha bonita
FECHA_FORMATO=$(date -d "$EXPIRA" +"%d de %B de %Y")

# Confirmación clara
echo ""
echo "===== USUARIO CREADO EXITOSAMENTE ====="
echo "Usuario: $USUARIO"
echo "Contraseña: $CLAVE"
echo "Duración: $DIAS días"
echo "Último día válido: $FECHA_FORMATO (vence a las 23:59)"
echo "======================================="
