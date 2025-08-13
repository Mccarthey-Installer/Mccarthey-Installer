#!/bin/bash

# ================================
# VARIABLES Y RUTAS
# ================================
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon.pid"

# Crear directorios si no existen
mkdir -p "$(dirname "$REGISTROS")"
mkdir -p "$(dirname "$HISTORIAL")"
mkdir -p "$(dirname "$PIDFILE")"

# ================================
#  FUNCIÓN: MONITOREAR CONEXIONES
# ================================
monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=1

    while true; do
        # Usuarios conectados ahora mismo por SSH o Dropbear
        usuarios_ps=$(ps -o user= -C sshd -C dropbear | sort -u)

        for usuario in $usuarios_ps; do
            [[ -z "$usuario" ]] && continue
            tmp_status="/tmp/status_${usuario}.tmp"

            # ¿Cuántas conexiones tiene activas?
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

            if [[ $conexiones -gt 0 ]]; then
                # Si nunca se ha creado el reloj, créalo ahora
                if [[ ! -f "$tmp_status" ]]; then
                    date +%s > "$tmp_status"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado." >> "$LOG"
                else
                    # Reparar si está corrupto
                    contenido=$(cat "$tmp_status")
                    [[ ! "$contenido" =~ ^[0-9]+$ ]] && date +%s > "$tmp_status"
                fi
            fi
        done

        # Ahora, ver quién estaba conectado y ya NO está, para cerrarles el tiempo
        for f in /tmp/status_*.tmp; do
            [[ ! -f "$f" ]] && continue
            usuario=$(basename "$f" .tmp | cut -d_ -f2)
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))
            if [[ $conexiones -eq 0 ]]; then
                hora_ini=$(date -d @"$(cat "$f")" "+%Y-%m-%d %H:%M:%S")
                hora_fin=$(date "+%Y-%m-%d %H:%M:%S")
                rm -f "$f"
                echo "$usuario|$hora_ini|$hora_fin" >> "$HISTORIAL"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desconectado. Inicio: $hora_ini Fin: $hora_fin" >> "$LOG"
            fi
        done

        sleep "$INTERVALO"
    done
}



# ================================
#  MODO MONITOREO DIRECTO
# ================================
if [[ "$1" == "mon" ]]; then
    monitorear_conexiones
    exit 0
fi

# ================================
#  ARRANQUE AUTOMÁTICO DEL MONITOR
# ================================
if [[ ! -f "$PIDFILE" ]] || ! ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PIDFILE"
    nohup bash "$0" mon >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
fi

# ================================

verificar_online() {
    clear
    echo "===== ✅   USUARIOS ONLINE ====="
    printf "%-14s %-14s %-10s %-25s\n" "👤 USUARIO" "✅ CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo "-----------------------------------------------------------------"

    total_online=0
    total_usuarios=0
    inactivos=0

    if [[ ! -f "$REGISTROS" ]]; then
        echo "❌ No hay registros."
        read -p "Presiona Enter para continuar..."
        return
    fi

    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}
        (( total_usuarios++ ))

        conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

        estado="☑️ 0"
        detalle="😴 Nunca conectado"
        mov_txt="📲 $moviles"
        tmp_status="/tmp/status_${usuario}.tmp"

        if [[ $conexiones -gt 0 ]]; then
            # Usuario actualmente online
            estado="✅ $conexiones"
            (( total_online += conexiones ))

            if [[ -f "$tmp_status" ]]; then
                contenido=$(cat "$tmp_status")
                if [[ "$contenido" =~ ^[0-9]+$ ]]; then
                    # Epoch válido
                    start_s=$((10#$contenido))
                else
                    # Reparar si estaba en formato viejo
                    start_s=$(date +%s)
                    echo $start_s > "$tmp_status"
                fi

                now_s=$(date +%s)
                elapsed=$(( now_s - start_s ))

                h=$(( elapsed / 3600 ))
                m=$(( (elapsed % 3600) / 60 ))
                s=$(( elapsed % 60 ))
                detalle=$(printf "⏰ %02d:%02d:%02d" "$h" "$m" "$s")
            fi
        else
            # Usuario desconectado ahora
            rm -f "$tmp_status"
            ult=$(grep "^$usuario|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}')
            if [[ -n "$ult" ]]; then
                ult_fmt=$(date -d "$ult" +"%d de %B %I:%M %p")
                detalle="📅 Última: $ult_fmt"
            else
                detalle="😴 Nunca conectado"
            fi
            (( inactivos++ )) # 📌 Siempre cuenta como inactivo si no está conectado
        fi

        printf "%-14s %-14s %-10s %-25s\n" "$usuario" "$estado" "$mov_txt" "$detalle"
    done < "$REGISTROS"

    echo "-----------------------------------------------------------------"
    echo "Total de Online: $total_online  Total usuarios: $total_usuarios  Inactivos: $inactivos"
    echo "================================================"
    read -p "Presiona Enter para continuar..."
}

# ================================
#  FUNCIÓN: BLOQUEAR/DESBLOQUEAR USUARIO
# ================================
bloquear_desbloquear_usuario() {
    clear
    echo "==== 🔒 BLOQUEAR/DESBLOQUEAR USUARIO ===="
    echo "===== 📋 USUARIOS REGISTRADOS ====="
    printf "%-4s %-14s %-14s %-20s %-15s\n" "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "✅ Estado"
    echo "--------------------------------------------------------------------------"

    # Archivo para almacenar bloqueos temporales
    BLOQUEOS="/tmp/bloqueos_usuarios.txt"
    touch "$BLOQUEOS"

    # Leer usuarios desde REGISTROS
    if [[ ! -f "$REGISTROS" ]]; then
        echo "❌ No hay registros de usuarios."
        read -p "Presiona Enter para continuar... ✨"
        return
    fi

    # Mostrar lista de usuarios
    declare -A user_map
    contador=0
    while IFS=':' read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}
        clave=${userpass#*:}
        (( contador++ ))

        # Verificar estado de bloqueo
        estado="desbloqueado"
        if grep -q "^$usuario:" "$BLOQUEOS"; then
            bloqueo_info=$(grep "^$usuario:" "$BLOQUEOS")
            tiempo_bloqueo=${bloqueo_info#*:}
            if [[ $tiempo_bloqueo =~ ^[0-9]+$ ]]; then
                now_s=$(date +%s)
                if [[ $now_s -lt $tiempo_bloqueo ]]; then
                    estado="bloqueado"
                else
                    # Eliminar bloqueo si ya expiró
                    sed -i "/^$usuario:/d" "$BLOQUEOS"
                    estado="desbloqueado"
                    passwd -u "$usuario" >/dev/null 2>&1
                fi
            else
                estado="bloqueado"
            fi
        fi

        # Formatear fecha de expiración
        fecha_exp_fmt=$(date -d "$fecha_exp" +"%d/%B/%Y" 2>/dev/null || echo "$fecha_exp")
        printf "%-4s %-14s %-14s %-20s %-15s\n" "$contador" "$usuario" "$clave" "$fecha_exp_fmt" "$estado"
        user_map[$contador]="$usuario"
    done < "$REGISTROS"

    echo "=========================================================================="
    read -p "👤 Digite el número o el nombre del usuario: " input

    # Validar entrada
    if [[ -z "$input" ]]; then
        echo "❌ Entrada inválida."
        read -p "Presiona Enter para continuar... ✨"
        return
    fi

    # Determinar usuario seleccionado
    if [[ "$input" =~ ^[0-9]+$ && -n "${user_map[$input]}" ]]; then
        usuario="${user_map[$input]}"
    else
        usuario="$input"
        grep -q "^$usuario:" "$REGISTROS" || {
            echo "❌ Usuario no encontrado."
            read -p "Presiona Enter para continuar... ✨"
            return
        }
    fi

    # Verificar estado actual
    estado="desbloqueado"
    if grep -q "^$usuario:" "$BLOQUEOS"; then
        bloqueo_info=$(grep "^$usuario:" "$BLOQUEOS")
        tiempo_bloqueo=${bloqueo_info#*:}
        if [[ $tiempo_bloqueo =~ ^[0-9]+$ ]]; then
            now_s=$(date +%s)
            if [[ $now_s -lt $tiempo_bloqueo ]]; then
                estado="bloqueado"
            else
                sed -i "/^$usuario:/d" "$BLOQUEOS"
                passwd -u "$usuario" >/dev/null 2>&1
                estado="desbloqueado"
            fi
        else
            estado="bloqueado"
        fi
    fi

    echo "𒯢 El usuario '$usuario' está ${estado^^}."

    if [[ "$estado" == "desbloqueado" ]]; then
        read -p "✅ Desea bloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            read -p "Digite el tiempo en minutos para desbloquear al usuario (0 para bloqueo permanente) y confirme con Enter: " minutos
            if [[ ! "$minutos" =~ ^[0-9]+$ ]]; then
                echo "❌ Tiempo inválido. Debe ser un número."
                read -p "Presiona Enter para continuar... ✨"
                return
            fi

            # Bloquear usuario
            passwd -l "$usuario" >/dev/null 2>&1
            # Terminar sesiones activas
            pkill -u "$usuario" >/dev/null 2>&1

            # Registrar bloqueo
            if [[ $minutos -gt 0 ]]; then
                tiempo_desbloqueo=$(( $(date +%s) + minutos * 60 ))
                sed -i "/^$usuario:/d" "$BLOQUEOS"  # Eliminar bloqueo anterior
                echo "$usuario:$tiempo_desbloqueo" >> "$BLOQUEOS"
            else
                sed -i "/^$usuario:/d" "$BLOQUEOS"  # Eliminar bloqueo anterior
                echo "$usuario:permanente" >> "$BLOQUEOS"
            fi

            echo "🔒 Usuario '$usuario' bloqueado exitosamente y sesiones SSH terminadas. ✅"
        fi
    else
        read -p "✅ Desea desbloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            # Desbloquear usuario
            passwd -u "$usuario" >/dev/null 2>&1
            sed -i "/^$usuario:/d" "$BLOQUEOS"
            echo "🔓 Usuario '$usuario' desbloqueado exitosamente. ✅"
        fi
    fi

    read -p "Presiona Enter para continuar... ✨"
}

# Colores y emojis
VIOLETA='\033[38;5;141m'
VERDE='\033[38;5;42m'
AMARILLO='\033[38;5;220m'
AZUL='\033[38;5;39m'
ROJO='\033[1;31m'
CIAN='\033[38;5;51m'
FUCHSIA='\033[38;2;255;0;255m'
AMARILLO_SUAVE='\033[38;2;255;204;0m'
ROSA='\033[38;2;255;105;180m'
ROSA_CLARO='\033[1;95m'
NC='\033[0m'

# Menú principal
if [[ -t 0 ]]; then
    while true; do
        clear
        barra_sistema
        echo
        echo -e "${VIOLETA}====== 😇 PANEL DE USUARIOS VPN/SSH ======${NC}"
        echo -e "${AMARILLO_SUAVE}1. 🆕 Crear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}2. 📋 Ver registros${NC}"
        echo -e "${AMARILLO_SUAVE}3. 🗑️ Eliminar usuario${NC}"
        echo -e "${AMARILLO_SUAVE}4. 📊 Información${NC}"
        echo -e "${AMARILLO_SUAVE}5. 🟢 Verificar usuarios online${NC}"
        echo -e "${AMARILLO_SUAVE}6. 🔒 Bloquear/Desbloquear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}7. 🆕 Crear múltiples usuarios${NC}"
        echo -e "${AMARILLO_SUAVE}8. 📋 Mini registro${NC}"
        echo -e "${AMARILLO_SUAVE}9. 💣 Eliminar completamente usuario(s) (modo nuclear)${NC}"
        echo -e "${AMARILLO_SUAVE}10. 🎨 Configurar banner SSH${NC}"
        echo -e "${AMARILLO_SUAVE}0. 🚪 Salir${NC}"
        PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")
        read -p "$PROMPT" OPCION
        case $OPCION in
            1) crear_registro ;;
            2) ver_registros ;;
            3) nuclear_eliminar ;;
            4) informacion_usuarios ;;
            5) verificar_online ;;
            6) bloquear_desbloquear_usuario ;;
            7) crear_multiples_usuarios ;;
            8) mini_registro ;;
            9) eliminar_usuario ;;
            10) configurar_banner_ssh ;;
            0) exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi
