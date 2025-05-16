#!/bin/bash

get_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) echo 'unsupported' ;;
    esac
}

install_checkuser() {
    local latest_release=$(curl -s https://api.github.com/repos/DTunnel0/CheckUser-Go/releases/latest | grep "tag_name" | cut -d'"' -f4)
    local arch=$(get_arch)

    if [ "$arch" = "unsupported" ]; then
        echo -e "\e[1;31mArquitectura de CPU no soportada!\e[0m"
        exit 1
    fi

    local name="checkuser-linux-$arch"
    echo "Descargando $name..."
    wget -q "https://github.com/DTunnel0/CheckUser-Go/releases/download/$latest_release/$name" -O /usr/local/bin/checkuser
    chmod +x /usr/local/bin/checkuser

    local addr="102.129.137.94"
    local domain="checkuser.alisson.shop"
    local port="8775"

    if systemctl status checkuser &>/dev/null 2>&1; then
        echo "Parando el servicio checkuser existente..."
        sudo systemctl stop checkuser
        sudo systemctl disable checkuser
        sudo rm /etc/systemd/system/checkuser.service
        sudo systemctl daemon-reload
        echo "Servicio checkuser existente fue parado y removido."
    fi

    cat << EOF | sudo tee /etc/systemd/system/checkuser.service > /dev/null
[Unit]
Description=CheckUser Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/checkuser --start --port $port
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload &>/dev/null
    sudo systemctl start checkuser &>/dev/null
    sudo systemctl enable checkuser &>/dev/null

    echo -e "\e[1;32mURL: \e[1;33mhttp://$domain:$port\e[0m"
    echo -e "\e[1;32mEl servicio CheckUser fue instalado y iniciado.\e[0m"
    read
}

reinstall_checkuser() {
    echo "Parando y removiendo el servicio checkuser..."
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm /usr/local/bin/checkuser
    sudo rm /etc/systemd/system/checkuser.service
    sudo systemctl daemon-reload &>/dev/null
    echo "Servicio checkuser removido."

    install_checkuser
}

uninstall_checkuser() {
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm /usr/local/bin/checkuser
    sudo rm /etc/systemd/system/checkuser.service
    sudo systemctl daemon-reload &>/dev/null
    echo "Serviço checkuser removido."
    read
}

main() {
    clear

    echo '---------------------------------'
    echo -ne '     \e[1;33mCHECKUSER\e[0m'
    if [[ -e /usr/local/bin/checkuser ]]; then
        echo -e ' \e[1;32mv'$(/usr/local/bin/checkuser --version | cut -d' ' -f2)'\e[0m'
    else
        echo -e ' \e[1;31m[DESINSTALADO]\e[0m'
    fi
    echo '---------------------------------'

    echo -e '\e[1;32m[01] - \e[1;31mINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[02] - \e[1;31mREINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[03] - \e[1;31mDESINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[00] - \e[1;31mSALIR\e[0m'
    echo '---------------------------------'
    echo -ne '\e[1;32mEscolha una opción: \e[0m'; 
    read option

    case $option in
        1) install_checkuser; main ;;
        2) reinstall_checkuser; main ;;
        3) uninstall_checkuser; main ;;
        0) echo "Saliendo.";;
        *) echo -e "\e[1;31mOpción inválida. Intenta nuevamente.\e[0m";read; main ;;
    esac
}

main
