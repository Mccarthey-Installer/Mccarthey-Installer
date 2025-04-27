#!/bin/bash

API_URL="http://102.129.137.174:3000"
LOG_FILE="/var/log/ssh_manager.log"

# Colores para el menú
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner chido
banner() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${YELLOW}          Mccarthey SSH Manager - ¡Bien robusto!             ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo
}

# Instalar jq si no está
if ! command -v jq &> /dev/null; then
    echo "Instalando jq..."
    apt update -y
    apt install -y jq
fi

# Registrar acción en log
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Validar clave
check_key() {
    KEY=$1
    RESPONSE=$(curl -s "$API_URL/keys/$KEY")
    if echo "$RESPONSE" | jq -e '.error' >/dev/null; then
        echo -e "${RED}Error: $(echo "$RESPONSE" | jq -r '.error')${NC}"
        log_action "Error validando clave $KEY: $(echo "$RESPONSE" | jq -r '.error')"
        exit 1
    fi
    EXPIRATION=$(echo "$RESPONSE" | jq -r '.expiration')
    USED=$(echo "$RESPONSE" | jq -r '.used')
    CURRENT_TIME=$(date +%s)
    if (( $(echo "$EXPIRATION > $CURRENT_TIME" | bc -l) )); then
        if [ "$USED" = "false" ]; then
            echo -e "${GREEN}Clave válida. Accediendo al panel...${NC}"
            log_action "Clave válida $KEY. Acceso concedido."
            curl -s -X POST "$API_URL/keys/$KEY/use"
            return 0
        else
            echo -e "${RED}Error: Clave ya usada. Genera una nueva con el bot.${NC}"
            log_action "Error: Clave $KEY ya usada."
            exit 1
        fi
    else
        echo -e "${RED}Error: Clave expirada. Genera una nueva con el bot.${NC}"
        log_action "Error: Clave $KEY expirada."
        exit 1
    fi
}

# Menú principal
menu() {
    banner
    echo -e "${BLUE}Opciones:${NC}"
    echo "1) Gestionar usuarios"
    echo "2) Configurar puerto SSH"
    echo "3) Monitorear recursos"
    echo "4) Gestionar servicios"
    echo "5) Instalar software"
    echo "6) Salir"
    echo
    read -p "Selecciona una opción [1-6]: " OPTION
    case $OPTION in
        1) manage_users ;;
        2) configure_ssh_port ;;
        3) monitor_resources ;;
        4) manage_services ;;
        5) install_software ;;
        6) echo "Saliendo..."; log_action "Usuario salió del panel."; exit 0 ;;
        *) echo -e "${RED}Opción inválida.${NC}"; sleep 2; menu ;;
    esac
}

# Gestionar usuarios
manage_users() {
    banner
    echo -e "${BLUE}Gestión de usuarios:${NC}"
    echo "1) Crear usuario"
    echo "2) Eliminar usuario"
    echo "3) Listar usuarios"
    echo "4) Volver"
    read -p "Selecciona una opción [1-4]: " USER_OPTION
    case $USER_OPTION in
        1)
            read -p "Nombre del usuario: " USERNAME
            adduser "$USERNAME"
            log_action "Usuario $USERNAME creado."
            echo -e "${GREEN}Usuario creado.${NC}"
            sleep 2
            manage_users
            ;;
        2)
            read -p "Nombre del usuario a eliminar: " USERNAME
            deluser --remove-home "$USERNAME"
            log_action "Usuario $USERNAME eliminado."
            echo -e "${GREEN}Usuario eliminado.${NC}"
            sleep 2
            manage_users
            ;;
        3)
            echo -e "${BLUE}Usuarios en el sistema:${NC}"
            cut -d: -f1 /etc/passwd
            log_action "Listado de usuarios solicitado."
            read -p "Presiona Enter para continuar..."
            manage_users
            ;;
        4) menu ;;
        *) echo -e "${RED}Opción inválida.${NC}"; sleep 2; manage_users ;;
    esac
}

# Configurar puerto SSH
configure_ssh_port() {
    banner
    read -p "Nuevo puerto SSH (ej. 2222): " NEW_PORT
    if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -ge 1024 ] && [ "$NEW_PORT" -le 65535 ]; then
        sed -i "s/#Port .*/Port $NEW_PORT/" /etc/ssh/sshd_config
        systemctl restart sshd
        log_action "Puerto SSH cambiado a $NEW_PORT."
        echo -e "${GREEN}Puerto SSH cambiado a $NEW_PORT.${NC}"
    else
        echo -e "${RED}Puerto inválido. Usa un número entre 1024 y 65535.${NC}"
        log_action "Error: Puerto SSH $NEW_PORT inválido."
    fi
    sleep 2
    menu
}

# Monitorear recursos
monitor_resources() {
    banner
    echo -e "${BLUE}Recursos del sistema:${NC}"
    echo -e "${YELLOW}CPU:${NC}"
    top -bn1 | head -n 3
    echo -e "${YELLOW}Memoria:${NC}"
    free -h
    echo -e "${YELLOW}Disco:${NC}"
    df -h
    log_action "Monitoreo de recursos solicitado."
    read -p "Presiona Enter para continuar..."
    menu
}

# Gestionar servicios
manage_services() {
    banner
    echo -e "${BLUE}Gestión de servicios:${NC}"
    echo "1) Iniciar servicio"
    echo "2) Parar servicio"
    echo "3) Reiniciar servicio"
    echo "4) Listar servicios"
    echo "5) Volver"
    read -p "Selecciona una opción [1-5]: " SERVICE_OPTION
    case $SERVICE_OPTION in
        1)
            read -p "Nombre del servicio (ej. sshd): " SERVICE
            systemctl start "$SERVICE"
            log_action "Servicio $SERVICE iniciado."
            echo -e "${GREEN}Servicio $SERVICE iniciado.${NC}"
            sleep 2
            manage_services
            ;;
        2)
            read -p "Nombre del servicio (ej. sshd): " SERVICE
            systemctl stop "$SERVICE"
            log_action "Servicio $SERVICE detenido."
            echo -e "${GREEN}Servicio $SERVICE detenido.${NC}"
            sleep 2
            manage_services
            ;;
        3)
            read -p "Nombre del servicio (ej. sshd): " SERVICE
            systemctl restart "$SERVICE"
            log_action "Servicio $SERVICE reiniciado."
            echo -e "${GREEN}Servicio $SERVICE reiniciado.${NC}"
            sleep 2
            manage_services
            ;;
        4)
            echo -e "${BLUE}Servicios en el sistema:${NC}"
            systemctl list-units --type=service
            log_action "Listado de servicios solicitado."
            read -p "Presiona Enter para continuar..."
            manage_services
            ;;
        5) menu ;;
        *) echo -e "${RED}Opción inválida.${NC}"; sleep 2; manage_services ;;
    esac
}

# Instalar software
install_software() {
    banner
    echo -e "${BLUE}Instalar software:${NC}"
    echo "1) Cockpit"
    echo "2) Nginx"
    echo "3) Volver"
    read -p "Selecciona una opción [1-3]: " SOFTWARE_OPTION
    case $SOFTWARE_OPTION in
        1)
            apt update -y
            apt install -y cockpit
            systemctl enable --now cockpit.socket
            log_action "Cockpit instalado."
            echo -e "${GREEN}Cockpit instalado. Accede en: http://$(hostname -I | awk '{print $1}'):9090${NC}"
            sleep 2
            install_software
            ;;
        2)
            apt update -y
            apt install -y nginx
            systemctl enable --now nginx
            log_action "Nginx instalado."
            echo -e "${GREEN}Nginx instalado.${NC}"
            sleep 2
            install_software
            ;;
        3) menu ;;
        *) echo -e "${RED}Opción inválida.${NC}"; sleep 2; install_software ;;
    esac
}

# Validar argumentos
if [ $# -lt 1 ]; then
    echo "Uso: ./installer.sh <clave> --mccpanel"
    exit 1
fi

# Crear archivo de log si no existe
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

KEY=$1
OPTION=$2

if [ "$OPTION" == "--mccpanel" ]; then
    check_key $KEY
    echo "Instalando dependencias para Mccarthey SSH Manager..."
    apt update -y
    apt install -y openssh-server
    echo "Dependencias instaladas. Iniciando Mccarthey SSH Manager..."
    # Entrar al menú directamente
    while true; do
        menu
    done
else
    echo "Opción inválida. Usa --mccpanel."
    exit 1
fi
