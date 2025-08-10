#!/bin/bash

REGISTRO_FILE="/root/ssh_users.txt"
TEMP_DIR="/tmp"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" 

calcular_expiracion() {
    local dias=$1
    date -d "+$dias days" +"%Y-%m-%d %H:%M:%S"
}

formato_fecha() {
    local fecha=$1
    meses=("enero" "febrero" "marzo" "abril" "mayo" "junio" "julio" "agosto" "septiembre" "octubre" "noviembre" "diciembre")
    dia=$(date -d "$fecha" +"%d")
    mes=$(date -d "$fecha" +"%m")
    anio=$(date -d "$fecha" +"%Y")
    mes_index=$((10#$mes - 1))
    echo "$dia/${meses[$mes_index]}/$anio"
}

crear_usuario() {
    clear
    echo -e "${GREEN}===== 🤪 CREAR USUARIO SSH =====${NC}"
    read -p "👤 Nombre del usuario: " username
    read -p "🔑 Contraseña: " password
    read -p "📅 Días de validez: " dias
    read -p "📱 ¿Cuántos móviles? " moviles

    if id "$username" >/dev/null 2>&1; then
        echo -e "${RED}Error: El usuario $username ya existe.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Los días y móviles deben ser números enteros.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    useradd -M -s /bin/false "$username"
    echo "$username:$password" | chpasswd

    fecha_creacion=$(date +"%Y-%m-%d %H:%M:%S")
    fecha_expiracion=$(calcular_expiracion $dias)

    echo "$username:$password:$fecha_expiracion:$dias:$moviles:$fecha_creacion" >> "$REGISTRO_FILE"

    echo -e "${GREEN}✅ Usuario creado correctamente:${NC}"
    echo "👤 Usuario: $username"
    echo "🔑 Clave: $password"
    echo "📅 Expira: $(formato_fecha "$fecha_expiracion")"
    echo "📱 Límite móviles: $moviles"
    echo "📅 Creado: $fecha_creacion"
    echo -e "${YELLOW}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    echo "👤 Usuario    📅 Expira          ⏳  Días       📱 Móviles   📅 Creado"
    echo "---------------------------------------------------------------"
    printf "%-12s %-20s %-12s %-12s %s\n" "$username:$password" "$(formato_fecha "$fecha_expiracion")" "$dias días" "$moviles" "$fecha_creacion"
    echo "==============================================================="
    read -p "Presiona Enter para continuar..."
}

ver_registros() {
    clear
    echo -e "${GREEN}===== 🌸 REGISTROS =====${NC}"
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira          ⏳  Días   📲 Móviles"
    echo "---------------------------------------------------------------"

    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    count=1
    while IFS=':' read -r user pass expira dias moviles creado; do
        if [[ -z "$user" ]] || [[ -z "$pass" ]] || [[ -z "$expira" ]] || [[ -z "$dias" ]] || [[ -z "$moviles" ]] || [[ -z "$creado" ]]; then
            continue
        fi
        # Mostrar valores sin ceros ni confusión, el campo días y móviles es numérico pero sin ceros delante:
        printf "%-2s %-12s %-12s %-18s %-7s %s\n" "$count" "$user" "$pass" "$(formato_fecha "$expira")" "$dias" "$moviles"
        ((count++))
    done < "$REGISTRO_FILE"

    echo "---------------------------------------------------------------"
    read -p "Presiona Enter para continuar..."
}

eliminar_usuario() {
    clear
    echo -e "${GREEN}===== 🗑️ ELIMINAR USUARIO SSH =====${NC}"

    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados para eliminar.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    echo -e "${YELLOW}Lista de usuarios registrados:${NC}"
    echo "Nº 👩 Usuario"
    echo "-----------------"
    # Guardar usuarios en array para soporte con números listados luego. Índices inician en 1 para matching fácil.
    mapfile -t usuarios < <(awk -F: '{print $1}' "$REGISTRO_FILE")
    for i in "${!usuarios[@]}"; do
        idx=$((i+1))
        echo "$idx  ${usuarios[$i]}"
    done
    echo "-----------------"

    read -p "👤 Nombre(s) o Nº(s) de usuario(s) a eliminar (separados por espacios): " -a entrada

    # Si la entrada está vacía, cancelar
    if [[ ${#entrada[@]} -eq 0 ]]; then
        echo -e "${RED}No ingresaste ningún usuario.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    for item in "${entrada[@]}"; do
        # Detectar si item es número válido en rango, convertir a nombre usuario:
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            if (( item >= 1 && item <= ${#usuarios[@]} )); then
                username="${usuarios[$((item-1))]}"
            else
                echo -e "${RED}Error: El número $item no corresponde a ningún usuario listado.${NC}"
                continue
            fi
        else
            username="$item"
        fi

        if ! id "$username" >/dev/null 2>&1; then
            echo -e "${RED}Error: El usuario $username no existe en el sistema.${NC}"
            continue
        fi

        if ! grep -q "^$username:" "$REGISTRO_FILE"; then
            echo -e "${RED}Error: El usuario $username no está en el registro.${NC}"
            continue
        fi

        # Bloquear sesiones activas (eliminar todas las sesiones activas de ese usuario con loginctl)
        echo "Bloqueando sesiones activas de $username..."
        sessions=$(loginctl list-sessions --no-legend | awk -v usr="$username" '$3 == usr {print $1}')
        for session in $sessions; do
            echo "Cerrando sesión $session de $username..."
            loginctl terminate-session "$session" 2>/dev/null
        done

        # Eliminar usuario del sistema (forzar eliminación)
        echo "Eliminando usuario $username del sistema..."
        userdel -r "$username" 2>/dev/null || userdel "$username"

        # Eliminar usuario del registro
        grep -v "^$username:" "$REGISTRO_FILE" > "$TEMP_DIR/ssh_users_temp.txt"
        mv "$TEMP_DIR/ssh_users_temp.txt" "$REGISTRO_FILE"

        echo -e "${GREEN}✅ Usuario $username eliminado correctamente.${NC}"
    done
    read -p "Presiona Enter para continuar..."
}

while true; do
    clear
    echo -e "${YELLOW}===== MENÚ SSH WEBSOCKET =====${NC}"
    echo "1. Crear usuario"
    echo "2. Ver registros"
    echo "3. Eliminar usuario"
    echo "0. Salir"
    read -p "Selecciona una opción [0-3]: " opcion

    case $opcion in
        1) crear_usuario ;;
        2) ver_registros ;;
        3) eliminar_usuario ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; read -p "Presiona Enter para continuar..." ;;
    esac
done
