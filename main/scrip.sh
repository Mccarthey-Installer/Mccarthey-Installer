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

# Función para calcular la fecha de expiración
calcular_expiracion() {
    local dias=$1
    local fecha_expiracion=$(date -d "+$dias days" "+%d/%B/%Y")
    echo $fecha_expiracion
}
calcular_dias_restantes() {
    local fecha_expiracion="$1"

    local dia=$(echo "$fecha_expiracion" | cut -d'/' -f1)
    local mes=$(echo "$fecha_expiracion" | cut -d'/' -f2)
    local anio=$(echo "$fecha_expiracion" | cut -d'/' -f3)

    # Convertir mes español a número
    case $mes in
        "enero") mes_num="01" ;;
        "febrero") mes_num="02" ;;
        "marzo") mes_num="03" ;;
        "abril") mes_num="04" ;;
        "mayo") mes_num="05" ;;
        "junio") mes_num="06" ;;
        "julio") mes_num="07" ;;
        "agosto") mes_num="08" ;;
        "septiembre") mes_num="09" ;;
        "octubre") mes_num="10" ;;
        "noviembre") mes_num="11" ;;
        "diciembre") mes_num="12" ;;
        *) echo 0; return ;;
    esac

    local fecha_formateada="$anio-$mes_num-$dia"
    local fecha_actual=$(date "+%Y-%m-%d")

    local fecha_exp_epoch=$(date -d "$fecha_formateada" "+%s" 2>/dev/null)
    local fecha_act_epoch=$(date -d "$fecha_actual" "+%s")

    if [[ -z "$fecha_exp_epoch" ]]; then
        echo 0
        return
    fi

    local diff_segundos=$((fecha_exp_epoch - fecha_act_epoch))
    local dias_restantes=$((diff_segundos / 86400))

    if [ $dias_restantes -lt 0 ]; then
        dias_restantes=0
    fi

    echo $dias_restantes
}
# Función para crear usuario
crear_usuario() {
    clear
    echo "===== 🤪 CREAR USUARIO SSH ====="
    read -p "👤 Nombre del usuario: " usuario
    read -p "🔑 Contraseña: " clave
    read -p "📅 Días de validez: " dias
    read -p "📱 ¿Cuántos móviles? " moviles

    # Validar entradas
    if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
        echo "❌ Todos los campos son obligatorios."
        read -p "Presiona Enter para continuar..."
        return
    fi

    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo "❌ Días y móviles deben ser números."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Verificar si el usuario ya existe en el sistema
    if id "$usuario" >/dev/null 2>&1; then
        echo "❌ El usuario $usuario ya existe en el sistema."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuario en el sistema Linux
    if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
        echo "❌ Error al crear el usuario en el sistema."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Establecer la contraseña
    if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
        echo "❌ Error al establecer la contraseña."
        userdel "$usuario" 2>/dev/null
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Configurar fecha de expiración en el sistema (a las 00:00 del día siguiente al último día)
    fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
    if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
        echo "❌ Error al establecer la fecha de expiración."
        userdel "$usuario" 2>/dev/null
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Obtener fecha actual y de expiración para registros
    fecha_creacion=$(date "+%Y-%m-%d %H:%M:%S")
    fecha_expiracion=$(calcular_expiracion $dias)

    # Guardar en archivo de registros
    echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> $REGISTROS

    # Guardar en historial
    echo "Usuario creado: $usuario, Expira: $fecha_expiracion, Móviles: $moviles, Creado: $fecha_creacion" >> $HISTORIAL

    # Mostrar confirmación
    echo "✅ Usuario creado correctamente:"
    echo "👤 Usuario: $usuario"
    echo "🔑 Clave: $clave"
    echo "📅 Expira: $fecha_expiracion"
    echo "📱 Límite móviles: $moviles"
    echo "📅 Creado: $fecha_creacion"
    echo "===== 📝 RESUMEN DE REGISTRO ====="
    echo "👤 Usuario    📅 Expira          ⏳ Días       📱 Móviles   📅 Creado"
    echo "---------------------------------------------------------------"
    printf "%-12s %-18s %-12s %-12s %s\n" "$usuario:$clave" "$fecha_expiracion" "$dias días" "$moviles" "$fecha_creacion"
    echo "=============================================================="
    read -p "Presiona Enter para continuar..."
}

# Función para ver registros
# Función para ver registros
ver_registros() {
    clear
    echo "===== 🌸 REGISTROS ====="
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira    ⏳  Días   📲 Móviles"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
    else
        count=1
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            fecha_creacion="$fecha_creacion1 $fecha_creacion2"
            # Usar la fecha de expiración directamente, ya está en formato dd/mes/YYYY
            printf "%-2s %-11s %-10s %-16s %-8s %-8s\n" "$count" "$usuario" "$clave" "$fecha_expiracion" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
    fi
    read -p "Presiona Enter para continuar..."
}
# Función para mostrar un mini registro
mini_registro() {
    clear
    echo "==== 📋 MINI REGISTRO ====="
    echo "👤 Nombre  🔑 Contraseña   ⏳ Días   📱 Móviles"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
    else
        count=0
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            printf "%-12s %-16s %-10s %-10s\n" "$usuario" "$clave" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
        echo "==========================================="
        echo "TOTAL: $count usuarios"
    fi
    echo "Presiona Enter para continuar... ✨"
    read
}

# Función para crear múltiples usuarios
crear_multiples_usuarios() {
    clear
    echo "===== 🆕 CREAR MÚLTIPLES USUARIOS SSH ====="
    echo "📝 Formato: nombre contraseña días móviles (separados por espacios, una línea por usuario)"
    echo "📋 Ejemplo: lucy 123 5 4"
    echo "✅ Presiona Enter dos veces para confirmar."

    # Array para almacenar las entradas de usuarios
    declare -a usuarios_input
    while true; do
        read -r linea
        # Si la línea está vacía y la anterior también, salir del bucle
        if [[ -z "$linea" ]]; then
            read -r linea_siguiente
            if [[ -z "$linea_siguiente" ]]; then
                break
            else
                usuarios_input+=("$linea" "$linea_siguiente")
                continue
            fi
        fi
        usuarios_input+=("$linea")
    done

    # Verificar si se ingresaron usuarios
    if [ ${#usuarios_input[@]} -eq 0 ]; then
        echo "❌ No se ingresaron usuarios."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Procesar y validar entradas
    declare -a usuarios_validos
    declare -a errores
    for linea in "${usuarios_input[@]}"; do
        # Separar los campos
        read -r usuario clave dias moviles <<< "$linea"

        # Validar que todos los campos estén presentes
        if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
            errores+=("Línea '$linea': Todos los campos son obligatorios.")
            continue
        fi

        # Validar que días y móviles sean números
        if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
            errores+=("Línea '$linea': Días y móviles deben ser números.")
            continue
        fi

        # Verificar si el usuario ya existe en el sistema
        if id "$usuario" >/dev/null 2>&1; then
            errores+=("Línea '$linea': El usuario $usuario ya existe en el sistema.")
            continue
        fi

        # Almacenar usuario válido
        usuarios_validos+=("$usuario:$clave:$dias:$moviles")
    done

    # Mostrar errores si los hay
    if [ ${#errores[@]} -gt 0 ]; then
        echo "❌ Errores encontrados:"
        for error in "${errores[@]}"; do
            echo "$error"
        done
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Mostrar resumen de usuarios a crear
    echo "===== 📋 USUARIOS A CREAR ====="
    echo "👤 Usuario    🔑 Clave      ⏳ Días       📱 Móviles"
    echo "---------------------------------------------------------------"
    for usuario_data in "${usuarios_validos[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$usuario_data"
        printf "%-12s %-12s %-12s %-12s\n" "$usuario" "$clave" "$dias" "$moviles"
    done
    echo "==============================================================="

    # Confirmar creación
    read -p "✅ ¿Confirmar creación de estos usuarios? (s/n): " confirmacion
    if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
        echo "❌ Creación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuarios y registrar
    count=0
    for usuario_data in "${usuarios_validos[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$usuario_data"

        # Crear usuario en el sistema Linux
        if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
            echo "❌ Error al crear el usuario $usuario en el sistema."
            continue
        fi

        # Establecer la contraseña
        if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
            echo "❌ Error al establecer la contraseña para $usuario."
            userdel "$usuario" 2>/dev/null
            continue
        fi

        # Configurar fecha de expiración en el sistema
        fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
        if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
            echo "❌ Error al establecer la fecha de expiración para $usuario."
            userdel "$usuario" 2>/dev/null
            continue
        fi

        # Obtener fecha actual y de expiración para registros
        fecha_creacion=$(date "+%Y-%m-%d %H:%M:%S")
        fecha_expiracion=$(calcular_expiracion $dias)

        # Guardar en archivo de registros
        echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> $REGISTROS

        # Guardar en historial
        echo "Usuario creado: $usuario, Expira: $fecha_expiracion, Móviles: $moviles, Creado: $fecha_creacion" >> $HISTORIAL

        ((count++))
    done

    # Mostrar resumen de creación
    echo "===== 📊 RESUMEN DE CREACIÓN ====="
    echo "✅ Usuarios creados exitosamente: $count"
    echo "Presiona Enter para continuar... ✨"
    read
}


# Función para eliminar múltiples usuarios
eliminar_multiples_usuarios() {
    clear
    echo "===== 💣 ELIMINAR USUARIO: NIVEL DIABLO - SATÁN ROOT 🔥 ====="
    echo "Nº      👤 Usuario"
    echo "--------------------------"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Cargar usuarios en un array para fácil acceso por número
    declare -a usuarios
    count=1
    while IFS=' ' read -r user_data _; do
        usuario=${user_data%%:*}
        usuarios[$count]="$usuario"
        printf "%-7s %-20s\n" "$count" "$usuario"
        ((count++))
    done < $REGISTROS

    read -p "🗑️ Ingrese los números o nombres de usuarios a eliminar (separados por espacios) (0 para cancelar): " input

    if [[ "$input" == "0" ]]; then
        echo "❌ Eliminación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Procesar input: puede ser números o nombres
    declare -a usuarios_a_eliminar
    for item in $input; do
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Es un número
            if [[ $item -ge 1 && $item -lt $count ]]; then
                usuarios_a_eliminar+=("${usuarios[$item]}")
            else
                echo "❌ Número inválido: $item"
            fi
        else
            # Es un nombre, verificar si existe
            if grep -q "^$item:" $REGISTROS; then
                usuarios_a_eliminar+=("$item")
            else
                echo "❌ Usuario no encontrado: $item"
            fi
        fi
    done

    # Eliminar duplicados si los hay
    usuarios_a_eliminar=($(echo "${usuarios_a_eliminar[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#usuarios_a_eliminar[@]} -eq 0 ]; then
        echo "❌ No se seleccionaron usuarios válidos."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Confirmar eliminación
    echo "===== 📋 USUARIOS A ELIMINAR ====="
    for usuario in "${usuarios_a_eliminar[@]}"; do
        echo "👤 $usuario"
    done
    read -p "✅ ¿Confirmar eliminación? (s/n): " confirmacion
    if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
        echo "❌ Eliminación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Eliminar usuarios
    count=0
    fecha_eliminacion=$(date "+%Y-%m-%d %H:%M:%S")
    for usuario in "${usuarios_a_eliminar[@]}"; do
        # Terminar sesiones activas si existen (usando loginctl si está disponible)
        if command -v loginctl >/dev/null 2>&1; then
            loginctl terminate-user "$usuario" 2>/dev/null
        else
            # Alternativa: matar procesos del usuario
            pkill -9 -u "$usuario" 2>/dev/null
        fi

        # Eliminar usuario del sistema
        if userdel "$usuario" 2>/dev/null; then
            # Eliminar del registro
            sed -i "/^$usuario:/d" $REGISTROS

            # Registrar en historial
            echo "Usuario eliminado: $usuario, Fecha: $fecha_eliminacion" >> $HISTORIAL

            ((count++))
        else
            echo "❌ Error al eliminar el usuario $usuario del sistema."
        fi
    done

    # Mostrar resumen
    echo "===== 📊 RESUMEN DE ELIMINACIÓN ====="
    echo "✅ Usuarios eliminados exitosamente: $count"
    echo "Presiona Enter para continuar... ✨"
    read
}


monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=0.3  # Verificación rápida

    while true; do
        # Usuarios con sesiones activas (usando loginctl, filtrados por reg.txt)
        usuarios_ps=$(loginctl list-sessions --no-legend | awk '{print $3}' | sort -u | while read -r user; do
            if grep -q "^$user:" "$REGISTROS" 2>/dev/null; then
                echo "$user"
            fi
        done)

        # --- LIMITE DE CONEXIONES POR USUARIO ---
        for usuario in $usuarios_ps; do
            [[ -z "$usuario" ]] && continue

            # Límite permitido (campo 4 en REGISTROS)
            MOVILES_NUM=$(awk -F: -v u="$usuario" '$1==u{print $4}' "$REGISTROS" 2>/dev/null)
            [[ -z "$MOVILES_NUM" || ! "$MOVILES_NUM" =~ ^[0-9]+$ ]] && MOVILES_NUM=1
            (( MOVILES_NUM < 1 )) && MOVILES_NUM=1

            # Conexiones actuales (usando loginctl y ps para validar)
            conexiones=$(loginctl list-sessions --no-legend | awk -v user="$usuario" '$3==user{print $1}' | wc -l)
            conexiones_ps=$(ps -u "$usuario" -o comm= | grep -E "^sshd$" | wc -l)
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Verificando $usuario: $conexiones sesiones (loginctl), $conexiones_ps procesos (ps), límite: $MOVILES_NUM" >> "$LOG"

            if [[ $conexiones -gt $MOVILES_NUM || $conexiones_ps -gt $MOVILES_NUM ]]; then
                # Obtener todas las sesiones del usuario (ordenadas por ID, las más recientes tienen IDs mayores)
                mapfile -t SESSIONS < <(loginctl list-sessions --no-legend | awk -v user="$usuario" '$3==user{print $1}' | sort -n)
                # Obtener PIDs de sshd ordenados por tiempo de ejecución (más reciente primero)
                mapfile -t PIDS < <(ps -u "$usuario" -o pid=,comm=,etimes= --no-headers | grep -E "sshd" | awk '{print $1, $3}' | sort -k2 -n | awk '{print $1}')
                # Cerrar sesiones extras (manteniendo las MOVILES_NUM más antiguas)
                for ((i=MOVILES_NUM; i<${#SESSIONS[@]}; i++)); do
                    SESSION="${SESSIONS[i]}"
                    # Cerrar la sesión con loginctl
                    if [[ -n "$SESSION" ]]; then
                        if loginctl terminate-session "$SESSION" 2>/dev/null; then
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Sesión nueva de '$usuario' (SESSION $SESSION) cerrada con loginctl por exceder límite de $MOVILES_NUM." >> "$LOG"
                        else
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: Fallo al cerrar sesión de '$usuario' (SESSION $SESSION) con loginctl." >> "$LOG"
                        fi
                    fi
                done
                # Cerrar procesos sshd extras si persisten
                for ((i=MOVILES_NUM; i<${#PIDS[@]}; i++)); do
                    PID="${PIDS[i]}"
                    if [[ -n "$PID" ]]; then
                        if kill -9 "$PID" 2>/dev/null; then
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Sesión nueva de '$usuario' (PID $PID) cerrada con kill -9 por exceder límite de $MOVILES_NUM." >> "$LOG"
                        else
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: Fallo al cerrar sesión de '$usuario' (PID $PID) con kill -9." >> "$LOG"
                        fi
                    fi
                done
                # Verificar si la conexión se cerró
                sleep 0.2
                conexiones=$(loginctl list-sessions --no-legend | awk -v user="$usuario" '$3==user{print $1}' | wc -l)
                conexiones_ps=$(ps -u "$usuario" -o comm= | grep -E "^sshd$" | wc -l)
                if [[ $conexiones -gt $MOVILES_NUM || $conexiones_ps -gt $MOVILES_NUM ]]; then
                    # Reintentar con killall para procesos residuales
                    killall -u "$usuario" -9 -r "sshd" 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Sesión persistente de '$usuario' cerrada con killall por exceder límite de $MOVILES_NUM." >> "$LOG"
                fi
                # Verificación final
                conexiones=$(loginctl list-sessions --no-legend | awk -v user="$usuario" '$3==user{print $1}' | wc -l)
                conexiones_ps=$(ps -u "$usuario" -o comm= | grep -E "^sshd$" | wc -l)
                if [[ $conexiones -gt $MOVILES_NUM || $conexiones_ps -gt $MOVILES_NUM ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: No se pudo cerrar sesión extra de '$usuario'. Sesiones: $conexiones (loginctl), $conexiones_ps (ps), límite: $MOVILES_NUM." >> "$LOG"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Éxito: Conexión extra de '$usuario' cerrada. Sesiones: $conexiones (loginctl), $conexiones_ps (ps)." >> "$LOG"
                fi
            fi
        done

        # --- MARCA DE TIEMPO DE CONEXIÓN (entrada/salida) ---
        for usuario in $usuarios_ps; do
            [[ -z "$usuario" ]] && continue
            tmp_status="/tmp/status_${usuario}.tmp"
            conexiones=$(loginctl list-sessions --no-legend | awk -v user="$usuario" '$3==user{print $1}' | wc -l)
            if [[ $conexiones -gt 0 ]]; then
                if [[ ! -f "$tmp_status" ]]; then
                    date +%s > "$tmp_status"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado." >> "$LOG"
                else
                    contenido=$(cat "$tmp_status" 2>/dev/null)
                    [[ ! "$contenido" =~ ^[0-9]+$ ]] && date +%s > "$tmp_status"
                fi
            fi
        done

        for f in /tmp/status_*.tmp; do
            [[ ! -f "$f" ]] && continue
            usuario="${f#/tmp/status_}"; usuario="${usuario%.tmp}"
            conexiones=$(loginctl list-sessions --no-legend | awk -v user="$usuario" '$3==user{print $1}' | wc -l)
            if [[ $conexiones -eq 0 ]]; then
                hora_ini=$(date -d @"$(cat "$f" 2>/dev/null)" "+%Y-%m-%d %H:%M:%S")
                hora_fin=$(date "+%Y-%m-%d %H:%M:%S")
                rm -f "$f"
                [[ -n "$HISTORIAL" ]] && echo "$usuario|$hora_ini|$hora_fin" >> "$HISTORIAL"
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

        # 🔍 Verificar si el usuario existe, si no, saltar al siguiente
        if ! id "$usuario" &>/dev/null; then
            continue
        fi

        (( total_usuarios++ ))

        conexiones=$(( $(ps -u "$usuario" -o comm= | grep -cE "^(sshd|dropbear)$") ))

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


bloquear_desbloquear_usuario() {
    clear
    echo "==== 🔒 BLOQUEAR/DESBLOQUEAR USUARIO ===="
    echo "===== 📋 USUARIOS REGISTRADOS ====="
    printf "%-4s %-15s %-15s %-22s %-25s\n" "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "✅ Estado"
    echo "--------------------------------------------------------------------------"

    # Leer usuarios desde el archivo de registros
    usuarios=()
    index=1
    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}
        clave=${userpass#*:}
        estado="desbloqueado"
        bloqueo_file="/tmp/bloqueo_${usuario}.lock"

        if [[ -f "$bloqueo_file" ]]; then
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -lt $bloqueo_hasta ]]; then
                estado="bloqueado (hasta $(date -d @$bloqueo_hasta '+%I:%M%p'))"
            else
                rm -f "$bloqueo_file"
                usermod -U "$usuario" 2>/dev/null
                estado="desbloqueado"
            fi
        fi

        printf "%-4s %-15s %-15s %-22s %-25s\n" "$index" "$usuario" "$clave" "$fecha_exp" "$estado"
        usuarios[$index]="$usuario"
        ((index++))
    done < "$REGISTROS"

    echo "=========================================================================="
    read -p "👤 Digite el número o el nombre del usuario: " input

    # Validar entrada
    if [[ "$input" =~ ^[0-9]+$ ]] && [[ -n "${usuarios[$input]}" ]]; then
        usuario="${usuarios[$input]}"
    else
        usuario="$input"
    fi

    # Verificar si el usuario existe
    if ! grep -q "^${usuario}:" "$REGISTROS"; then
        echo -e "${ROJO}❌ Usuario '$usuario' no encontrado.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    bloqueo_file="/tmp/bloqueo_${usuario}.lock"
    if [[ -f "$bloqueo_file" ]] && [[ $(date +%s) -lt $(cat "$bloqueo_file") ]]; then
        echo -e "𒯢 El usuario '$usuario' está BLOQUEADO hasta $(date -d @$(cat "$bloqueo_file") '+%I:%M%p')."
        read -p "✅ Desea desbloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            rm -f "$bloqueo_file"
            usermod -U "$usuario" 2>/dev/null
            loginctl terminate-user "$usuario" 2>/dev/null
            pkill -9 -u "$usuario" 2>/dev/null
            killall -u "$usuario" -9 2>/dev/null
            echo -e "${VERDE}🔓 Usuario '$usuario' desbloqueado exitosamente.${NC}"
        else
            echo -e "${AMARILLO}⚠️ Operación cancelada.${NC}"
        fi
        read -p "Presiona Enter para continuar..."
        return
    else
        echo -e "𒯢 El usuario '$usuario' está DESBLOQUEADO."
        read -p "✅ Desea bloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            read -p "Ponga en minutos el tiempo que el usuario estaría bloqueado y confirmar con Enter: " minutos
            if [[ "$minutos" =~ ^[0-9]+$ ]] && [[ $minutos -gt 0 ]]; then
                bloqueo_hasta=$(( $(date +%s) + minutos * 60 ))
                echo "$bloqueo_hasta" > "$bloqueo_file"
                usermod -L "$usuario" 2>/dev/null
                loginctl terminate-user "$usuario" 2>/dev/null
                pkill -9 -u "$usuario" 2>/dev/null
                killall -u "$usuario" -9 2>/dev/null
                echo -e "${VERDE}🔒 Usuario '$usuario' bloqueado exitosamente y sesiones SSH terminadas. ✅${NC}"
                echo -e "Desbloqueado automáticamente hasta las $(date -d @$bloqueo_hasta '+%I:%M%p')"
            else
                echo -e "${ROJO}❌ Tiempo inválido. Debe ser un número mayor a 0.${NC}"
            fi
        else
            echo -e "${AMARILLO}⚠️ Operación cancelada.${NC}"
        fi
        read -p "Presiona Enter para continuar..."
    fi
}

monitorear_bloqueos() {
    LOG="/var/log/monitoreo_bloqueos.log"
    INTERVALO=10 # Verificar cada 10 segundos

    while true; do
        for bloqueo_file in /tmp/bloqueo_*.lock; do
            [[ ! -f "$bloqueo_file" ]] && continue
            usuario=$(basename "$bloqueo_file" .lock | cut -d_ -f2)
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -ge $bloqueo_hasta ]]; then
                rm -f "$bloqueo_file"
                usermod -U "$usuario" 2>/dev/null
                loginctl terminate-user "$usuario" 2>/dev/null
                pkill -9 -u "$usuario" 2>/dev/null
                killall -u "$usuario" -9 2>/dev/null
                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desbloqueado automáticamente." >> "$LOG"
            fi
        done
        sleep "$INTERVALO"
    done
}

# ================================
#  ARRANQUE AUTOMÁTICO DEL MONITOR DE BLOQUEOS
# ================================
if [[ ! -f "$PIDFILE.bloqueos" ]] || ! ps -p "$(cat "$PIDFILE.bloqueos" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PIDFILE.bloqueos"
    nohup bash "$0" mon_bloqueos >/dev/null 2>&1 &
    echo $! > "$PIDFILE.bloqueos"
fi

# ================================
#  MODO MONITOREO DE BLOQUEOS
# ================================
if [[ "$1" == "mon_bloqueos" ]]; then
    monitorear_bloqueos
    exit 0
fi
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
        echo -e "${VIOLETA}=====📆ANEL DE USUARIOS VPN/SSH ======${NC}"
        echo -e "${AMARILLO_SUAVE}1. 🆕 Crear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}2. 📋 Ver registros${NC}"
        echo -e "${AMARILLO_SUAVE}3. 🗑️ Eliminar usuario${NC}"
        echo -e "${AMARILLO_SUAVE}4. 📊 Información${NC}"
        echo -e "${AMARILLO_SUAVE}5. 🟢 Verificar usuarios online${NC}"
        echo -e "${AMARILLO_SUAVE}6. 🔒 Bloquear/Desbloquear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}7. 🆕 Crear múltiples usuarios${NC}"
        echo -e "${AMARILLO_SUAVE}8. 📋 Mini registro${NC}"
        
        echo -e "${AMARILLO_SUAVE}10. 🎨 Configurar banner SSH${NC}"
        echo -e "${AMARILLO_SUAVE}0. 🚪 Salir${NC}"
        PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")
        read -p "$PROMPT" OPCION
        case $OPCION in
            1) crear_usuario ;;
            2) ver_registros ;;
            3) eliminar_multiples_usuarios ;;
            4) informacion_usuarios ;;
            5) verificar_online ;;
            6) bloquear_desbloquear_usuario ;;
            7) crear_multiples_usuarios ;;
            8) mini_registro ;;
            9) configurar_banner_ssh ;;
            0) exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi
