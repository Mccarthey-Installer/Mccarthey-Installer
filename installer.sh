#!/bin/bash

validar_key() {
    echo -e "\n\033[1;36m[ INFO ]\033[0m Descargando la última versión del instalador..."
    wget -q -O installer.sh https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/installer.sh
    if [ $? -ne 0 ]; then
        echo -e "\033[1;31m[ ERROR ] No se pudo descargar el script actualizado.\033[0m"
        read -p "Presiona enter para continuar..."
        return 1
    fi
    chmod +x installer.sh
    echo -e "\033[1;96m[ OK ] Script actualizado correctamente.\033[0m"
    
    echo -e "\n\033[1;36m[ INFO ] Ingresa tu nueva MCC-KEY:\033[0m"
    read -p "> " NEW_KEY
    
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

# Determinar saludo según la hora
hora=$(date +%H)
if [ "$hora" -ge 5 ] && [ "$hora" -lt 12 ]; then
    saludo="Buenos días 🌞"
elif [ "$hora" -ge 12 ] && [ "$hora" -lt 18 ]; then
    saludo="Buenas tardes"
else
    saludo="Buenas noches 🌙"
fi

# Archivo para almacenar usuarios
USUARIOS_FILE="/root/usuarios_registrados.txt"

# Contar usuarios registrados
if [[ -s "$USUARIOS_FILE" ]]; then
    usuarios_registrados=$(wc -l < "$USUARIOS_FILE")
else
    usuarios_registrados=0
fi

# Función para contar dispositivos conectados
contar_dispositivos() {
    total_conexiones=0
    while IFS=: read -r usuario _ limite _ _; do
        conexiones=$(pgrep -u "$usuario" | wc -l)
        ((total_conexiones += conexiones))
    done < "$USUARIOS_FILE"
    echo "$total_conexiones"
}

# Contar dispositivos conectados totales
dispositivos_on=$(contar_dispositivos)

# Archivo para log de conexiones múltiples
MULTI_LOG="/root/multi_onlines.log"

# Función para verificar y bloquear/desbloquear usuarios según límite
verificar_limites() {
    > "$MULTI_LOG"
    while IFS=: read -r usuario _ limite _ _; do
        conexiones=$(pgrep -u "$usuario" | wc -l)
        if [ "$conexiones" -gt "$limite" ]; then
            pkill -u "$usuario"
            echo "$(date): Usuario $usuario bloqueado por exceder límite ($conexiones/$limite)" >> "$MULTI_LOG"
        elif [ "$conexiones" -gt 0 ] && ! id -u "$usuario" >/dev/null 2>&1; then
            useradd -M -s /bin/false "$usuario"
            echo "$(date): Usuario $usuario desbloqueado (conexiones: $conexiones/$limite)" >> "$MULTI_LOG"
        fi
    done < "$USUARIOS_FILE"
}

# Ejecutar verificación de límites
verificar_limites

# PANEL
while true; do
    clear
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "          \e[1;33mPANEL 💗OFICIAL MCCARTHEY💕\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e " \e[1;35m$saludo\e[0m"
    echo -e " \e[1;35mFECHA       :\e[0m \e[1;93m$fecha\e[0m"
    echo -e " \e[1;35mIP VPS      :\e[0m \e[1;93m$ip\e[0m"
    echo -e " \e[1;35mDISPOSITIVOS ON:\e[0m \e[1;31m$dispositivos_on onlines\e[0m"
    echo -e " \e[1;35mUsuarios registrados:\e[0m \e[1;93m$usuarios_registrados\e[0m"
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
    echo -e " \e[1;33m[7] 💕 ➮ VER DISPOSITIVOS ONLINE\e[0m "
    echo -e " \e[1;33m[8] 💕 ➮ VER MULTI ONLINES\e[0m "
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

                    echo "$proxy_ports" | tr ',' ' ' > /etc/mccproxy_ports

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
        7)
            clear
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "          \e[1;33mDISPOSITIVOS ONLINE\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            if [[ -s "$USUARIOS_FILE" ]]; then
                echo -e "\e[1;35m$(printf '%-12s %-14s %-15s' 'USUARIO' 'CONEXIONES' 'TIEMPO HH:MM:SS')\e[0m"
                online_found=false
                while IFS=: read -r usuario _ limite _ _; do
                    conexiones=$(pgrep -u "$usuario" | wc -l)
                    if [ "$conexiones" -gt 0 ]; then
                        online_found=true
                        # Obtener tiempo de la primera conexión activa
                        pid=$(pgrep -u "$usuario" | head -n 1)
                        if [ -n "$pid" ]; then
                            start_time=$(ps -p "$pid" -o etime= | tr -d ' ')
                            if [[ "$start_time" =~ ([0-9]+)-([0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                                days=${BASH_REMATCH[1]}
                                time=${BASH_REMATCH[2]}
                                tiempo="$days-$time"
                            else
                                tiempo="$start_time"
                            fi
                        else
                            tiempo="00:00:00"
                        fi
                        printf "[%-10s] [%-12s] %-15s\n" "$usuario" "$conexiones/$limite" "$tiempo"
                    fi
                done < "$USUARIOS_FILE"
                if ! $online_found; then
                    echo -e "\e[1;31mNo hay usuarios conectados.\e[0m"
                fi
            else
                echo -e "\e[1;31mNo hay usuarios registrados.\e[0m"
            fi
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            read -p "Presiona enter para volver al panel principal..."
            ;;
        8)
            clear
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "          \e[1;33mREGISTRO DE MULTI ONLINES\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            if [[ -s "$MULTI_LOG" ]]; then
                cat "$MULTI_LOG"
            else
                echo -e "\e[1;31mNo hay registros de conexiones múltiples.\e[0m"
            fi
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            read -p "Presiona enter para volver al panel principal..."
            ;;
        *)
            echo -e "\e[1;31mOpción no válida.\e[0m"
            sleep 2
            ;;
    esac
done
