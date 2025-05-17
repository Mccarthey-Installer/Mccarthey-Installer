#!/bin/bash

REGISTRO="usuarios.txt"
IP_VPS="102.129.137.94"

crear_usuario() {
  read -p "Ingrese el nombre de usuario: " usuario
  read -p "Ingrese la contraseña: " contrasena
  echo ""
  echo "Presione ENTER para confirmar..."
  read

  # Crear usuario con expiración de 7 días
  useradd -e $(date -d "+7 days" +"%Y-%m-%d") -M -s /bin/false "$usuario"
  echo "$usuario:$contrasena" | chpasswd

  fecha_exp=$(chage -l "$usuario" | grep "Account expires" | cut -d: -f2 | sed 's/^[ \t]*//')
  
  echo "$usuario | $contrasena | $fecha_exp" >> "$REGISTRO"
  echo "Usuario creado correctamente en $IP_VPS"
}

ver_registros() {
  if [[ -f "$REGISTRO" ]]; then
    echo "===== REGISTROS ====="
    cat "$REGISTRO"
    echo "======================"
  else
    echo "No hay registros aún."
  fi
}

menu() {
  while true; do
    clear
    echo "====== PANEL DE USUARIOS ======"
    echo "1. Crear usuario"
    echo "2. Ver registros"
    echo "0. Salir"
    echo "================================"
    read -p "Seleccione una opción: " opcion

    case $opcion in
      1) crear_usuario ;;
      2) ver_registros ;;
      0) exit ;;
      *) echo "Opción inválida." ; sleep 1 ;;
    esac
  done
}

menu
