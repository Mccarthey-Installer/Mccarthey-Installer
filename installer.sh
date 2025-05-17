#!/bin/bash

REGISTROS="registros.txt"

# Colores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

function crear_usuario() {
  clear
  echo -e "${CYAN}===== CREAR USUARIO SSH =====${NC}"
  read -p "$(echo -e ${YELLOW}"Nombre del usuario: "${NC})" USUARIO
  read -p "$(echo -e ${YELLOW}"Contraseña: "${NC})" CLAVE
  read -p "$(echo -e ${YELLOW}"Días de validez: "${NC})" DIAS

  # Verificar si ya existe
  if id "$USUARIO" &>/dev/null; then
    echo -e "${RED}El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
    read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
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
  echo -e "${GREEN}Usuario creado exitosamente:${NC}"
  echo -e "${BLUE}Usuario: ${YELLOW}$USUARIO${NC}"
  echo -e "${BLUE}Clave: ${YELLOW}$CLAVE${NC}"
  echo -e "${BLUE}Expira: ${YELLOW}$EXPIRA${NC}"
  read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
}

function ver_registros() {
  clear
  echo -e "${CYAN}===== REGISTROS =====${NC}"
  if [[ -f $REGISTROS ]]; then
    echo -e "${YELLOW}Nº\tUsuario\tClave\tExpira\t\tDuración${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"
    awk '{print NR"\t"$0}' "$REGISTROS" | while IFS=$'\t' read -r NUM USUARIO CLAVE EXPIRA DURACION; do
      echo -e "${GREEN}$NUM\t${YELLOW}$USUARIO\t$CLAVE\t$EXPIRA\t$DURACION${NC}"
    done
  else
    echo -e "${RED}No hay registros aún.${NC}"
  fi
  echo -e "${CYAN}=====================${NC}"
  read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
}

function eliminar_usuario() {
  clear
  echo -e "${CYAN}===== ELIMINAR USUARIO =====${NC}"
  if [[ ! -f $REGISTROS ]]; then
    echo -e "${RED}No hay registros para eliminar.${NC}"
    read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
    return
  fi

  echo -e "${YELLOW}Nº\tUsuario\tClave\tExpira\t\tDuración${NC}"
  echo -e "${BLUE}---------------------------------------------${NC}"
  awk '{print NR"\t"$0}' "$REGISTROS" | while IFS=$'\t' read -r NUM USUARIO CLAVE EXPIRA DURACION; do
    echo -e "${GREEN}$NUM\t${YELLOW}$USUARIO\t$CLAVE\t$EXPIRA\t$DURACION${NC}"
  done

  echo
  read -p "$(echo -e ${YELLOW}"Ingrese el número del usuario a eliminar (0 para cancelar): "${NC})" NUMERO
  if [[ $NUMERO -eq 0 ]]; then
    echo -e "${BLUE}Operación cancelada.${NC}"
    read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
    return
  fi

  # Verificar si el número es válido
  TOTAL=$(wc -l < "$REGISTROS")
  if [[ $NUMERO -lt 1 || $NUMERO -gt $TOTAL ]]; then
    echo -e "${RED}Número inválido. Debe estar entre 1 y $TOTAL.${NC}"
    read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
    return
  fi

  # Obtener el usuario a eliminar
  USUARIO=$(awk -v n=$NUMERO 'NR==n {print $1}' "$REGISTROS")
  echo -e "${YELLOW}¿Confirmar eliminación del usuario ${RED}$USUARIO${YELLOW}? (s/n)${NC}"
  read -p "" CONFIRMAR
  if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
    echo -e "${BLUE}Operación cancelada.${NC}"
    read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
    return
  fi

  # Eliminar usuario del sistema
  userdel -r "$USUARIO" 2>/dev/null
  # Eliminar registro
  sed -i "${NUMERO}d" "$REGISTROS"

  echo -e "${GREEN}Usuario $USUARIO eliminado exitosamente.${NC}"
  read -p "$(echo -e ${BLUE}"Presiona Enter para continuar..."${NC})"
}

while true; do
  clear
  echo -e "${CYAN}====== PANEL DE USUARIOS VPN/SSH ======${NC}"
  echo -e "${GREEN}1. Crear usuario${NC}"
  echo -e "${YELLOW}2. Ver registros${NC}"
  echo -e "${RED}3. Eliminar usuario${NC}"
  echo -e "${BLUE}0. Salir${NC}"
  echo -e "${CYAN}=======================================${NC}"
  read -p "$(echo -e ${YELLOW}"Seleccione una opción: "${NC})" opcion

  case $opcion in
    1) crear_usuario ;;
    2) ver_registros ;;
    3) eliminar_usuario ;;
    0) echo -e "${BLUE}Saliendo...${NC}"; break ;;
    *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
  esac
done
