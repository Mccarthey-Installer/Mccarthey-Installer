#!/bin/bash

# ================================
# ███╗   ███╗ ██████╗ ██████╗ ███████╗
# ████╗ ████║██╔═══██╗██╔══██╗██╔════╝
# ██╔████╔██║██║   ██║██████╔╝█████╗  
# ██║╚██╔╝██║██║   ██║██╔═══╝ ██╔══╝  
# ██║ ╚═╝ ██║╚██████╔╝██║     ███████╗
# ╚═╝     ╚═╝ ╚═════╝ ╚═╝     ╚══════╝
#       McCarthey Installer v1.4
# ================================

# ARGUMENTOS
ENABLE_PANEL=false
ENABLE_PROXY=true  # Por defecto, instalamos proxy.py para todos
for arg in "$@"; do
    if [[ "$arg" == "--mccpanel" ]]; then
        ENABLE_PANEL=true
    fi
    if [[ "$arg" == "--proxy" ]]; then
        ENABLE_PROXY=true
    fi
done

# OBTENER MCC-KEY
KEY=""
for arg in "$@"; do
    if [[ "$arg" != "--mccpanel" && "$arg" != "--proxy" ]]; then
        KEY="$arg"
        break
    fi
done

if [ -z "$KEY" ]; then
    clear
    echo -e "\e[1;34m"
    echo "============================================="
    echo "          having MCC-KEY NO PROPORCIONADA          "
    echo "============================================="
    echo -e "\e[0m"

    echo -e "\e[1;36m"
    echo "╔═══════════════════════════════════════════╗"
    echo "║           INGRESA TU MCC-KEY              ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "\e[0m"

    read -p "> " KEY
fi

ENCODED_KEY=$(echo "$KEY" | sed 's/{/%7B/' | sed 's/}/%7D/')
VALIDATOR_URL="http://172.235.128.99:9393/validate/$ENCODED_KEY"

# Validación con reintentos
echo -e "\n\033[1;34m[ INFO ]\033[0m Verificando KEY con el servidor..."
for attempt in {1..3}; do
    RESPONSE=$(curl -s --connect-timeout 5 "$VALIDATOR_URL")
    if [ $? -eq 0 ]; then
        break
    fi
    echo -e "\033[1;33m[ WARN ]\033[0m Intento $attempt falló. Reintentando..."
    sleep 2
done

if [ -z "$RESPONSE" ]; then
    echo -e "\n\033[1;31m[ ERROR ]\033[0m No se pudo contactar al servidor de validación."
    exit 1
fi

VALIDO=$(echo "$RESPONSE" | grep -o '"valida":true')

if [ -z "$VALIDO" ]; then
    MOTIVO=$(echo "$RESPONSE" | grep -oP '"motivo":"\K[^"]+')
    echo -e "\n\033[1;31m[ ERROR ]\033[0m Key inválida: $MOTIVO"
    exit 1
fi

USERNAME=$(echo "$RESPONSE" | grep -oP '"username":"\K[^"]+')
echo -e "\n\033[1;32m[ OK ]\033[0m Key válida. Continuando con la instalación..."
echo -e "\033[1;34mKey: Verified【  $USERNAME  】\033[0m"

# ACTUALIZACIÓN DEL SISTEMA
echo -e "\n\033[1;33m==============================================\033[0m"
echo -e "\033[1;33m      ACTUALIZANDO SISTEMA Y PAQUETES          \033[0m"
echo -e "\033[1;33m==============================================\033[0m"

apt update -y && apt upgrade -y
if command -v needrestart >/dev/null; then
    needrestart -r a
fi

apt install -y curl unzip wget

# INSTALACIÓN DE PAQUETES
PAQUETES=(
  bsdmainutils screen nload htop python3
  nodejs npm lsof psmisc socat bc net-tools cowsay
  nmap jq iptables openssh-server dropbear
)

echo -e "\n\033[1;33m==============================================\033[0m"
echo -e "\033[1;33m          INSTALANDO PAQUETES NECESARIOS        \033[0m"
echo -e "\033[1;33m==============================================\033[0m"

for paquete in "${PAQUETES[@]}"; do
    echo -e "\033[1;34m[ INFO ]\033[0m Instalando $paquete..."
    if ! apt install -y "$paquete"; then
        echo -e "\033[1;31m[ FAIL ]\033[0m Error al instalar: ${paquete^^}"
    elif dpkg -s "$paquete" &>/dev/null; then
        echo -e "\033[1;32m[ OK ]\033[0m Instalación correcta: ${paquete^^}"
    else
        echo -e "\033[1;31m[ FAIL ]\033[0m Error al verificar: ${paquete^^}"
    fi
done

# CONFIGURAR OPENSSH EN PUERTO 22
echo -e "\n\033[1;33m==============================================\033[0m"
echo -e "\033[1;33m          CONFIGURANDO OPENSSH (PUERTO 22)      \033[0m"
echo -e "\033[1;33m==============================================\033[0m"

systemctl enable ssh &>/dev/null
systemctl start ssh &>/dev/null

if ss -tuln | grep -q ":22 "; then
    echo -e "\033[1;32m[ OK ]\033[0m OpenSSH está activo en el puerto 22."
else
    sed -i 's/^#Port 22/Port 22/' /etc/ssh/sshd_config
    systemctl restart ssh &>/dev/null
    if ss -tuln | grep -q ":22 "; then
        echo -e "\033[1;32m[ OK ]\033[0m OpenSSH configurado y activo en el puerto 22."
    else
        echo -e "\033[1;31m[ FAIL ]\033[0m No se pudo activar OpenSSH en el puerto 22."
    fi
fi

ufw allow 22 &>/dev/null
ufw enable &>/dev/null
echo -e "\033[1;32m[ OK ]\033[0m Puerto 22 permitido en ufw."

# INSTALACIÓN Y CONFIGURACIÓN AUTOMÁTICA DE DROPBEAR Y PROXY.PY
if $ENABLE_PROXY; then
    echo -e "\n\033[1;33m==============================================\033[0m"
    echo -e "\033[1;33m      CONFIGURANDO DROPBEAR Y PROXY.PY         \033[0m"
    echo -e "\033[1;33m==============================================\033[0m"

    # Instalar Dropbear si no está instalado
    if ! dpkg -s dropbear &>/dev/null; then
        echo -e "\n[+] Instalando Dropbear..."
        apt install dropbear -y
        if dpkg -s dropbear &>/dev/null; then
            echo -e "\033[1;32m[ OK ]\033[0m Dropbear instalado correctamente."
        else
            echo -e "\033[1;31m[ FAIL ]\033[0m Error al instalar Dropbear."
            exit 1
        fi
    fi

    # Configurar Dropbear en puerto 444
    echo -e "\n[+] Configurando Dropbear en puerto 444..."
    echo "/bin/false" >> /etc/shells
    echo "/usr/sbin/nologin" >> /etc/shells
    sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear
    echo 'DROPBEAR_EXTRA_ARGS="-p 444"' >> /etc/default/dropbear

    # Reiniciar Dropbear
    systemctl restart dropbear &>/dev/null || service dropbear restart &>/dev/null

    # Verificar si Dropbear está activo
    if pgrep dropbear > /dev/null && ss -tuln | grep -q ":444 "; then
        echo -e "\033[1;32m[ OK ] Dropbear activado en puerto 444.\033[0m"
    else
        echo -e "\033[1;31m[ FAIL ] Error: No se pudo iniciar Dropbear en el puerto 444.\033[0m"
        journalctl -u dropbear -n 10 --no-pager
        exit 1
    fi

    # Configurar proxy.py
    echo -e "\n[+] Configurando Proxy WS/Directo..."
    mkdir -p /etc/mccproxy

    # Usar el proxy.py proporcionado por el usuario
    cat << 'PROXY_EOF' > /etc/mccproxy/proxy.py
import socket
import threading
import select
import logging
import os

# Configuración de logging
logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(message)s', datefmt='%H:%M:%S')

# Cargar puertos desde archivos externos
def cargar_puertos():
    try:
        with open('/etc/mccproxy_ports') as f:
            return [int(p.strip()) for p in f.read().replace(',', ' ').split()]
    except:
        return [8080]  # Puerto por defecto

LISTEN_PORTS = cargar_puertos()
DESTINATION_HOST = '127.0.0.1'
DESTINATION_PORT = 444  # Dropbear u otro

# Encabezado WebSocket para handshake
WS_HANDSHAKE = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    "Sec-WebSocket-Accept: dummykey==\r\n\r\n"
)

def handle_client(client_socket):
    try:
        request = client_socket.recv(1024)
        if not request:
            client_socket.close()
            return

        # Detectar y responder handshake WebSocket sin cerrar conexión
        if b'Upgrade: websocket' in request:
            logging.info(f"[HANDSHAKE] WebSocket detectado")
            client_socket.sendall(WS_HANDSHAKE.encode())
            # No se cierra el socket

        # Redirigir tráfico al destino (Dropbear)
        remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_socket.connect((DESTINATION_HOST, DESTINATION_PORT))

        sockets = [client_socket, remote_socket]
        while True:
            read_sockets, _, _ = select.select(sockets, [], [])
            for sock in read_sockets:
                data = sock.recv(4096)
                if not data:
                    client_socket.close()
                    remote_socket.close()
                    return
                if sock is client_socket:
                    remote_socket.sendall(data)
                else:
                    client_socket.sendall(data)
    except Exception as e:
        logging.error(f"Error manejando cliente: {e}")
        try:
            client_socket.close()
        except:
            pass

def start_proxy(port):
    try:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('0.0.0.0', port))
        server.listen(100)
        logging.info(f"[PROXY] Escuchando en puerto {port}")
        while True:
            client_socket, addr = server.accept()
            threading.Thread(target=handle_client, args=(client_socket,)).start()
    except Exception as e:
        logging.error(f"Error al iniciar proxy en puerto {port}: {e}")

if __name__ == '__main__':
    for port in LISTEN_PORTS:
        threading.Thread(target=start_proxy, args=(port,)).start()
PROXY_EOF

    if [ -f /etc/mccproxy/proxy.py ]; then
        echo -e "\033[1;32m[ OK ] Script proxy.py configurado correctamente.\033[0m"
    else
        echo -e "\033[1;31m[ FAIL ] Error al configurar proxy.py.\033[0m"
        exit 1
    fi

    # Crear archivo de configuración de puertos si no existe
    if [ ! -f /etc/mccproxy_ports ]; then
        echo "8080" > /etc/mccproxy_ports
        echo -e "\033[1;32m[ OK ] Creado /etc/mccproxy_ports con puerto predeterminado 8080.\033[0m"
    fi

    # Leer puertos de configuración
    PROXY_PORTS=$(cat /etc/mccproxy_ports | tr ',' ' ')

    # Verificar si los puertos están disponibles
    for port in $PROXY_PORTS; do
        if ss -tuln | grep -q ":$port "; then
            echo -e "\033[1;31m[ ERROR ] El puerto $port ya está en uso."
            echo -e "\033[1;34m[ INFO ] Intentando liberar el puerto $port...\033[0m"
            fuser -k "$port"/tcp &>/dev/null
            sleep 2
            if ! ss -tuln | grep -q ":$port "; then
                echo -e "\033[1;32m[ OK ] Puerto $port liberado.\033[0m"
            else
                echo -e "\033[1;31m[ FAIL ] No se pudo liberar el puerto $port.\033[0m"
                exit 1
            fi
        fi
    done

    # Iniciar proxy.py
    echo -e "\n[+] Iniciando Proxy en puertos $PROXY_PORTS"
    screen -dmS proxy python3 /etc/mccproxy/proxy.py
    sleep 2

    # Verificar si el proxy está corriendo
    if screen -list | grep -q "proxy"; then
        echo -e "\033[1;32m[ OK ] Proxy WS/Directo activo en puertos $PROXY_PORTS\033[0m"
    else
        echo -e "\033[1;31m[ FAIL ] Error: No se pudo iniciar el Proxy.\033[0m"
        exit 1
    fi
fi

# PANEL
if $ENABLE_PANEL; then
    echo -e "\n\033[1;33m==============================================\033[0m"
    echo -e "\033[1;33m      INSTALANDO PANEL MCCARTHEY               \033[0m"
    echo -e "\033[1;33m==============================================\033[0m"

    cat << 'EOF' > /root/menu.sh
#!/bin/bash

validar_key() {
    echo -e "\n\033[1;36m[ INFO ]\033[0m Descargando la última versión del instalador..."
    # Descargar el script principal (ajusta el nombre si es diferente)
    wget -q -O installer.sh https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/installer.sh
    if [ $? -ne 0 ]; then
        echo -e "\033[1;31m[ ERROR ] No se pudo descargar el script actualizado.\033[0m"
        read -p "Presiona enter para continuar..."
        return 1
    fi
    chmod +x installer.sh
    echo -e "\033[1;96m[ OK ] Script actualizado correctamente.\033[0m"
    
    # Solicitar nueva MCC-KEY
    echo -e "\n\033[1;36m[ INFO ] Ingresa tu nueva MCC-KEY:\033[0m"
    read -p "> " NEW_KEY
    
    # Ejecutar el script actualizado con la nueva MCC-KEY y los argumentos originales
    echo -e "\n\033[1;36m[ INFO ] Ejecutando el script actualizado...\033[0m"
    ./installer.sh --mccpanel --proxy "$NEW_KEY"
    if [ $? -ne 0 ]; then
        echo -e "\033[1;31m[ ERROR ] Error al ejecutar el script actualizado.\033[0m"
        read -p "Presiona enter para continuar..."
        return 1
    fi
    
    echo -e "\n\033[1;96m[ OK ] Actualización completada. Reiniciando el panel...\033[0m"
    exec /usr/bin/menu
}

# Datos del sistema
fecha=$(TZ=America/El_Salvador date +"%a %d/%m/%Y - %I:%M:%S %p %Z")
ip=$(hostname -I | awk '{print $1}')
cpu_model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo)
cpus=$(nproc)
so=$(lsb_release -d | cut -f2)

read total used free shared buff_cache available <<< $(free -m | awk '/^Mem:/ {print $2, $3, $4, $5, $6, $7}')
cpu_uso=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
cpu_uso_fmt=$(awk "BEGIN {printf \"%.1f%%\", $cpu_uso}")
ram_porc=$(awk "BEGIN {printf \"%.2f%%\", ($used/$total)*100}")

if [ "$total" -ge 1024 ]; then
    ram_total=$(awk "BEGIN {printf \"%.1fG\", $total/1024}")
    ram_libre=$(awk "BEGIN {printf \"%.1fG\", $available/1024}")
else
    ram_total="${total}M"
    ram_libre="${available}M"
fi

ram_usada=$(awk "BEGIN {printf \"%.0fM\", $used}")
ram_cache=$(awk "BEGIN {printf \"%.0fM\", $buff_cache}")

# Archivo para almacenar usuarios
USUARIOS_FILE="/root/usuarios_registrados.txt"

# PANEL
while true; do
    clear
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "          \e[1;33mPANEL 🤡OFICIAL MCCARTHEY🤓\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e " \e[1;35mFECHA       :\e[0m \e[1;93m$fecha\e[0m"
    echo -e " \e[1;35mIP VPS      :\e[0m \e[1;93m$ip\e[0m"
    echo -e " \e[1;35mCPU's       :\e[0m \e[1;93m$cpus\e[0m"
    echo -e " \e[1;35mMODELO CPU  :\e[0m \e[1;93m$cpu_model\e[0m"
    echo -e " \e[1;35mS.O         :\e[0m \e[1;93m$so\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e " \e[1;96m∘ TOTAL: $ram_total  ∘ LIBRE: $ram_libre  ∘ EN USO: $ram_usada\e[0m"
    echo -e " \e[1;96m∘ U/RAM: $ram_porc   ∘ U/CPU: $cpu_uso_fmt  ∘ BUFFER: $ram_cache\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e " \e[1;33m[1] ➮ CREAR NUEVO USUARIO SSH\e[0m "
    echo -e " \e[1;33m[2] ➮ ACTUALIZAR MCC-KEY\e[0m "
    echo -e " \e[1;33m[3] ➮ USUARIOS REGISTRADOS\e[0m "
    echo -e " \e[1;33m[4] ➮ ELIMINAR USUARIOS\e[0m "
    echo -e " \e[1;33m[5] ➮ SALIR\e[0m "
    echo -e " \e[1;33m[6] 💕 ➮ COLOCAR PUERTOS\e[0m "
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e -n "\e[1;33m► 🌞Elige una opción: \e[0m"
    read opc

    case $opc in
        1)
            read -p $'\e[1;95mNombre de usuario: \e[0m' USUARIO
            if id "$USUARIO" >/dev/null 2>&1; then
                echo ""
                echo -e "\e[1;31mEl usuario $USUARIO ya existe en el sistema.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi
            if grep -q "^$USUARIO:" "$USUARIOS_FILE" 2>/dev/null; then
                echo ""
                echo -e "\e[1;31mEl usuario $USUARIO ya está registrado en el archivo.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi
            read -p $'\e[1;95mContraseña: \e[0m' PASSWORD
            read -p $'\e[1;95mLímite de conexiones: \e[0m' LIMITE
            read -p $'\e[1;95mDías de validez: \e[0m' DIAS

            if [[ -z "$USUARIO" || -z "$PASSWORD" || -z "$LIMITE" || -z "$DIAS" ]]; then
                echo ""
                echo -e "\e[1;31mPor favor complete todos los datos.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi

            if ! [[ "$LIMITE" =~ ^[0-9]+$ ]] || [ "$LIMITE" -lt 1 ]; then
                echo ""
                echo -e "\e[1;31mEl límite de conexiones debe ser un número positivo.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi

            if ! [[ "$DIAS" =~ ^[0-9]+$ ]] || [ "$DIAS" -lt 1 ]; then
                echo ""
                echo -e "\e[1;31mLos días de validez deben ser un número positivo.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi

            FECHA_EXPIRACION=$(date -d "$DIAS days" +"%d/ de %B")
            useradd -e $(date -d "$DIAS days" +%Y-%m-%d) -s /bin/false -M "$USUARIO"
            echo "$USUARIO:$PASSWORD" | chpasswd

            echo "$USUARIO:$PASSWORD:$LIMITE:$FECHA_EXPIRACION:$DIAS" >> "$USUARIOS_FILE"

            echo ""
            echo -e "\e[1;96mUsuario creado con éxito:\e[0m"
            echo ""
            echo -e "\e[1;35m$(printf '%-12s %-14s %-10s %-15s %-5s' 'USUARIO' 'CONTRASEÑA' 'LIMITE' 'CADUCA' 'DIAS')\e[0m"
            printf "%-12s %-14s %-10s %-15s %-5s\n" "$USUARIO" "$PASSWORD" "$LIMITE" "$FECHA_EXPIRACION" "$DIAS"
            echo ""
            read -p "Presiona enter para continuar..."
            ;;
        2)
            validar_key
            ;;
        3)
            clear
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "          \e[1;33mUSUARIOS REGISTRADOS\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            if [[ -s "$USUARIOS_FILE" ]]; then
                echo -e "\e[1;35m$(printf '%-12s %-14s %-10s %-15s %-5s' 'USUARIO' 'CONTRASEÑA' 'LIMITE' 'CADUCA' 'DIAS')\e[0m"
                while IFS=: read -r usuario password limite caduca dias; do
                    if id "$usuario" >/dev/null 2>&1; then
                        printf "%-12s %-14s %-10s %-15s %-5s\n" "$usuario" "$password" "$limite" "$caduca" "$dias"
                    else
                        sed -i "/^$usuario:/d" "$USUARIOS_FILE"
                    fi
                done < "$USUARIOS_FILE"
                if [[ ! -s "$USUARIOS_FILE" ]]; then
                    echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
                fi
            else
                echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
            fi
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            read -p "Presiona enter para volver al panel principal..."
            ;;
        4)
            clear
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "          \e[1;33mELIMINAR USUARIOS\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            if [[ -s "$USUARIOS_FILE" ]]; then
                echo -e "\e[1;35m$(printf '%-12s %-14s %-10s %-15s %-5s' 'USUARIO' 'CONTRASEÑA' 'LIMITE' 'CADUCA' 'DIAS')\e[0m"
                while IFS=: read -r usuario password limite caduca dias; do
                    if id "$usuario" >/dev/null 2>&1; then
                        printf "%-12s %-14s %-10s %-15s %-5s\n" "$usuario" "$password" "$limite" "$caduca" "$dias"
                    else
                        sed -i "/^$usuario:/d" "$USUARIOS_FILE"
                    fi
                done < "$USUARIOS_FILE"
                if [[ ! -s "$USUARIOS_FILE" ]]; then
                    echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
                fi
            else
                echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
            fi
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "\e[1;33m[1] Eliminar un usuario específico\e[0m"
            echo -e "\e[1;33m[2] Eliminar todos los usuarios\e[0m"
            echo -e "\e[1;33m[3] Volver al panel principal\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e -n "\e[1;33m► Elige una opción: \e[0m"
            read del_opc

            case $del_opc in
                1)
                    read -p "Nombre del usuario a eliminar: " USUARIO_DEL
                    if [[ -z "$USUARIO_DEL" ]]; then
                        echo -e "\e[1;31mPor favor ingrese un nombre de usuario.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi

                    if ! id "$USUARIO_DEL" >/dev/null 2>&1; then
                        echo -e "\e[1;31mEl usuario $USUARIO_DEL no existe.\e[0m"
                        sed -i "/^$USUARIO_DEL:/d" "$USUARIOS_FILE" 2>/dev/null
                        read -p "Presiona enter para continuar..."
                        continue
                    fi

                    echo -e "\e[1;33m¿Estás seguro de eliminar al usuario $USUARIO_DEL? (s/n)\e[0m"
                    read -p "Confirma: " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        userdel -r "$USUARIO_DEL" 2>/dev/null
                        sed -i "/^$USUARIO_DEL:/d" "$USUARIOS_FILE"
                        echo -e "\e[1;96mUsuario $USUARIO_DEL eliminado con éxito.\e[0m"
                    else
                        echo -e "\e[1;31mEliminación cancelada.\e[0m"
                    fi
                    read -p "Presiona enter para continuar..."
                    ;;
                2)
                    echo -e "\e[1;33m¿Estás seguro de eliminar TODOS los usuarios? (s/n)\e[0m"
                    read -p "Confirma: " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        if [[ -s "$USUARIOS_FILE" ]]; then
                            while IFS=: read -r usuario _; do
                                userdel -r "$usuario" 2>/dev/null
                            done < "$USUARIOS_FILE"
                            > "$USUARIOS_FILE"
                            echo -e "\e[1;96mTodos los usuarios han sido eliminados.\e[0m"
                        else
                            echo -e "\e[1;31mNo hay usuarios para eliminar.\e[0m"
                        fi
                    else
                        echo -e "\e[1;31mEliminación cancelada.\e[0m"
                    fi
                    read -p "Presiona enter para continuar..."
                    ;;
                3)
                    continue
                    ;;
                *)
                    echo -e "\e[1;31mOpción no válida.\e[0m"
                    read -p "Presiona enter para continuar..."
                    ;;
            esac
            ;;
        5)
            echo -e "\e[1;33mSaliendo del panel...\e[0m"
            exit 0
            ;;
        6)
            clear
            echo -e "\e[1;36m╔══════════════════════════════════════════════╗\e[0m"
            echo -e "\e[1;33m     ⚡ CONFIGURACIÓN DE PUERTOS PRO ⚡     \e[0m"
            echo -e "\e[1;36m╚══════════════════════════════════════════════╝\e[0m"
            echo -e "\e[1;35m⚡Potencia tu VPS con estilo 🌐\e[0m"
            echo -e "\e[1;36m----------------------------------------------\e[0m"
            echo -e "\e[1;96m[1] ➮ Configurar Dropbear (Puerto 444)\e[0m"
            echo -e "\e[1;33m      Instala Dropbear para conexiones SSH seguras.\e[0m"
            echo -e "\e[1;96m[2] ➮ Iniciar Proxy WS/Directo\e[0m"
            echo -e "\e[1;33m      Configura el proxy para redirigir al puerto Dropbear.\e[0m"
            echo -e "\e[1;96m[3] ➮ Verificar Estado de Puertos\e[0m"
            echo -e "\e[1;33m      Revisa si Dropbear y el proxy están activos.\e[0m"
            echo -e "\e[1;96m[4] ➮ Detener Proxy WS/Directo\e[0m"
            echo -e "\e[1;33m      Para el proxy si está corriendo.\e[0m"
            echo -e "\e[1;96m[5] ➮ Editar Configuración de Puertos\e[0m"
            echo -e "\e[1;33m      Modifica los puertos de escucha del proxy.\e[0m"
            echo -e "\e[1;31m[0] ➮ Volver al Menú Principal\e[0m"
            echo -e "\e[1;36m----------------------------------------------\e[0m"
            echo -e -n "\e[1;35m🎯 Elige tu opción: \e[0m"
            read option

            case $option in
                1)
                    if ! dpkg -s dropbear &>/dev/null; then
                        echo -e "\n\e[1;34m🔧 Instalando Dropbear...\e[0m"
                        apt install dropbear -y
                        if dpkg -s dropbear &>/dev/null; then
                            echo -e "\e[1;96m[✓] Dropbear instalado correctamente.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] Error al instalar Dropbear.\e[0m"
                            read -p "Presiona enter para continuar..."
                            continue
                        fi
                    fi

                    echo -e "\n\e[1;34m🔧 Configurando Dropbear en puerto 444...\e[0m"
                    echo "/bin/false" >> /etc/shells
                    echo "/usr/sbin/nologin" >> /etc/shells
                    sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
                    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear
                    echo 'DROPBEAR_EXTRA_ARGS="-p 444"' >> /etc/default/dropbear

                    systemctl restart dropbear &>/dev/null || service dropbear restart &>/dev/null

                    if pgrep dropbear > /dev/null && ss -tuln | grep -q ":444 "; then
                        echo -e "\e[1;96m[✓] Dropbear activado en puerto 444.\e[0m"
                    else
                        echo -e "\e[1;31m[✗] Error: No se pudo iniciar Dropbear en el puerto 444.\e[0m"
                        journalctl -u dropbear -n 10 --no-pager
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                2)
                    if ! pgrep dropbear > /dev/null; then
                        echo -e "\n\e[1;31m[✗] Dropbear no está activo. Instálalo primero.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi

                    echo -e "\n\e[1;34m🔧 Configurando Proxy WS/Directo...\e[0m"
                    mkdir -p /etc/mccproxy

                    if [ ! -f /etc/mccproxy/proxy.py ]; then
                        echo -e "\e[1;31m[✗] Script proxy.py no encontrado. Por favor, configúralo primero.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi

                    if ! dpkg -s screen &>/dev/null; then
                        apt install screen -y
                        if dpkg -s screen &>/dev/null; then
                            echo -e "\e[1;96m[✓] Screen instalado correctamente.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] Error al instalar screen.\e[0m"
                            read -p "Presiona enter para continuar..."
                            continue
                        fi
                    fi

                    echo -e "\e[1;33m⚙️ Configura tu Proxy WS/Directo:\e[0m"
                    read -p "Puertos de escucha (Ej: 8080,443, separador coma o espacio): " proxy_ports

                    if [[ -z "$proxy_ports" ]]; then
                        echo -e "\e[1;31m[✗] Debes especificar al menos un puerto.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi

                    # Guardar configuración de puertos
                    echo "$proxy_ports" | tr ',' ' ' > /etc/mccproxy_ports

                    # Verificar si los puertos están disponibles
                    for port in $(echo "$proxy_ports" | tr ',' ' '); do
                        if ss -tuln | grep -q ":$port "; then
                            echo -e "\e[1;31m[✗] El puerto $port ya está en uso.\e[0m"
                            read -p "Presiona enter para continuar..."
                            continue 2
                        fi
                    done

                    echo -e "\n\e[1;34m🔧 Iniciando Proxy en puertos $proxy_ports\e[0m"
                    screen -dmS proxy python3 /etc/mccproxy/proxy.py
                    sleep 2

                    if screen -list | grep -q "proxy"; then
                        echo -e "\e[1;96m[✓] Proxy WS/Directo activo en puertos $proxy_ports\e[0m"
                    else
                        echo -e "\e[1;31m[✗] Error: No se pudo iniciar el Proxy.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                3)
                    echo -e "\n\e[1;34m🔍 Verificando estado de puertos...\e[0m"
                    echo -e "\e[1;36m----------------------------------------------\e[0m"
                    echo -e "\e[1;33m🌐 Estado de Dropbear (Puerto 444):\e[0m"
                    if pgrep dropbear > /dev/null && ss -tuln | grep -q ":444 "; then
                        echo -e "\e[1;96m[✓] Activo y escuchando en puerto 444.\e[0m"
                    else
                        echo -e "\e[1;31m[✗] No activo en puerto 444.\e[0m"
                    fi
                    echo -e "\e[1;33m🌐 Estado de Proxy WS/Directo:\e[0m"
                    proxy_ports=$(cat /etc/mccproxy_ports 2>/dev/null || echo "8080")
                    for port in $proxy_ports; do
                        if ss -tuln | grep -q ":$port "; then
                            echo -e "\e[1;96m[✓] Activo y escuchando en puerto $port.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] No activo en puerto $port.\e[0m"
                        fi
                    done
                    echo -e "\e[1;36m----------------------------------------------\e[0m"
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                4)
                    echo -e "\n\e[1;34m🔧 Deteniendo Proxy WS/Directo...\e[0m"
                    if screen -list | grep -q "proxy"; then
                        screen -X -S proxy quit &>/dev/null
                        echo -e "\e[1;96m[✓] Proxy detenido correctamente.\e[0m"
                    else
                        echo -e "\e[1;31m[✗] No hay proxy corriendo.\e[0m"
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                5)
                    echo -e "\n\e[1;34m🔧 Editando configuración de puertos...\e[0m"
                    echo -e "\e[1;33m⚙️ Puertos de escucha actuales: $(cat /etc/mccproxy_ports 2>/dev/null || echo '8080')\e[0m"
                    read -p "Nuevos puertos de escucha (Ej: 8080,443, separador coma o espacio): " new_proxy_ports

                    if [[ -n "$new_proxy_ports" ]]; then
                        echo "$new_proxy_ports" | tr ',' ' ' > /etc/mccproxy_ports
                        echo -e "\e[1;96m[✓] Puertos de escucha actualizados: $new_proxy_ports\e[0m"
                    fi

                    echo -e "\n\e[1;33m¿Deseas reiniciar el proxy con la nueva configuración? (s/n)\e[0m"
                    read -p "Confirma: " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        if screen -list | grep -q "proxy"; then
                            screen -X -S proxy quit &>/dev/null
                        fi
                        for port in $(cat /etc/mccproxy_ports); do
                            if ss -tuln | grep -q ":$port "; then
                                echo -e "\e[1;31m[✗] El puerto $port ya está en uso.\e[0m"
                                read -p "Presiona enter para continuar..."
                                continue 2
                            fi
                        done
                        screen -dmS proxy python3 /etc/mccproxy/proxy.py
                        sleep 2
                        if screen -list | grep -q "proxy"; then
                            echo -e "\e[1;96m[✓] Proxy reiniciado con nueva configuración.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] Error: No se pudo reiniciar el Proxy.\e[0m"
                        fi
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                0)
                    continue
                    ;;
                *)
                    echo -e "\e[1;31m[✗] Opción no válida.\e[0m"
                    read -p "Presiona enter para continuar..."
                    ;;
            esac
            ;;
        *)
            echo -e "\e[1;31mOpción no válida.\e[0m"
            sleep 2
            ;;
    esac
done
EOF

    chmod +x /root/menu.sh
    ln -sf /root/menu.sh /usr/bin/menu
    chmod +x /usr/bin/menu

    # Configurar inicio automático del panel al iniciar sesión
    echo -e "\n\033[1;36m[ CONFIG ]\033[0m Configurando inicio automático del panel..."
    if ! grep -q "/usr/bin/menu" /root/.bashrc; then
        echo "[ -f /usr/bin/menu ] && /usr/bin/menu" >> /root/.bashrc
        echo -e "\033[1;96m[ OK ] Inicio automático configurado.\033[0m"
    else
        echo -e "\033[1;33m[ INFO ] Inicio automático ya estaba configurado.\033[0m"
    fi

    echo -e "\n\033[1;36m[ PANEL ]\033[0m Panel McCarthey instalado y listo para usar."
    echo -e "Ejecuta \033[1;33mmenu\033[0m para acceder."
fi

# FINAL
echo -e "\n\033[1;36m==============================================\033[0m"
echo -e "\033[1;33m      ¡TU VPS ESTÁ LISTA PARA DESPEGAR!         \033[0m"
echo -e "\033[1;36m==============================================\033[0m"
echo -e "Puedes acceder al panel usando: \033[1;33mmenu\033[0m"
echo -e "¡Gracias por usar \033[1;35mMcCarthey Installer\033[0m!"   
