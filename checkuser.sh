#!/bin/bash

echo ""
echo "Tigo un Scrip referente al Scrip checkuser.sh que subí a github"
echo ""
echo "1. Instalar Checkuser"
echo "2. Desinstalar Checkuser"
echo ""

read -p "Selecciona una opción [1-2]: " opcion

if [[ $opcion == "1" ]]; then
    echo ""
    echo "Baixando checkuser-linux-amd64..."
    echo "URL: https://checkuser.alisson.shop:2598"
    echo ""
    curl -o /usr/bin/checkuser https://checkuser.alisson.shop:2598/checkuser-linux-amd64
    chmod +x /usr/bin/checkuser
    echo ""
    echo "O serviço CheckUser foi instalado e iniciado."
    echo ""
elif [[ $opcion == "2" ]]; then
    rm -f /usr/bin/checkuser
    echo ""
    echo "CheckUser foi desinstalado."
    echo ""
else
    echo ""
    echo "Opção inválida."
    echo ""
fi
