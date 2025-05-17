#!/bin/bash

REGISTROS="registros.txt"

function crear_usuario() {
  clear
  echo "===== CREAR USUARIO SSH ====="
  read -p "Nombre del usuario: " USUARIO
  read -p "Contraseña: " CLAVE
  read -p "Días de validez: " DIAS

  # Verificar si ya existe
  if id "$USUARIO" &>/dev/null; then
    echo "El usuario '$USUARIO' ya existe. No se puede crear."
    read -p "Presiona Enter para continuar..."
    return
  fi

  # Crear usuario real
  useradd -m -s /bin/bash "$USUARIO"
  echo "$USUARIO:$CLAVE" | chpasswd
  EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)
  chage -E "$EXPIRA" "$USUARIO"

  # Guardar registro
  echo -e "$USUARIO\t$CLAVE\t$EXPIRA\t${DIAS} días" >> "$REGISTROS"

  echo
  echo "Usuario creado exitosamente:"
  echo "Usuario: $USUARIO"
  echo "Clave: $CLAVE"
  echo "Expira: $EXPIRA"
  read -p "Presiona Enter para continuar..."
}

function ver_registros() {
  clear
  echo "===== REGISTROS ====="
  if [[ -f $REGISTROS ]]; then
    echo -e "Usuario\tClave\tExpira\t\tDuración"
    echo "---------------------------------------------"
    cat "$REGISTROS"
  else
    echo "No hay registros aún."
  fi
  echo "======================"
  read -p "Presiona Enter para continuar..."
}

while true; do
  clear
  echo "====== PANEL DE USUARIOS VPN/SSH ======"
  echo "1. Crear usuario"
  echo "2. Ver registros"
  echo "0. Salir"
  echo "======================================="
  read -p "Seleccione una opción: " opcion

  case $opcion in
    1) crear_usuario ;;
    2) ver_registros ;;
    0) break ;;
    *) echo "Opción inválida"; sleep 1 ;;
  esac
done
