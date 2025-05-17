#!/bin/bash

REGISTROS="registros.txt"

function crear_usuario() {
  clear
  echo "===== CREAR USUARIO ====="
  read -p "Nombre del usuario: " nombre
  read -p "Contraseña: " clave
  read -p "Días de duración: " dias

  # Calcular fecha de expiración exacta
  fecha_exp=$(date -d "+$dias days" +"%Y-%m-%d")

  # Crear usuario con fecha de expiración
  useradd -e "$fecha_exp" -M -s /bin/false "$nombre"
  echo "$nombre:$clave" | chpasswd

  # Guardar en registros
  echo -e "$nombre\t$clave\t$fecha_exp\t${dias} días" >> $REGISTROS

  echo
  echo "Usuario creado exitosamente"
  echo "Nombre: $nombre"
  echo "Clave: $clave"
  echo "Expira: $fecha_exp"
  echo "============================"
  read -p "Presione Enter para continuar..."
}

function ver_registros() {
  clear
  echo "===== REGISTROS ====="
  if [[ -f $REGISTROS ]]; then
    echo -e "Usuario\tClave\tExpira\t\tDuración"
    echo "--------------------------------------------"
    cat $REGISTROS
  else
    echo "No hay registros aún."
  fi
  echo "======================="
  read -p "Presione Enter para continuar..."
}

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
    0) break ;;
    *) echo "Opción inválida"; sleep 1 ;;
  esac
done
