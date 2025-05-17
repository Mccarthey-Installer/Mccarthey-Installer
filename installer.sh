#!/bin/bash

archivo="usuarios.txt"

crear_usuario() {
  clear
  echo "====== CREAR NUEVO USUARIO ======"
  read -p "Ingrese el nombre del usuario: " usuario
  read -p "Ingrese la contraseña: " clave
  read -p "Ingrese los días de duración: " dias

  # Fecha de vencimiento
  fecha_vencimiento=$(date -d "+$dias days" +"%d-%m-%Y")

  # Guardar en archivo
  echo "$usuario $clave $fecha_vencimiento $dias" >> $archivo

  echo "Usuario creado exitosamente."
  read -p "Presione ENTER para continuar..."
}

ver_registros() {
  clear
  echo "====== REGISTRO DE USUARIOS ======"
  if [[ ! -f $archivo || ! -s $archivo ]]; then
    echo "No hay registros disponibles."
  else
    printf "%-15s %-10s %-15s %-10s\n" "Usuario" "Clave" "Vencimiento" "Días"
    echo "----------------------------------------------------------"
    while read -r usuario clave vencimiento dias; do
      printf "%-15s %-10s %-15s %-10s\n" "$usuario" "$clave" "$vencimiento" "$dias"
    done < $archivo
  fi
  echo ""
  read -p "Presione ENTER para continuar..."
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
    0) exit ;;
    *) echo "Opción inválida. Presione ENTER para continuar..."; read ;;
  esac
done
