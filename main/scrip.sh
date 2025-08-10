#!/bin/bash

# Archivo para almacenar registros de usuarios
REGISTRO_FILE="/root/ssh_users.txt"
# Directorio temporal para cálculos
TEMP_DIR="/tmp"
# Colores para la interfaz
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m" # Sin color

# Función para calcular la fecha de expiración
calcular_expiracion() {
    local dias=$1
    date -d "+$dias days" +"%Y-%m-%d %H:%M:%S"
}

# Función para formatear fecha a español (dd/mes/yyyy)
formato_fecha() {
    local fecha=$1
    # Lista de meses en español
    meses=("enero" "febrero" "marzo" "abril" "mayo" "junio" "julio" "agosto" "septiembre" "octubre" "noviembre" "diciembre")
    dia=$(date -d "$fecha" +"%d")
    mes=$(date -d "$fecha" +"%m")
    anio=$(date -d "$fecha" +"%Y")
    # Convertir mes numérico a texto (restamos 1 porque los índices en bash comienzan en 0)
    mes_index=$((10#$mes - 1))
    echo "$dia/${meses[$mes_index]}/$anio"
}

# Función para crear un usuario
crear_usuario() {
    clear
    echo -e "${GREEN}===== 🤪 CREAR USUARIO SSH =====${NC}"
    read -p "👤 Nombre del usuario: " username
    read -p "🔑 Contraseña: " password
    read -p "📅 Días de validez: " dias
    read -p "📱 ¿Cuántos móviles? " moviles

    # Validar que el usuario no exista
    if id "$username" >/dev/null 2>&1; then
        echo -e "${RED}Error: El usuario $username ya existe.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Validar que los días y móviles sean números
    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Los días y móviles deben ser números enteros.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuario en el sistema
    useradd -M -s /bin/false "$username"
    echo "$username:$password" | chpasswd

    # Calcular fecha de creación y expiración
    fecha_creacion=$(date +"%Y-%m-%d %H:%M:%S")
    fecha_expiracion=$(calcular_expiracion $dias)

    # Guardar en el archivo de registro
    echo "$username:$password:$fecha_expiracion:$dias:$moviles:$fecha_creacion" >> "$REGISTRO_FILE"

    # Mostrar información del usuario creado
    echo -e "${GREEN}✅ Usuario creado correctamente:${NC}"
    echo "👤 Usuario: $username"
    echo "🔑 Clave: $password"
    echo "📅 Expira: $(formato_fecha "$fecha_expiracion")"
    echo "📱 Límite móviles: $moviles"
    echo "📅 Creado: $fecha_creacion"
    echo -e "${YELLOW}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    echo "👤 Usuario    📅 Expira          ⏳ Días       📱 Móviles   📅 Creado"
    echo "---------------------------------------------------------------"
    printf "%-12s %-20s %-12s %-12s %s\n" "$username:$password" "$(formato_fecha "$fecha_expiracion")" "$dias días" "$moviles" "$fecha_creacion"
    echo "==============================================================="
    read -p "Presiona Enter para continuar..."
}

# Función para ver registros
ver_registros() {
    clear
    echo -e "${GREEN}===== 🌸 REGISTROS =====${NC}"
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira          ⏳ Días   📲 Móviles"
    echo "---------------------------------------------------------------"
    
    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Leer el archivo de registros
    count=1
    while IFS=':' read -r user pass expira dias moviles creado; do
        # Validar que los campos no estén vacíos o corruptos
        if [[ -z "$user" ]] || [[ -z "$pass" ]] || [[ -z "$expira" ]] || [[ -z "$dias" ]] || [[ -z "$moviles" ]] || [[ -z "$creado" ]]; then
            continue
        fi
        # CORREGIDO: Mostrar los valores correctos de días y móviles
        printf "%-2s %-12s %-12s %-18s %-10s %02d\n" "$count" "$user" "$pass" "$(formato_fecha "$expira")" "$dias" "$moviles"
        ((count++))
    done < "$REGISTRO_FILE"
    
    echo "---------------------------------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Función para terminar sesiones activas de un usuario (MODO NUCLEAR)
terminar_sesiones_usuario() {
    local username=$1
    echo -e "${BLUE}🔒 Terminando sesiones activas del usuario $username...${NC}"
    
    # Obtener sesiones por usuario exacto (más preciso)
    local sessions=$(loginctl list-sessions --no-legend | awk -v u="$username" '$3 == u {print $1}')
    
    if [[ -n "$sessions" ]]; then
        for session in $sessions; do
            echo "  🔐 Terminando sesión: $session"
            loginctl terminate-session "$session" 2>/dev/null || true
        done
        echo -e "${GREEN}✅ Sesiones terminadas para $username${NC}"
        
        # Pausa para asegurar cierre completo
        sleep 2
        
        # Verificar si quedan sesiones y forzar cierre
        local remaining=$(loginctl list-sessions --no-legend | awk -v u="$username" '$3 == u {print $1}')
        if [[ -n "$remaining" ]]; then
            echo -e "${YELLOW}  🔄 Forzando cierre de sesiones restantes...${NC}"
            for session in $remaining; do
                loginctl kill-session "$session" 2>/dev/null || true
            done
            sleep 1
        fi
    else
        echo -e "${YELLOW}ℹ️ No hay sesiones activas para $username${NC}"
    fi
}

# Función para obtener usuario por número
obtener_usuario_por_numero() {
    local numero=$1
    local count=1
    while IFS=':' read -r user pass expira dias moviles creado; do
        if [[ -z "$user" ]]; then
            continue
        fi
        if [[ $count -eq $numero ]]; then
            echo "$user"
            return
        fi
        ((count++))
    done < "$REGISTRO_FILE"
    echo ""
}

# Función para eliminar usuario
eliminar_usuario() {
    clear
    echo -e "${GREEN}===== 🗑️ ELIMINAR USUARIO SSH =====${NC}"
    
    # Verificar si hay usuarios registrados
    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados para eliminar.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Mostrar lista de usuarios
    echo -e "${YELLOW}Lista de usuarios registrados:${NC}"
    echo "Nº 👩 Usuario"
    echo "-----------------"
    count=1
    while IFS=':' read -r user pass expira dias moviles creado; do
        if [[ -z "$user" ]]; then
            continue
        fi
        printf "%-2s %s\n" "$count" "$user"
        ((count++))
    done < "$REGISTRO_FILE"
    echo "-----------------"

    # Solicitar el nombre del usuario a eliminar
    echo -e "${YELLOW}💡 Puedes usar:${NC}"
    echo "  - Nombres de usuario: pedro juan maria"
    echo "  - Números: 1 2 3 4 5"
    echo "  - Combinación: pedro 2 maria 4"
    echo ""
    read -p "👤 Usuario(s) a eliminar: " input_usuarios

    # Convertir la entrada en un array
    read -a usuarios_array <<< "$input_usuarios"
    
    # Array para almacenar usuarios válidos para eliminar
    declare -a usuarios_eliminar

    # Procesar cada entrada
    for item in "${usuarios_array[@]}"; do
        username=""
        
        # Verificar si es un número
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            username=$(obtener_usuario_por_numero "$item")
            if [[ -z "$username" ]]; then
                echo -e "${RED}⚠️ Número $item no válido (fuera de rango)${NC}"
                continue
            fi
        else
            # Es un nombre de usuario
            username="$item"
        fi

        # Verificar si el usuario existe en el sistema y en el registro
        if ! id "$username" >/dev/null 2>&1; then
            echo -e "${RED}⚠️ El usuario $username no existe en el sistema${NC}"
            continue
        fi

        if ! grep -q "^$username:" "$REGISTRO_FILE"; then
            echo -e "${RED}⚠️ El usuario $username no está en el registro${NC}"
            continue
        fi

        # Agregar a la lista de usuarios a eliminar (evitar duplicados)
        if [[ ! " ${usuarios_eliminar[@]} " =~ " ${username} " ]]; then
            usuarios_eliminar+=("$username")
        fi
    done

    # Verificar si hay usuarios válidos para eliminar
    if [[ ${#usuarios_eliminar[@]} -eq 0 ]]; then
        echo -e "${RED}❌ No hay usuarios válidos para eliminar${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Mostrar usuarios que se van a eliminar
    echo ""
    echo -e "${YELLOW}📋 Usuarios que serán eliminados:${NC}"
    for user in "${usuarios_eliminar[@]}"; do
        echo "  🗑️ $user"
    done
    echo ""
    
    # Confirmar eliminación
    read -p "❓ ¿Estás seguro de eliminar estos usuarios? (s/N): " confirmar
    if [[ ! "$confirmar" =~ ^[sS]$ ]]; then
        echo -e "${YELLOW}❌ Operación cancelada${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Eliminar usuarios
    echo ""
    echo -e "${BLUE}🔄 Iniciando proceso de eliminación NUCLEAR...${NC}"
    
    for username in "${usuarios_eliminar[@]}"; do
        echo ""
        echo -e "${YELLOW}💣 Eliminando usuario: $username (MODO NUCLEAR)${NC}"
        
        # 1. Terminar sesiones activas con método nuclear
        terminar_sesiones_usuario "$username"
        
        # 2. Matar todos los procesos del usuario
        echo "  ⚔️ Eliminando procesos del usuario..."
        pkill -u "$username" 2>/dev/null || true
        sleep 1
        
        # 3. Forzar eliminación completa del usuario del sistema
        echo "  🔧 Eliminando del sistema (FORZADO)..."
        if userdel -r -f "$username" 2>/dev/null; then
            echo -e "${GREEN}    ✅ Usuario eliminado del sistema${NC}"
        else
            echo -e "${RED}    ⚠️ Error al eliminar del sistema, intentando método alternativo...${NC}"
            # Método alternativo más agresivo
            userdel -f "$username" 2>/dev/null || true
            rm -rf "/home/$username" 2>/dev/null || true
        fi
        
        # 4. Eliminar usuario del archivo de registro con sync
        echo "  📝 Eliminando del registro..."
        sed -i "/^$username:/d" "$REGISTRO_FILE" 2>/dev/null
        sync  # Forzar escritura al disco
        
        # 5. Verificación final de limpieza
        echo "  🧹 Verificando limpieza completa..."
        
        # Verificar que no exista en el sistema
        if ! id "$username" >/dev/null 2>&1; then
            echo -e "${GREEN}    ✅ Usuario completamente eliminado del sistema${NC}"
        else
            echo -e "${RED}    ⚠️ Usuario aún existe, aplicando limpieza final...${NC}"
            # Último recurso: editar directamente /etc/passwd, /etc/shadow, /etc/group
            sed -i "/^$username:/d" /etc/passwd 2>/dev/null || true
            sed -i "/^$username:/d" /etc/shadow 2>/dev/null || true
            sed -i "/^$username:/d" /etc/group 2>/dev/null || true
        fi
        
        # Verificar que no esté en el registro
        if ! grep -q "^$username:" "$REGISTRO_FILE" 2>/dev/null; then
            echo -e "${GREEN}    ✅ Usuario eliminado del registro${NC}"
        else
            echo -e "${RED}    ⚠️ Reintentando eliminación del registro...${NC}"
            grep -v "^$username:" "$REGISTRO_FILE" > "$TEMP_DIR/ssh_users_temp.txt" 2>/dev/null
            mv "$TEMP_DIR/ssh_users_temp.txt" "$REGISTRO_FILE" 2>/dev/null
            sync
        fi
        
        echo -e "${GREEN}  🎯 Usuario $username COMPLETAMENTE ERRADICADO${NC}"
    done

    echo ""
    echo -e "${GREEN}🎉 Proceso completado. ${#usuarios_eliminar[@]} usuario(s) eliminado(s)${NC}"
    read -p "Presiona Enter para continuar..."
}

# Menú principal
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
