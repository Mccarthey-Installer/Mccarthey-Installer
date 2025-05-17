#!/bin/bash

while true; do
  clear
  echo "===== PANEL DE USUARIOS SSH POR ERICK ====="
  echo ""
  echo "1) Crear usuario temporal"
  echo "2) Listar usuarios"
  echo "3) Verificar conexión WebSocket (puerto 80)"
  echo "0) Salir"
  echo ""
  read -p "Selecciona una opción: " OPCION

  case $OPCION in
    1)
      clear
      echo "===== CREAR USUARIO TEMPORAL ====="
      read -p "Nombre de usuario: " USUARIO
      read -p "Contraseña: " CLAVE
      read -p "Días de validez: " DIAS

      if id "$USUARIO" &>/dev/null; then
        echo "El usuario '$USUARIO' ya existe. No se puede crear."
      else
        useradd -m -s /bin/bash $USUARIO
        echo "$USUARIO:$CLAVE" | chpasswd
        EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)
        chage -E $EXPIRA $USUARIO
        FECHA_FORMATO=$(date -d "$EXPIRA" +"%d de %B de %Y")
        echo ""
        echo "===== USUARIO CREADO EXITOSAMENTE ====="
        echo "Usuario: $USUARIO"
        echo "Contraseña: $CLAVE"
        echo "Duración: $DIAS días"
        echo "Válido hasta: $FECHA_FORMATO"
        echo "======================================="
      fi
      read -p "Presiona Enter para volver al menú..."
      ;;

    2)
      clear
      echo "===== LISTA DE USUARIOS ====="
      echo ""
      printf "%-20s %-15s\n" "USUARIO" "EXPIRA"
      echo "-----------------------------------------"
      for u in $(cut -d: -f1 /etc/passwd); do
        expira=$(chage -l $u 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        if [[ "$expira" != "never" && -n "$expira" ]]; then
          printf "%-20s %-15s\n" "$u" "$expira"
        fi
      done
      echo ""
      read -p "Presiona Enter para volver al menú..."
      ;;

    3)
      clear
      echo "===== VERIFICAR CONEXIÓN WEBSOCKET ====="
      read -p "Ingresa el nombre de usuario a verificar: " USUARIO

      # Verifica si tiene sesión activa
      SESION_ACTIVA=$(who | grep "^$USUARIO ")

      # Intenta detectar conexiones al puerto 80 por procesos del usuario
      CONEXION_P80=$(ss -tunp | grep ':80' | grep "$USUARIO")

      echo ""
      echo "===== ESTADO DE CONEXIÓN ====="
      if [[ -n "$SESION_ACTIVA" || -n "$CONEXION_P80" ]]; then
        echo "$USUARIO podría estar conectado por WebSocket (puerto 80)"
        echo "(Sesión o conexión detectada)"
      else
        echo "$USUARIO no está conectado o no se detecta actividad en puerto 80"
      fi
      echo "==============================="
      read -p "Presiona Enter para volver al menú..."
      ;;

    0)
      echo "Saliendo..."
      exit 0
      ;;

    *)
      echo "Opción no válida."
      read -p "Presiona Enter para continuar..."
      ;;
  esac
done
