#!/bin/bash

# Colores para la salida
RED='\033[1;31m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;96m'
NC='\033[0m'

# Variables
REPO_URL="https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main"
MENU_URL="$REPO_URL/menu.sh"
PROXY_URL="$REPO_URL/etc/mccproxy/proxy.py"
MENU_PATH="/root/menu.sh"
PROXY_PATH="/etc/mccproxy/proxy.py"
API_URL="http://localhost:40412/validate"

# Función para mostrar mensajes
msg() {
    echo -e "${2}[ INFO ] $1${NC}"
}

# Función para mostrar errores
error() {
    echo -e "${RED}[ ERROR ] $1${NC}"
    exit 1
}

# Función para instalar dependencias
install_dependencies() {
    msg "Actualizando paquetes e instalando dependencias..."
    apt update -y >/dev/null 2>&1 && apt upgrade -y >/dev/null 2>&1
    apt install -y git wget curl dropbear screen python3 python3-pip lsb-release sqlite3 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        error "No se pudieron instalar las dependencias."
    fi
    pip3 install flask >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        error "No se pudo instalar Flask."
    fi
    msg "Dependencias instaladas correctamente." "${GREEN}"
}

# Función para descargar archivos
download_file() {
    local url=$1
    local dest=$2
    msg "Descargando $dest desde $url..."
    wget -q -O "$dest" "$url"
    if [ $? -ne 0 ] || [ ! -s "$dest" ]; then
        error "No se pudo descargar $dest."
    fi
    chmod +x "$dest"
    msg "$dest descargado correctamente." "${GREEN}"
}

# Función para validar MCC-KEY contra la API
validate_key() {
    local key=$1
    msg "Validando MCC-KEY: $key..."
    response=$(curl -s "$API_URL/$key")
    if [ $? -ne 0 ]; then
        error "No se pudo conectar con la API de validación."
    fi
    valida=$(echo "$response" | grep -o '"valida": *true' | wc -l)
    motivo=$(echo "$response" | grep -o '"motivo": *"[^"]*"' | cut -d'"' -f4)
    if [ "$valida" -eq 1 ]; then
        msg "MCC-KEY válida: $key" "${GREEN}"
    else
        error "MCC-KEY inválida. Motivo: $motivo"
    fi
}

# Función para configurar el panel
setup_panel() {
    download_file "$MENU_URL" "$MENU_PATH"
    mkdir -p /etc/mccproxy
    download_file "$PROXY_URL" "$PROXY_PATH"
    msg "Configurando el comando menu..."
    ln -sf "$MENU_PATH" /usr/bin/menu
    chmod +x /usr/bin/menu
    if [ ! -L /usr/bin/menu ] || [ "$(readlink /usr/bin/menu)" != "$MENU_PATH" ]; then
        error "No se pudo crear el enlace simbólico /usr/bin/menu."
    fi
    msg "Comando menu configurado correctamente." "${GREEN}"
    msg "Configurando persistencia del panel..."
    if ! grep -q "exec /usr/bin/menu" /root/.bashrc; then
        echo "[ -t 1 ] && exec /usr/bin/menu" >> /root/.bashrc
    fi
    msg "Persistencia configurada en .bashrc." "${GREEN}"
}

# Función para iniciar la API Flask si no está corriendo
start_api() {
    msg "Verificando estado de la API Flask..."
    if ! pgrep -f "flask run.*40412" >/dev/null; then
        msg "Iniciando API Flask en puerto 40412..."
        if [ -f /root/telegram-bot/validator.py ]; then
            screen -dmS flask_api bash -c "cd /root/telegram-bot && python3 validator.py"
            sleep 2
            if pgrep -f "flask run.*40412" >/dev/null; then
                msg "API Flask iniciada correctamente." "${GREEN}"
            else
                error "No se pudo iniciar la API Flask."
            fi
        else
            error "Script de API Flask no encontrado en /root/telegram-bot/validator.py."
        fi
    else
        msg "API Flask ya está corriendo." "${GREEN}"
    fi
}

# Función principal
main() {
    if [ $# -eq 0 ]; then
        error "Uso: $0 <MCC-KEY> [--mccpanel] [--proxy <KEY>]"
    fi

    local mcc_key=""
    local mccpanel=false
    local proxy_key=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --mccpanel)
                mccpanel=true
                shift
                ;;
            --proxy)
                proxy_key="$2"
                shift 2
                ;;
            *)
                mcc_key="$1"
                shift
                ;;
        esac
    done

    start_api
    validate_key "$mcc_key"

    if [ -n "$proxy_key" ]; then
        validate_key "$proxy_key"
    fi

    install_dependencies
    setup_panel

    if [ "$mccpanel" = true ]; then
        msg "Lanzando el McCarthey Panel..."
        exec /usr/bin/menu
    else
        msg "Instalación completada. Usa 'menu' para abrir el panel." "${GREEN}"
    fi
}

main "$@"
