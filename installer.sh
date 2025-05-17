#!/bin/bash

REGISTRO="usuarios.txt"

while true; do
  clear
  echo "====== PANEL DE USUARIOS ======"
  echo "1. Crear usuario"
  echo "2. Ver registros"
  echo "3. Verificar conexión WebSocket"
  echo "0. Salir"
  echo "================================"
  read -p "Seleccione una opción: " OPCION

  case $OPCION in
    1)
      clear
      echo "===== CREAR NUEVO USUARIO ====="
      read -p "Digite nombre de usuario: " USUARIO
      read -p "Digite la contraseña: " CLAVE
      read -p "Días de duración: " DIAS

      # Verifica si el usuario ya existe
      if id "$USUARIO" &>/dev/null; then
        echo "El usuario '$USUARIO' ya existe. No se puede crear."
        read -p "Presiona Enter para volver al menú..."
        continue
      fi

      # Crear el usuario
      useradd -m -s /bin/bash "$USUARIO"
      echo "$USUARIO:$CLAVE" | chpasswd

      # Calcular la fecha exacta de expiración
      EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)
      chage -E "$EXPIRA" "$USUARIO"

      # Guardar en registros
      FECHA_FORMATO=$(date -d "$EXPIRA" +"%d de %B de %Y")
      echo -e "$USUARIO\t$CLAVE\t$FECHA_FORMATO\t$DIAS días" >> "$REGISTRO"

      echo ""
      echo "===== USUARIO CREADO EXITOSAMENTE ====="
      echo "Usuario: $USUARIO"
      echo "Contraseña: $CLAVE"
      echo "Duración: $DIAS días"
      echo "Expira: $FECHA_FORMATO (23:59)"
      echo "======================================="
      read -p "Presiona Enter para volver al menú..."
      ;;
      
    2)
      clear
      echo "===== REGISTRO DE USUARIOS ====="
      if [[ -f "$REGISTRO" ]]; then
        echo -e "Usuario\t\tClave\t\tVencimiento\t\tDuración"
        echo "----------------------------------------------------------"
        column -t "$REGISTRO"
      else
        echo "No hay registros aún."
      fi
      echo "================================"
      read -p "Presiona Enter para volver al menú..."
      ;;
    
    3)
      clear
      echo "===== VERIFICAR CONEXIÓN WEBSOCKET ====="
      read -p "Ingresa el nombre de usuario a verificar: " USUARIO

      # Verifica si el usuario tiene una sesión activa
      SESION_ACTIVA=$(who | grep "^$USUARIO ")

      # Verifica si hay conexiones activas al puerto 80
      CONEXION_P80=$(lsof -i :80 -n | grep "$USUARIO")

      echo ""
      echo "===== ESTADO DE CONEXIÓN ====="
      if [[ -n "$SESION_ACTIVA" || -n "$CONEXION_P80" ]]; then
        echo "$USUARIO está conectado por WebSocket (puerto 80)"
      else
        echo "$USUARIO no está conectado por WebSocket"
      fi
      echo "==============================="
      read -p "Presiona Enter para volver al menú..."
      ;;
      
    0)
      echo "Saliendo del panel..."
      exit 0
      ;;
      
    *)
      echo "Opción inválida."
      read -p "Presiona Enter para volver al menú..."
      ;;
  esac
done
