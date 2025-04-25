#!/bin/bash

KEY="$1"
ARG="$2"
IP_API="172.233.189.223"
PORT_API="40412"
ENCODED_KEY=$(echo "$KEY" | sed 's/{/%7B/;s/}/%7D/')
VALIDADOR_URL="http://$IP_API:$PORT_API/validate/$ENCODED_KEY"

function instalar_dependencias() {
    echo "[ INFO ] Actualizando paquetes e instalando dependencias..."
    apt update -y &>/dev/null
    apt install -y curl net-tools &>/dev/null
    echo "[ INFO ] Dependencias instaladas correctamente."
}

function validar_key() {
    echo "[ INFO ] Validando KEY con API remota..."
    response=$(curl -s "$VALIDADOR_URL")
    echo "$response" | grep -q '"valida":true' && {
        echo "[ INFO ] KEY válida: $(echo "$response" | grep motivo)"
        return 0
    }
    echo "[ ERROR ] $(echo "$response" | grep motivo)"
    exit 1
}

function mostrar_panel() {
    while true; do
        clear
        echo "=== PANEL MCCARTHEY ==="
        echo "[1] Mostrar IP"
        echo "[2] Ver CPU y RAM"
        echo "[3] Crear usuario SSH"
        echo "[0] Salir"
        read -p "> " opt

        case $opt in
            1) echo -n "Tu IP pública: "; curl -s ifconfig.me ;;
            2) echo -e "\nCPU:"; lscpu | grep -E 'Model name|CPUs' ; echo -e "\nRAM:"; free -h ;;
            3) read -p "Nombre de usuario: " user
               read -p "Contraseña: " pass
               useradd -m -s /bin/bash "$user"
               echo "$user:$pass" | chpasswd
               echo "[ OK ] Usuario $user creado." ;;
            0) echo "Saliendo..."; exit ;;
            *) echo "Opción inválida." ;;
        esac
        read -p "Presiona ENTER para continuar..." dummy
    done
}

### FLUJO PRINCIPAL ###
[[ -z "$KEY" || "$ARG" != "--mccpanel" ]] && {
    echo "Uso correcto: ./installer.sh MCC-KEY{xxxx-xxxx-xxxx-xxxx} --mccpanel"
    exit 1
}

instalar_dependencias
validar_key
mostrar_panel
