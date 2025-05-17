#!/bin/bash

# Colores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Función para mostrar el menú
mostrar_menu() {
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${YELLOW}    SISTEMA DE GESTIÓN DE USUARIOS    ${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${GREEN}1. Crear usuario temporal${NC}"
    echo -e "${GREEN}2. Ver registro de usuarios${NC}"
    echo -e "${GREEN}3. Eliminar usuario${NC}"
    echo -e "${GREEN}4. Salir${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo -e -n "${BLUE}Seleccione una opción [1-4]: ${NC}"
}

# Función para crear usuario
crear_usuario() {
    read -p "Ingrese nombre de usuario: " USUARIO
    read -s -p "Ingrese contraseña: " CLAVE
    echo ""
    read -p "Ingrese días de validez: " DIAS

    # Verifica si se proporcionaron los datos
    if [ -z "$USUARIO" ] || [ -z "$CLAVE" ] || [ -z "$DIAS" ]; then
        echo -e "${RED}Error: Todos los campos son requeridos${NC}"
        return 1
    }

    # Verifica si el usuario ya existe
    if id "$USUARIO" &>/dev/null; then
        echo -e "${RED}El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
        return 1
    }

    # Crear el usuario con shell bash y directorio home
    useradd -m -s /bin/bash "$USUARIO"

    # Asignar contraseña
    echo "$USUARIO:$CLAVE" | chpasswd

    # Calcular la fecha exacta de expiración
    EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)

    # Establecer la expiración
    chage -E "$EXPIRA" "$USUARIO"

    # Formatear fecha bonita
    FECHA_FORMATO=$(date -d "$EXPIRA" +"%d de %B de %Y")

    # Confirmación clara
    echo -e "\n${GREEN}===== USUARIO CREADO EXITOSAMENTE =====${NC}"
    echo -e "${CYAN}Usuario: ${YELLOW}$USUARIO${NC}"
    echo -e "${CYAN}Contraseña: ${YELLOW}$CLAVE${NC}"
    echo -e "${CYAN}Duración: ${YELLOW}$DIAS días${NC}"
    echo -e "${CYAN}Último día válido: ${YELLOW}$FECHA_FORMATO (vence a las 23:59)${NC}"
    echo -e "${GREEN}=======================================${NC}"
}

# Función para ver registro de usuarios
ver_registro() {
    echo -e "\n${CYAN}===== REGISTRO DE USUARIOS =====${NC}"
    i=1
    while IFS=: read -r username _ _ _ _ _ home _; do
        if [[ "$home" == /home/* ]]; then
            expiry=$(chage -l "$username" | grep "Account expires" | awk -F": " '{print $2}' || echo "No especificada")
            echo -e "${YELLOW}$i. ${CYAN}Usuario: ${GREEN}$username ${CYAN}Expiración: ${GREEN}$expiry${NC}"
            ((i++))
        fi
    done < /etc/passwd
    echo -e "${CYAN}===============================${NC}"
}

# Función para eliminar usuario
eliminar_usuario() {
    echo -e "\n${CYAN}===== ELIMINAR USUARIO =====${NC}"
    ver_registro
    echo -e -n "${BLUE}Ingrese el número del usuario a eliminar: ${NC}"
    read numero

    # Obtener el nombre del usuario según el número
    i=1
    usuario_seleccionado=""
    while IFS=: read -r username _ _ _ _ _ home _; do
        if [[ "$home" == /home/* ]]; then
            if [ "$i" -eq "$numero" ]; then
                usuario_seleccionado="$username"
                break
            fi
            ((i++))
        fi
    done < /etc/passwd

    if [ -z "$usuario_seleccionado" ]; then
        echo -e "${RED}Número de usuario inválido${NC}"
        return 1
    }

    echo -e "${YELLOW}Usuario seleccionado: ${GREEN}$usuario_seleccionado${NC}"
    echo -e -n "${BLUE}¿Confirma la eliminación? (Presione Enter para confirmar, cualquier otra tecla para cancelar): ${NC}"
    read -s -n 1 confirmacion
    echo ""

    if [ -z "$confirmacion" ]; then
        userdel -r "$usuario_seleccionado" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Usuario $usuario_seleccionado eliminado exitosamente${NC}"
        else
            echo -e "${RED}Error al eliminar el usuario${NC}"
        fi
    else
        echo -e "${YELLOW}Operación cancelada${NC}"
    fi
}

# Bucle principal del menú
while true; do
    mostrar_menu
    read opcion
    case $opcion in
        1)
            crear_usuario
            echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
            read
            ;;
        2)
            ver_registro
            echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
            read
            ;;
        3)
            eliminar_usuario
            echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
            read
            ;;
        4)
            echo -e "${GREEN}¡Hasta luego!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
            read
            ;;
    esac
done
