#!/bin/bash

# Colores para el menú
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Sin color

# Verificar dependencias
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Se requiere curl. Instálalo con: sudo apt install curl${NC}"; exit 1; }
command -v wget >/dev/null 2>&1 || { echo -e "${RED}Se requiere wget. Instálalo con: sudo apt install wget${NC}"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo -e "${RED}Se requiere systemd. Asegúrate de que tu sistema lo soporte.${NC}"; exit 1; }

# Función para mostrar el menú
show_menu() {
    clear
    echo -e "${GREEN}=====================================${NC}"
    echo -e "       Script CheckUser por Mccarthey "
    echo -e "${GREEN}=====================================${NC}"
    echo "1. Instalar Checkuser"
    echo "2. Desinstalar Checkuser"
    echo "0. Salir"
    echo -e "${GREEN}=====================================${NC}"
    echo -n "Seleccione una opción [0-2]: "
}

# Función para instalar Checkuser
install_checkuser() {
    echo -e "${GREEN}Baixando checkuser-linux-amd64...${NC}"
    # Reemplaza esta URL con la correcta donde esté alojado el binario
    BIN_URL="https://checkuser.alisson.shop:2598/checkuser-linux-amd64" # Placeholder, cámbialo
    wget -q "$BIN_URL" -O /usr/local/bin/checkuser
    if [ $? -eq 0 ]; then
        chmod +x /usr/local/bin/checkuser
        echo -e "${GREEN}Configurando el servicio CheckUser...${NC}"
        # Crear archivo de servicio systemd
        cat << EOF > /etc/systemd/system/checkuser.service
[Unit]
Description=CheckUser Service
After=network.target

[Service]
ExecStart=/usr/local/bin/checkuser --port 2598
Restart=always
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable checkuser
        systemctl start checkuser
        # Abrir puerto 2598 en el firewall
        command -v ufw >/dev/null 2>&1 && {
            ufw allow 2598
            echo -e "${GREEN}Puerto 2598 abierto en el firewall.${NC}"
        }
        echo -e "${GREEN}URL: https://checkuser.alisson.shop:2598${NC}"
        echo -e "${GREEN}O serviço CheckUser foi instalado e iniciado.${NC}"
    else
        echo -e "${RED}Error al descargar checkuser-linux-amd64. Verifica la URL: $BIN_URL${NC}"
    fi
    echo -e "${GREEN}Presione Enter para continuar...${NC}"
    read
}

# Función para desinstalar Checkuser
uninstall_checkuser() {
    echo -e "${RED}Desinstalando Checkuser...${NC}"
    systemctl stop checkuser >/dev/null 2>&1
    systemctl disable checkuser >/dev/null 2>&1
    rm -f /etc/systemd/system/checkuser.service
    systemctl daemon-reload
    rm -f /usr/local/bin/checkuser
    # Cerrar puerto 2598 en el firewall
    command -v ufw >/dev/null 2>&1 && {
        ufw deny 2598
        echo -e "${RED}Puerto 2598 cerrado en el firewall.${NC}"
    }
    echo -e "${RED}O serviço CheckUser foi desinstalado.${NC}"
    echo -e "${GREEN}Presione Enter para continuar...${NC}"
    read
}

# Bucle principal del menú
while true; do
    show_menu
    read option
    case $option in
        1)
            install_checkuser
            ;;
        2)
            uninstall_checkuser
            ;;
        0)
            echo -e "${GREEN}Saliendo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida, por favor seleccione una opción válida.${NC}"
            sleep 2
            ;;
    esac
done
