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
    apt install -y git wget curl dropbear screen python3 lsb-release >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        error "No se pudieron instalar las dependencias."
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
}

# Función para validar MCC-KEY (simulada)
validate_key() {
    local key=$1
    # Aquí va tu lógica de validación de MCC-KEY (ejemplo simulado)
    if [[ ! "$key" =~ ^MCC-KEY\{[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}\}$ ]]; then
        error "MCC-KEY inválida. Formato esperado: MCC-KEY{XXXX-XXXX-XXXX-XXXX}"
    fi
    msg "MCC-KEY válida: $key" "${GREEN}"
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

    # Validar MCC-KEY
    validate_key "$mcc_key"

    # Si se pasa --proxy, validar la clave proxy
    if [ -n "$proxy_key" ]; then
        validate_key "$proxy_key"
    fi

    # Instalar dependencias
    install_dependencies

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
