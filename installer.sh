#!/bin/bash

# Uso: ./crear_usuario_temporal.sh nombre_usuario contraseña dias_validez

USUARIO=$1
CLAVE=$2
DIAS=$3

# Colores para embellecer la salida
ROJO="\e[31m"
VERDE="\e[32m"
AMARILLO="\e[33m"
AZUL="\e[34m"
MAGENTA="\e[35m"
CIAN="\e[36m"
BLANCO="\e[97m"
RESET="\e[0m"
LINEA="=============================================="

# Verifica si se proporcionaron los 3 argumentos
if [ $# -ne 3 ]; then
  echo -e "${ROJO}Uso: $0 nombre_usuario contraseña dias_validez${RESET}"
  exit 1
fi

# Verifica si el usuario ya existe
if id "$USUARIO" &>/dev/null; then
  echo -e "${ROJO}El usuario '$USUARIO' ya existe. No se puede crear.${RESET}"
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
echo -e "${CIAN}${LINEA}${RESET}"
echo -e "${VERDE}===== USUARIO CREADO EXITOSAMENTE =====${RESET}"
echo -e "${AMARILLO}Usuario:${RESET} $USUARIO"
echo -e "${AMARILLO}Contraseña:${RESET} $CLAVE"
echo -e "${AMARILLO}Duración:${RESET} $DIAS días"
echo -e "${AMARILLO}Último día válido:${RESET} $FECHA_FORMATO (vence a las 23:59)"
echo -e "${CIAN}${LINEA}${RESET}"
echo ""

# Función para mostrar usuarios con expiración
mostrar_usuarios() {
  echo -e "${MAGENTA}Lista de usuarios con fecha de expiración:${RESET}"
  echo ""
  # Listar usuarios con expiración configurada y numerarlos
  mapfile -t usuarios < <(awk -F: '($3>=1000)&&($3!=65534){print $1}' /etc/passwd)
  local index=1
  for u in "${usuarios[@]}"; do
    exp_date=$(chage -l "$u" | grep "Account expires" | cut -d: -f2 | xargs)
    echo -e " ${AMARILLO}$index)${RESET} Usuario: ${CIAN}$u${RESET} - Expira: ${VERDE}$exp_date${RESET}"
    ((index++))
  done
  echo ""
}

# Función para eliminar usuario según índice
eliminar_usuario() {
  if [ ${#usuarios[@]} -eq 0 ]; then
    echo -e "${ROJO}No hay usuarios temporales para eliminar.${RESET}"
    return
  fi

  mostrar_usuarios

  read -p "$(echo -e ${AMARILLO}Ingrese el número del usuario a eliminar: ${RESET})" opcion

  if ! [[ "$opcion" =~ ^[0-9]+$ ]] || [ "$opcion" -lt 1 ] || [ "$opcion" -gt "${#usuarios[@]}" ]; then
    echo -e "${ROJO}Opción inválida.${RESET}"
    return
  fi

  usuario_eliminar=${usuarios[$((opcion-1))]}

  read -p "$(echo -e ${ROJO}¿Confirmar eliminar usuario '$usuario_eliminar'? (s/n): ${RESET})" confirmar

  if [[ "$confirmar" =~ ^[sS]$ ]]; then
    userdel -r "$usuario_eliminar" && \
    echo -e "${VERDE}Usuario '$usuario_eliminar' eliminado correctamente.${RESET}" || \
    echo -e "${ROJO}Error eliminando el usuario.${RESET}"
  else
    echo -e "${AMARILLO}Eliminación cancelada.${RESET}"
  fi
}

# Menú final con opciones
while true; do
  echo -e "${CIAN}${LINEA}${RESET}"
  echo -e "${MAGENTA}Seleccione una opción:${RESET}"
  echo -e " ${AMARILLO}1)${RESET} Ver registro"
  echo -e " ${AMARILLO}2)${RESET} Opción 2 (no implementada)"
  echo -e " ${AMARILLO}3)${RESET} Eliminar usuario"
  echo -e " ${AMARILLO}0)${RESET} Salir"
  echo -e "${CIAN}${LINEA}${RESET}"
  read -p "$(echo -e ${AZUL}Ingrese su opción: ${RESET})" opcion_menu

  case $opcion_menu in
    1)
      mostrar_usuarios
      ;;
    2)
      echo -e "${AMARILLO}Opción 2 aún no implementada.${RESET}"
      ;;
    3)
      eliminar_usuario
      ;;
    0)
      echo -e "${VERDE}Saliendo...${RESET}"
      break
      ;;
    *)
      echo -e "${ROJO}Opción inválida. Intente de nuevo.${RESET}"
      ;;
  esac
done
