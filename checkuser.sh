#!/bin/bash

# Colores para el menú
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Sin color

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
    sleep 2
    echo -e "${GREEN}URL: https://checkuser.alisson.shop:2598${NC}"
    sleep 1
    echo -e "${GREEN}O serviço CheckUser foi instalado e iniciado.${NC}"
    sleep 2
}

# Función para desinstalar Checkuser
uninstall_checkuser() {
    echo -e "${RED}Desinstalando Checkuser...${NC}"
    sleep 2
    echo -e "${RED}O serviço CheckUser foi desinstalado.${NC}"
    sleep 2
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
