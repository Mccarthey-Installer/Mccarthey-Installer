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
API_SCRIPT_URL="$REPO_URL/api.py"
MENU_PATH="/root/menu.sh"
PROXY_PATH="/etc/mccproxy/proxy.py"
API_PATH="/root/telegram-bot/api.py"
DB_PATH="/root/telegram-bot/keys.db"
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
    # Instalar Flask
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
    chmod +x "$dest" 2>/dev/null
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

# Función para inicializar la base de datos SQLite
setup_db() {
    msg "Configurando base de datos SQLite..."
    if [ ! -f "$DB_PATH" ]; then
        sqlite3 "$DB_PATH" <<EOF
CREATE TABLE keys (
    key TEXT PRIMARY KEY,
    fecha_creacion TEXT,
    usado INTEGER,
    expirado INTEGER
);
EOF
        if [ $? -eq 0 ]; then
            msg "Base de datos creada correctamente." "${GREEN}"
        else
            error "No se pudo crear la base de datos SQLite."
        fi
    else
        msg "Base de datos ya existe." "${GREEN}"
    fi
}

# Función para instalar y descargar la API Flask
setup_api() {
    msg "Configurando API Flask..."
    mkdir -p /root/telegram-bot
    if [ ! -f "$API_PATH" ]; then
        download_file "$API_SCRIPT_URL" "$API_PATH"
    else
        msg "$API_PATH ya existe." "${GREEN}"
    fi
    setup_db
}

# Función para iniciar la API Flask si no está corriendo
start_api() {
    msg "Verificando estado de la API Flask..."
    if ! ss -tuln | grep -q ":40412 "; then
        msg "Iniciando API Flask en puerto 40412..."
        # Verificar si el puerto está en uso
        if ss -tuln | grep -q ":40412 "; then
            msg "Puerto 40412 en uso, intentando liberar..." "${YELLOW}"
            fuser -k 40412/tcp >/dev/null 2>&1
            sleep 1
        fi
        if [ -f "$API_PATH" ]; then
            # Probar ejecución para capturar error
            error_log=$(mktemp)
            screen -dmS flask_api bash -c "cd /root/telegram-bot && python3 api.py 2>$error_log"
            sleep 3
            if ss -tuln | grep -q ":40412 "; then
                msg "API Flask iniciada correctamente." "${GREEN}"
                rm -f "$error_log"
            else
                error_msg=$(cat "$error_log")
                rm -f "$error_log"
                error "No se pudo iniciar la API Flask. Error: $error_msg"
            fi
        else
            error "Script de API Flask no encontrado en $API_PATH."
        fi
    else
        msg "API Flask ya está corriendo." "${GREEN}"
    fi
}

# Función para configurar el panel
setup_panel() {
    # Descargar menu.sh
    download_file "$MENU_URL" "$MENU_PATH"

    # Descargar proxy.py
    mkdir -p /etc/mccproxy
    download_file "$PROXY_URL" "$PROXY_PATH"

    # Crear enlace simbólico para el comando menu
    msg "Configurando el comando menu..."
    ln -sf "$MENU_PATH" /usr/bin/menu
    chmod +x /usr/bin/menu
    if [ ! -L /usr/bin/menu ] || [ "$(readlink /usr/bin/menu)" != "$MENU_PATH" ]; then
        error "No se pudo crear el enlace simbólico /usr/bin/menu."
    fi
    msg "Comando menu configurado correctamente." "${GREEN}"

    # Configurar persistencia en .bashrc
    msg "Configurando persistencia del panel..."
    if ! grep -q "exec /usr/bin/menu" /root/.bashrc; then
        echo "[ -t 1 ] && exec /usr/bin/menu" >> /root/.bashrc
    fi
    msg "Persistencia configurada en .bashrc." "${GREEN}"
}

# Función principal
main() {
    # Verificar si se ejecuta con parámetros
    if [ $# -eq 0 ]; then
        error "Uso: $0 <MCC-KEY> [--mccpanel] [--proxy <KEY>]"
    fi

    local mcc_key=""
    local mccpanel=false
    local proxy_key=""

    # Parsear argumentos
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

    # Instalar dependencias
    install_dependencies

    # Configurar e iniciar API Flask
    setup_api
    start_api

    # Validar MCC-KEY
    validate_key "$mcc_key"

    # Si se pasa --proxy, validar la clave proxy
    if [ -n "$proxy_key" ]; then
        validate_key "$proxy_key"
    fi

    # Configurar el panel
    setup_panel

    # Si se pasa --mccpanel, lanzar el panel
    if [ "$mccpanel" = true ]; then
        msg "Lanzando el McCarthey Panel..."
        exec /usr/bin/menu
    else
        msg "Instalación completada. Usa 'menu' para abrir el panel." "${GREEN}"
    fi
}

# Ejecutar la función principal
main "$@"
