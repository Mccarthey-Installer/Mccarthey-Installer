#!/bin/bash

DB="usuarios.db"

crear_usuario() {
  clear
  echo "===== CREAR USUARIO ====="
  read -p "Digite el nombre de usuario: " usuario
  read -p "Digite la clave: " clave
  read -p "Días de duración: " dias

  fecha_vencimiento=$(date -d "+$dias days" +"%d-%m-%Y")

  echo "$usuario;$clave;$fecha_vencimiento;$dias" >> $DB
  echo "Usuario $usuario creado con éxito."
  read -p "Presione ENTER para continuar..."
}

ver_registros() {
  clear
  echo "===== REGISTROS DE USUARIOS ====="
  printf "%-15s %-10s %-15s %-10s\n" "Usuario" "Clave" "Vencimiento" "Duración"
  echo "----------------------------------------------------------"
  if [[ -f "$DB" ]]; then
    while IFS=";" read -r usuario clave vencimiento dias; do
      printf "%-15s %-10s %-15s %-10s\n" "$usuario" "$clave" "$vencimiento" "$dias"
    done < "$DB"
  else
    echo "No hay registros todavía."
  fi
  echo "----------------------------------------------------------"
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
    0) echo "Saliendo..."; exit ;;
    *) echo "Opción inválida"; sleep 1 ;;
  esac
done
