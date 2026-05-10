#!/bin/bash
# ══════════════════════════════════════════════════════════════
#  tokens-bot.sh — Bot Telegram para gestión de tokens v2.1
#                  Arquitectura MULTIUSUARIO real
#                  + Toggle ON/OFF por instancia (sin borrar nada)
#
#  Uso: bash tokens-bot.sh           → Menú de gestión
#       (modo --daemon es interno, no llamar manualmente)
#
#  Estructura por instancia:
#    Config : /etc/tgbots/bot_{slug}.conf
#    PID    : /etc/tgbots/bot_{slug}.pid
#    DB     : /var/www/html/db_{slug}.db
#    Backups: /var/backups/tokens-db/{slug}/
# ══════════════════════════════════════════════════════════════

# ── Directorio central de instancias ──────────────────────────
INSTANCES_DIR="/etc/tgbots"
DB_BASE_DIR="/var/www/html"
BACKUP_BASE_DIR="/var/backups/tokens-db"
SCRIPT_PATH="$(realpath "$0")"

# ── Colores (solo para el manager interactivo) ─────────────────
HOT='\e[38;5;198m'; MAG='\e[38;5;201m'; CYAN='\e[38;5;159m'
GOLD='\e[38;5;220m'; GRN='\e[38;5;82m'; RED='\e[38;5;196m'
PINK='\e[38;5;212m'; RST='\e[0m'; BLD='\e[1m'

# ══════════════════════════════════════════════════════════════
#  MODO DAEMON  (llamado internamente por el manager)
#  $2 = BOT_TOKEN
#  $3 = ALLOWED_IDS  (csv: "123,456,789")
#  $4 = ADMIN_NAME
#  $5 = DB_PATH      (ej: /var/www/html/db_pepe.db)
#  $6 = BACKUP_DIR   (ej: /var/backups/tokens-db/pepe)
# ══════════════════════════════════════════════════════════════
if [[ "$1" == "--daemon" ]]; then
  BOT_TOKEN="$2"
  ALLOWED_IDS="${3//,/ }"
  ADMIN_NAME="${4:-Admin}"
  DB="$5"
  BACKUP_DIR="$6"
  URL="https://api.telegram.org/bot${BOT_TOKEN}"
  OFFSET=0

  # ── Extraer slug de la instancia actual para presentación ────
  # db_manzana.db → manzana  |  db_alexa.db → alexa
  SLUG=$(basename "$DB" .db)
  SLUG="${SLUG#db_}"

  declare -A STATE STEP TMPDATA

  # ── Helpers ──────────────────────────────────────────────────
  q()  { sqlite3 "$DB" "$@"; }
  qs() { sqlite3 -separator $'\t' "$DB" "$@"; }
  safe() { printf '%s' "$1" | sed "s/'/''/g"; }

  is_allowed() {
    for id in $ALLOWED_IDS; do [[ "$1" == "$id" ]] && return 0; done
    return 1
  }

  send_msg() {
    curl -s -X POST "$URL/sendMessage" \
      --data-urlencode "chat_id=$1" \
      --data-urlencode "text=$2" \
      --data-urlencode "parse_mode=Markdown" >/dev/null
  }

  send_doc() {
    curl -s -X POST "$URL/sendDocument" \
      -F "chat_id=$1" -F "document=@$2" \
      -F "caption=$3" -F "parse_mode=Markdown" >/dev/null
  }

  gen_token() {
    local tok exists
    while true; do
      tok=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
      exists=$(q "SELECT COUNT(*) FROM tokens WHERE token='$(safe "$tok")'")
      [[ "$exists" == "0" ]] && echo "$tok" && return
    done
  }

  # ── Menú principal ───────────────────────────────────────────
  do_menu() {
    send_msg "$1" "¡Hola! 😏 *${ADMIN_NAME}* 👋 Selecciona una opción:

📊 *1*  — Stats rápidas
📋 *2*  — Ver todos los tokens
➕ *3*  — Crear token manual
🚀 *4*  — Crear tokens masivos
📄 *5*  — Tokens libres
✍️  *6*  — Crear multi usuario manual
🗑️  *7*  — Eliminar tokens usados
🔢 *8*  — Eliminar por índice
🚨 *9*  — IPs con abuso / bloqueadas
🔓 *10* — Desbloquear IP
🔄 *11* — Resetear token (reactivar)
💾 *12* — Crear backup DB
📥 *13* — Restaurar backup"
  }

  # ── Stats ────────────────────────────────────────────────────
  do_stats() {
    local t u l
    t=$(q "SELECT COUNT(*) FROM tokens")
    u=$(q "SELECT COUNT(*) FROM tokens WHERE used=1")
    l=$((t - u))
    send_msg "$1" "📊 *STATS DE TOKENS*

💎 *Total:*  \`$t\`
🟢 *Libres:* \`$l\`
🔴 *Usados:* \`$u\`

Escribe *hola* para ver el menú."
  }

  # ── Ver todos los tokens ─────────────────────────────────────
  do_ver_tokens() {
    local cid="$1" t u l msg
    t=$(q "SELECT COUNT(*) FROM tokens")
    u=$(q "SELECT COUNT(*) FROM tokens WHERE used=1")
    l=$((t - u))
    msg="📋 *TOKENS — instancia:* \`${SLUG}\`
📊 Total: $t | 🟢 Libres: $l | 🔴 Usados: $u

"
    while IFS=$'\t' read -r user tok used ip ts; do
      if [[ "$used" == "1" ]]; then
        msg+="🔴 \`${user}\`  \`${tok}\`
  IP: ${ip:-—}  |  ${ts:-—}

"
      else
        msg+="🟢 \`${user}\` → \`${SLUG}:${tok}\`
"
      fi
    done < <(qs "SELECT user, token, used,
        COALESCE(ip,''),
        CASE WHEN used_at IS NOT NULL
             THEN datetime(used_at,'unixepoch','localtime')
             ELSE '' END
        FROM tokens ORDER BY used DESC, user ASC")

    if [[ ${#msg} -gt 3500 ]]; then
      local f="/tmp/tklist_$(date +%s).txt"
      printf '%s' "$msg" > "$f"
      send_doc "$cid" "$f" "📋 Lista completa de tokens — instancia: ${SLUG}"
      rm -f "$f"
    else
      send_msg "$cid" "${msg}
Escribe *hola* para ver el menú."
    fi
  }

  # ── Mini tokens (solo libres) ────────────────────────────────
  do_mini_tokens() {
    local cid="$1" msg cnt=0
    msg="📄 *TOKENS LIBRES — instancia:* \`${SLUG}\`

"
    while IFS=$'\t' read -r user tok; do
      msg+="$(printf "%-18s" "$user")  \`${SLUG}:${tok}\`
"
      ((cnt++))
    done < <(qs "SELECT user, token FROM tokens WHERE used=0 ORDER BY user ASC")
    msg+="
*Total:* $cnt  |  Escribe *hola* para ver el menú."
    if [[ ${#msg} -gt 3500 ]]; then
      local f="/tmp/tkfree_$(date +%s).txt"
      printf '%s' "$msg" > "$f"
      send_doc "$cid" "$f" "📄 Tokens libres ($cnt) — instancia: ${SLUG}"
      rm -f "$f"
    else
      send_msg "$cid" "$msg"
    fi
  }

  # ── Abuso / IPs bloqueadas ───────────────────────────────────
  do_abuse() {
    local cid="$1" now msg has
    now=$(date +%s)
    msg="🚨 *IPs CON MÚLTIPLES TOKENS USADOS*

"
    has=0
    while IFS=$'\t' read -r ip cnt users; do
      msg+="🔴 \`${ip}\` — ${cnt} usos
  Usuarios: ${users}

"
      ((has++))
    done < <(qs "SELECT ip, COUNT(*) as c, GROUP_CONCAT(user,', ')
        FROM tokens WHERE used=1 AND ip IS NOT NULL
        GROUP BY ip HAVING c>1 ORDER BY c DESC")
    [[ $has -eq 0 ]] && msg+="✅ Sin IPs sospechosas.
"
    msg+="
🔒 *IPs BLOQUEADAS*

"
    has=0
    while IFS=$'\t' read -r ip att until_ts; do
      msg+="🚫 \`${ip}\` — ${att} intentos — hasta ${until_ts}
"
      ((has++))
    done < <(qs "SELECT ip, attempts,
        datetime(blocked_until,'unixepoch','localtime')
        FROM rate_limit WHERE blocked_until > $now ORDER BY blocked_until DESC")
    [[ $has -eq 0 ]] && msg+="✅ Ninguna IP bloqueada."
    msg+="

Escribe *hola* para ver el menú."
    send_msg "$cid" "$msg"
  }

  # ══════════════════════════════════════════════════════════════
  #  MANEJADOR DE ESTADOS (interacciones multi-paso)
  # ══════════════════════════════════════════════════════════════
  handle_state() {
    local cid="$1" text="$2" doc_id="$3"
    local state="${STATE[$cid]}" step="${STEP[$cid]}"

    if [[ "$text" == "cancel" || "$text" == "Cancel" ]]; then
      STATE[$cid]=""; STEP[$cid]=0
      send_msg "$cid" "❌ *Cancelado.* Escribe *hola* para ver el menú."
      return
    fi

    case "$state" in

    create_token)
      local exists; exists=$(q "SELECT COUNT(*) FROM tokens WHERE user='$(safe "$text")'")
      if [[ "$exists" != "0" ]]; then
        send_msg "$cid" "❌ *El usuario* \`$text\` *ya existe.*
Escribe *hola* para ver el menú."
      else
        local tok now_ts
        tok=$(gen_token); now_ts=$(date +%s)
        q "INSERT INTO tokens (token,user,used,ip,used_at,created_at,expires_at)
           VALUES ('$(safe "$tok")','$(safe "$text")',0,NULL,NULL,$now_ts,NULL)"
        send_msg "$cid" "✅ *Token creado:*

👤 *Usuario:* \`$text\`
🔑 *Token:*   \`$tok\`
📋 *Usarlo:*  \`${SLUG}:${tok}\`

Escribe *hola* para ver el menú."
      fi
      STATE[$cid]=""
      ;;

    bulk_step1)
      TMPDATA["${cid}_base"]="$text"
      STATE[$cid]="bulk_step2"
      send_msg "$cid" "🔢 *¿Cuántos tokens crear?*"
      ;;

    bulk_step2)
      local base="${TMPDATA["${cid}_base"]}"
      if ! [[ "$text" =~ ^[0-9]+$ ]] || [[ "$text" -lt 1 ]]; then
        send_msg "$cid" "❌ *Número inválido.* Escribe *hola* para volver."
        STATE[$cid]=""; return
      fi
      local cantidad="$text" now_ts created=0 skipped=0
      now_ts=$(date +%s)
      local sql="BEGIN;"
      local tmpf="/tmp/bulk_${base}_$(date +%s).txt"
      # Cabecera del TXT exportado
      printf "%-20s %-18s %s\n" "USUARIO" "TOKEN" "ACTIVAR" >> "$tmpf"
      printf "%-20s %-18s %s\n" "-------" "-----" "-------" >> "$tmpf"
      for ((i=1; i<=cantidad; i++)); do
        local uname="${base}${i}"
        local exists; exists=$(q "SELECT COUNT(*) FROM tokens WHERE user='$(safe "$uname")'")
        if [[ "$exists" != "0" ]]; then ((skipped++)); continue; fi
        local tok; tok=$(gen_token)
        sql+="INSERT INTO tokens (token,user,used,ip,used_at,created_at,expires_at)
              VALUES ('$(safe "$tok")','$(safe "$uname")',0,NULL,NULL,$now_ts,NULL);"
        printf "%-20s %-18s %s\n" "$uname" "$tok" "${SLUG}:${tok}" >> "$tmpf"
        ((created++))
      done
      sql+="COMMIT;"
      [[ $created -gt 0 ]] && echo "$sql" | sqlite3 "$DB"
      send_msg "$cid" "🚀 *Tokens masivos — ${base}*

✅ *Creados:*  $created
⏭️  *Saltados:* $skipped"
      if [[ $created -gt 0 && -f "$tmpf" ]]; then
        send_doc "$cid" "$tmpf" "🚀 ${base} — $created tokens generados — instancia: ${SLUG}"
      fi
      rm -f "$tmpf"
      send_msg "$cid" "Escribe *hola* para ver el menú."
      STATE[$cid]=""
      ;;

    multi_manual)
      if [[ "$text" == "listo" || "$text" == "Listo" ]]; then
        local raw="${TMPDATA["${cid}_lines"]}"
        if [[ -z "$raw" ]]; then
          send_msg "$cid" "❌ *Sin líneas.* Escribe *hola* para ver el menú."
          STATE[$cid]=""; return
        fi
        local created=0 skipped=0 now_ts sql result
        now_ts=$(date +%s); sql="BEGIN;"
        result="✍️ *MULTI USUARIO — instancia:* \`${SLUG}\`

"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local uname tok; read -r uname tok <<< "$line"
          if [[ -z "$uname" || -z "$tok" ]]; then ((skipped++)); continue; fi
          local eu et
          eu=$(q "SELECT COUNT(*) FROM tokens WHERE user='$(safe "$uname")'")
          et=$(q "SELECT COUNT(*) FROM tokens WHERE token='$(safe "$tok")'")
          if [[ "$eu" != "0" || "$et" != "0" ]]; then
            result+="⏭️ \`$uname\` — ya existe
"; ((skipped++)); continue
          fi
          sql+="INSERT INTO tokens (token,user,used,ip,used_at,created_at,expires_at)
                VALUES ('$(safe "$tok")','$(safe "$uname")',0,NULL,NULL,$now_ts,NULL);"
          result+="✅ \`$uname\` → \`${SLUG}:${tok}\`
"; ((created++))
        done <<< "$raw"
        sql+="COMMIT;"
        [[ $created -gt 0 ]] && echo "$sql" | sqlite3 "$DB"
        result+="
✅ *Creados:* $created  |  ⏭️ *Saltados:* $skipped

Escribe *hola* para ver el menú."
        send_msg "$cid" "$result"
        unset "TMPDATA[${cid}_lines]"
        STATE[$cid]=""
      else
        local cur="${TMPDATA["${cid}_lines"]}"
        TMPDATA["${cid}_lines"]="${cur:+${cur}$'\n'}${text}"
        send_msg "$cid" "✍️ Línea guardada. Sigue enviando o escribe *listo*."
      fi
      ;;

    delete_used)
      if [[ "$text" == "ELIMINAR" ]]; then
        local cnt; cnt=$(q "SELECT COUNT(*) FROM tokens WHERE used=1")
        q "DELETE FROM tokens WHERE used=1"
        send_msg "$cid" "🗑️ *$cnt tokens usados eliminados.*
Escribe *hola* para ver el menú."
      else
        send_msg "$cid" "🛡️ *Cancelado.* DB intacta.
Escribe *hola* para ver el menú."
      fi
      STATE[$cid]=""
      ;;

    delete_by_idx)
      local -a all_u all_t
      while IFS=$'\t' read -r u t; do
        all_u+=("$u"); all_t+=("$t")
      done < <(qs "SELECT user, token FROM tokens ORDER BY used DESC, user ASC")
      local total=${#all_u[@]}
      local -a del_u del_t bad_idx

      for item in $text; do
        if [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
          for ((ii=${BASH_REMATCH[1]}; ii<=${BASH_REMATCH[2]}; ii++)); do
            local r=$((ii-1))
            if [[ $r -ge 0 && $r -lt $total ]]; then
              del_u+=("${all_u[$r]}"); del_t+=("${all_t[$r]}")
            else bad_idx+=("$ii"); fi
          done
        elif [[ "$item" =~ ^[0-9]+$ ]]; then
          local r=$((item-1))
          if [[ $r -ge 0 && $r -lt $total ]]; then
            del_u+=("${all_u[$r]}"); del_t+=("${all_t[$r]}")
          else bad_idx+=("$item"); fi
        fi
      done

      if [[ ${#del_u[@]} -eq 0 ]]; then
        send_msg "$cid" "❌ *Sin índices válidos.*
Escribe *hola* para ver el menú."
        STATE[$cid]=""; return
      fi
      local sql="BEGIN;"
      for tok in "${del_t[@]}"; do
        sql+="DELETE FROM tokens WHERE token='$(safe "$tok")';"
      done
      sql+="COMMIT;"
      echo "$sql" | sqlite3 "$DB"

      local lista="🗑️ *Eliminados (${#del_u[@]}):*

"
      for u in "${del_u[@]}"; do lista+="❌ \`$u\`
"; done
      [[ ${#bad_idx[@]} -gt 0 ]] && lista+="
⚠️ Índices inválidos: ${bad_idx[*]}"
      lista+="

Escribe *hola* para ver el menú."
      send_msg "$cid" "$lista"
      STATE[$cid]=""
      ;;

    unblock_ip)
      if [[ "$text" == "0" ]]; then
        send_msg "$cid" "🛡️ *Cancelado.* Escribe *hola* para ver el menú."
      else
        local target="${TMPDATA["${cid}_ip_${text}"]}"
        if [[ -z "$target" ]]; then
          send_msg "$cid" "❌ *Selección inválida.* Escribe *hola* para ver el menú."
        else
          q "DELETE FROM rate_limit WHERE ip='$(safe "$target")'"
          send_msg "$cid" "🔓 *IP desbloqueada:* \`$target\`
Escribe *hola* para ver el menú."
        fi
      fi
      local cnt="${TMPDATA["${cid}_ip_count"]}"
      for ((kk=1; kk<=${cnt:-0}; kk++)); do unset "TMPDATA[${cid}_ip_${kk}]"; done
      unset "TMPDATA[${cid}_ip_count]"
      STATE[$cid]=""; STEP[$cid]=0
      ;;

    reset_token)
      local exists used_st
      exists=$(q "SELECT COUNT(*) FROM tokens WHERE user='$(safe "$text")'")
      if [[ "$exists" == "0" ]]; then
        send_msg "$cid" "❌ *Usuario* \`$text\` *no existe.*
Escribe *hola* para ver el menú."
        STATE[$cid]=""; return
      fi
      used_st=$(q "SELECT used FROM tokens WHERE user='$(safe "$text")'")
      if [[ "$used_st" == "0" ]]; then
        send_msg "$cid" "⚠️ El token de \`$text\` ya está libre, no necesita reset.
Escribe *hola* para ver el menú."
        STATE[$cid]=""; return
      fi
      TMPDATA["${cid}_reset_user"]="$text"
      STATE[$cid]="reset_token_confirm"
      send_msg "$cid" "🔄 *Resetear token de* \`$text\`

Esto marcará el token como libre (used=0) y borrará la IP registrada.

Escribe *RESETEAR* para confirmar o *cancel* para cancelar."
      ;;

    reset_token_confirm)
      local uname="${TMPDATA["${cid}_reset_user"]}"
      if [[ "$text" == "RESETEAR" ]]; then
        q "UPDATE tokens SET used=0, ip=NULL, used_at=NULL WHERE user='$(safe "$uname")'"
        send_msg "$cid" "🔄 *Token reseteado correctamente.*

👤 *Usuario:* \`${uname}\`
✅ Token libre y listo para usar de nuevo.

Escribe *hola* para ver el menú."
      else
        send_msg "$cid" "🛡️ *Cancelado.* Token intacto.
Escribe *hola* para ver el menú."
      fi
      unset "TMPDATA[${cid}_reset_user]"
      STATE[$cid]=""
      ;;

    restore_backup)
      if [[ "${STEP[$cid]}" == "1" ]]; then
        if [[ -n "$doc_id" ]]; then
          local fi_info fp dl tmp_db
          fi_info=$(curl -s "$URL/getFile?file_id=$doc_id")
          fp=$(echo "$fi_info" | jq -r '.result.file_path // empty')
          if [[ -z "$fp" ]]; then
            send_msg "$cid" "❌ *Error al obtener el archivo.* Intenta de nuevo."; return
          fi
          dl="https://api.telegram.org/file/bot${BOT_TOKEN}/${fp}"
          tmp_db="/tmp/restore_${cid}_$(date +%s).db"
          curl -s -o "$tmp_db" "$dl"

          local magic; magic=$(head -c 6 "$tmp_db" 2>/dev/null || echo "")
          if [[ "$magic" != "SQLite" ]]; then
            rm -f "$tmp_db"
            send_msg "$cid" "❌ *Archivo inválido.* No es una DB SQLite.
Escribe *hola* para ver el menú."
            STATE[$cid]=""; return
          fi
          local integ; integ=$(sqlite3 "$tmp_db" "PRAGMA integrity_check;" 2>/dev/null)
          if [[ "$integ" != "ok" ]]; then
            rm -f "$tmp_db"
            send_msg "$cid" "❌ *Backup corrupto.* integrity_check falló.
Escribe *hola* para ver el menú."
            STATE[$cid]=""; return
          fi
          local has_tbl; has_tbl=$(sqlite3 "$tmp_db" \
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='tokens';" 2>/dev/null)
          if [[ "$has_tbl" != "1" ]]; then
            rm -f "$tmp_db"
            send_msg "$cid" "❌ *Backup inválido.* No contiene la tabla 'tokens'.
Escribe *hola* para ver el menú."
            STATE[$cid]=""; return
          fi
          local tt tf tu
          tt=$(sqlite3 "$tmp_db" "SELECT COUNT(*) FROM tokens;")
          tf=$(sqlite3 "$tmp_db" "SELECT COUNT(*) FROM tokens WHERE used=0;")
          tu=$(sqlite3 "$tmp_db" "SELECT COUNT(*) FROM tokens WHERE used=1;")
          TMPDATA["${cid}_rst_path"]="$tmp_db"
          TMPDATA["${cid}_rst_total"]="$tt"
          TMPDATA["${cid}_rst_free"]="$tf"
          TMPDATA["${cid}_rst_used"]="$tu"
          STEP[$cid]=2
          send_msg "$cid" "📊 *Backup recibido y validado:*

💎 Total: $tt  |  🟢 Libres: $tf  |  🔴 Usados: $tu

⚠️ *La DB actual será reemplazada.*
Se creará un safety backup automáticamente.

Escribe *RESTAURAR* para confirmar o *cancel* para cancelar."
        else
          send_msg "$cid" "📥 Esperando archivo *.db*...
Envíalo o escribe *cancel* para cancelar."
        fi

      elif [[ "${STEP[$cid]}" == "2" ]]; then
        local src="${TMPDATA["${cid}_rst_path"]}"
        if [[ "$text" == "RESTAURAR" ]]; then
          mkdir -p "$BACKUP_DIR"
          if [[ -f "$DB" ]]; then
            cp "$DB" "$BACKUP_DIR/tokens_$(date +%Y%m%d_%H%M%S)_pre_restore.db"
          fi
          cp "$src" "$DB"
          chown www-data:www-data "$DB" 2>/dev/null || true
          chmod 660 "$DB" 2>/dev/null || true
          rm -f "$src"
          send_msg "$cid" "✅ *¡Restauración completada!*

💎 Total: ${TMPDATA["${cid}_rst_total"]}
🟢 Libres: ${TMPDATA["${cid}_rst_free"]}
🔴 Usados: ${TMPDATA["${cid}_rst_used"]}

Escribe *hola* para ver el menú."
        else
          rm -f "$src" 2>/dev/null
          send_msg "$cid" "🛡️ *Restauración cancelada.* DB intacta.
Escribe *hola* para ver el menú."
        fi
        unset "TMPDATA[${cid}_rst_path]" "TMPDATA[${cid}_rst_total]"
        unset "TMPDATA[${cid}_rst_free]"  "TMPDATA[${cid}_rst_used]"
        STATE[$cid]=""; STEP[$cid]=0
      fi
      ;;

    esac
  }

  # ══════════════════════════════════════════════════════════════
  #  MANEJADOR DE COMANDOS (sin estado activo)
  # ══════════════════════════════════════════════════════════════
  handle_cmd() {
    local cid="$1" text="$2"
    case "$text" in

      hola|Hola|/start|menu|Menu|0)
        do_menu "$cid" ;;

      1)  do_stats "$cid" ;;
      2)  do_ver_tokens "$cid" ;;

      3)
        STATE[$cid]="create_token"
        send_msg "$cid" "➕ *Crear Token Manual*

👤 Ingresa el nombre del usuario:" ;;

      4)
        STATE[$cid]="bulk_step1"
        send_msg "$cid" "🚀 *Crear Tokens Masivos*

👤 Nombre base (ej: \`alexa\`):" ;;

      5)  do_mini_tokens "$cid" ;;

      6)
        STATE[$cid]="multi_manual"
        TMPDATA["${cid}_lines"]=""
        send_msg "$cid" "✍️ *Multi Usuario Manual*

Formato: \`usuario token\` (una por mensaje)
Escribe *listo* al terminar o *cancel* para cancelar." ;;

      7)
        local cnt; cnt=$(q "SELECT COUNT(*) FROM tokens WHERE used=1")
        if [[ "$cnt" == "0" ]]; then
          send_msg "$cid" "✅ *No hay tokens usados.*
Escribe *hola* para ver el menú."
        else
          STATE[$cid]="delete_used"
          send_msg "$cid" "🗑️ *Eliminar Tokens Usados*

Se eliminarán *$cnt* tokens.
Escribe *ELIMINAR* para confirmar o *cancel* para cancelar."
        fi ;;

      8)
        local lista cnt=0
        lista="🔢 *LISTA DE USUARIOS*

"
        while IFS=$'\t' read -r user used; do
          ((cnt++))
          if [[ "$used" == "1" ]]; then
            lista+="*${cnt})* 🔴 \`${user}\`
"
          else
            lista+="*${cnt})* 🟢 \`${user}\`
"
          fi
        done < <(qs "SELECT user, used FROM tokens ORDER BY used DESC, user ASC")
        if [[ $cnt -eq 0 ]]; then
          send_msg "$cid" "❌ *No hay tokens registrados.*
Escribe *hola* para ver el menú."
        else
          STATE[$cid]="delete_by_idx"
          lista+="
Índices a eliminar (ej: \`1 3 5\` o \`2-5\`):"
          send_msg "$cid" "$lista"
        fi ;;

      9)  do_abuse "$cid" ;;

      10)
        local now cnt lista
        now=$(date +%s); cnt=0
        lista="🔓 *IPs BLOQUEADAS*

"
        while IFS=$'\t' read -r ip att until_ts; do
          ((cnt++))
          TMPDATA["${cid}_ip_${cnt}"]="$ip"
          lista+="*${cnt})* \`${ip}\` — ${att} intentos — hasta ${until_ts}
"
        done < <(qs "SELECT ip, attempts,
            datetime(blocked_until,'unixepoch','localtime')
            FROM rate_limit WHERE blocked_until > $now ORDER BY blocked_until DESC")
        if [[ $cnt -eq 0 ]]; then
          send_msg "$cid" "✅ *Ninguna IP bloqueada.*
Escribe *hola* para ver el menú."
        else
          TMPDATA["${cid}_ip_count"]=$cnt
          STATE[$cid]="unblock_ip"; STEP[$cid]=1
          lista+="
Número a desbloquear (0 = cancelar):"
          send_msg "$cid" "$lista"
        fi ;;

      11)
        STATE[$cid]="reset_token"
        send_msg "$cid" "🔄 *Resetear Token*

👤 Ingresa el nombre del usuario a resetear:" ;;

      12)
        if [[ ! -f "$DB" ]]; then
          send_msg "$cid" "❌ *No existe la DB.*"
        else
          mkdir -p "$BACKUP_DIR"
          local stamp bak t f u
          stamp=$(date +"%Y%m%d_%H%M%S")
          bak="$BACKUP_DIR/tokens_${stamp}.db"
          cp "$DB" "$bak"
          t=$(q "SELECT COUNT(*) FROM tokens")
          f=$(q "SELECT COUNT(*) FROM tokens WHERE used=0")
          u=$(q "SELECT COUNT(*) FROM tokens WHERE used=1")
          send_doc "$cid" "$bak" "💾 Backup — Total: $t | Libres: $f | Usados: $u"
          send_msg "$cid" "✅ *Backup creado y enviado!*
Escribe *hola* para ver el menú."
        fi ;;

      13)
        STATE[$cid]="restore_backup"; STEP[$cid]=1
        send_msg "$cid" "📥 *Restaurar Backup*

Envía el archivo *.db* de backup.
O escribe *cancel* para cancelar." ;;

      *)
        send_msg "$cid" "❓ *Opción no válida.*
Escribe *hola* para ver el menú." ;;
    esac
  }

  # ── Loop principal ────────────────────────────────────────────
  while true; do
    UPDATES=$(curl -s --max-time 20 "$URL/getUpdates?offset=$OFFSET&timeout=10" 2>/dev/null)
    [[ -z "$UPDATES" ]] && sleep 2 && continue

    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      OFFSET=$(echo "$row" | jq -r '.update_id // 0')
      OFFSET=$((OFFSET + 1))
      CHAT_ID=$(echo "$row" | jq -r '.message.chat.id // empty')
      [[ -z "$CHAT_ID" ]] && continue
      MSG_TEXT=$(echo "$row" | jq -r '.message.text // empty')
      DOC_ID=$(echo "$row"   | jq -r '.message.document.file_id // empty')

      if ! is_allowed "$CHAT_ID"; then
        curl -s -X POST "$URL/sendMessage" \
          -d "chat_id=$CHAT_ID" -d "text=⛔ No autorizado." >/dev/null
        continue
      fi

      if [[ -n "${STATE[$CHAT_ID]}" ]]; then
        handle_state "$CHAT_ID" "$MSG_TEXT" "$DOC_ID"
      else
        handle_cmd "$CHAT_ID" "$MSG_TEXT"
      fi
    done < <(echo "$UPDATES" | jq -c '.result[]?' 2>/dev/null)
  done

  exit 0
fi

# ══════════════════════════════════════════════════════════════
#  MODO INTERACTIVO (manager multiusuario)
# ══════════════════════════════════════════════════════════════
check_deps() {
  local miss=()
  command -v jq      &>/dev/null || miss+=("jq")
  command -v sqlite3 &>/dev/null || miss+=("sqlite3")
  command -v curl    &>/dev/null || miss+=("curl")
  if [[ ${#miss[@]} -gt 0 ]]; then
    echo -e "${GOLD}⚠️  Instalando dependencias: ${miss[*]}${RST}"
    command -v apt-get &>/dev/null && apt-get install -y -qq "${miss[@]}" 2>/dev/null
    if ! command -v jq &>/dev/null; then
      curl -sL -o /usr/bin/jq \
        "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
      chmod +x /usr/bin/jq
    fi
  fi
}

# ══════════════════════════════════════════════════════════════
#  INSTALL BACKEND — despliega check.php automáticamente
#  Se ejecuta al arrancar el manager. Si check.php ya existe
#  y está actualizado (mismo hash) no hace nada.
# ══════════════════════════════════════════════════════════════
install_backend() {
  local dest="${DB_BASE_DIR}/check.php"

  # Contenido del backend — heredoc con comillas para evitar expansión
  local php_content
  php_content='<?php
// ══════════════════════════════════════════════════════════════
//  check.php — Validador de tokens multiinstancia v2.2
//  Generado automáticamente por tokens-bot.sh
//
//  Respuestas:
//      OK           → token válido, activado correctamente
//      DENY         → token no existe
//      USED         → token existe pero ya fue consumido
//      BLOCKED      → IP bloqueada por rate limit
//      DISABLED     → instancia desactivada (toggle OFF)
//      SLUG_UNKNOWN → no existe db_{slug}.db
//      DB_ERROR     → error abriendo SQLite
// ══════════════════════════════════════════════════════════════

define("DB_BASE_DIR",   "/var/www/html");
define("RATE_LIMIT",    5);
define("BLOCK_TIME",    300);
define("ANTI_BF_DELAY", 150000);

$token = trim($_GET["token"] ?? "");
$slug  = trim($_GET["slug"]  ?? "");
$slug  = preg_replace("/[^a-zA-Z0-9_]/", "", $slug);

if ($token === "" || $slug === "") {
    http_response_code(400);
    die("DENY");
}

$dbfile = DB_BASE_DIR . "/db_{$slug}.db";
if (!file_exists($dbfile)) {
    die("SLUG_UNKNOWN");
}

usleep(ANTI_BF_DELAY);

try {
    $db = new SQLite3($dbfile, SQLITE3_OPEN_READWRITE);
    $db->busyTimeout(3000);
    $db->exec("PRAGMA journal_mode=WAL");
    $db->exec("PRAGMA synchronous=NORMAL");
} catch (Exception $e) {
    die("DB_ERROR");
}

$meta     = $db->query("SELECT enabled FROM instance_meta WHERE id=1");
$meta_row = $meta ? $meta->fetchArray(SQLITE3_ASSOC) : null;
if ($meta_row && (int)$meta_row["enabled"] === 0) {
    $db->close();
    die("DISABLED");
}

$ip = trim(
    explode(",", (
        $_SERVER["HTTP_X_FORWARDED_FOR"]
        ?? $_SERVER["HTTP_X_REAL_IP"]
        ?? $_SERVER["REMOTE_ADDR"]
        ?? "0.0.0.0"
    ))[0]
);
$now = time();

$stmt_rl = $db->prepare("SELECT attempts, blocked_until FROM rate_limit WHERE ip = :ip");
$stmt_rl->bindValue(":ip", $ip, SQLITE3_TEXT);
$rl = $stmt_rl->execute()->fetchArray(SQLITE3_ASSOC);

if ($rl && $rl["blocked_until"] > $now) {
    $db->close();
    http_response_code(429);
    die("BLOCKED");
}

$chk = $db->prepare("SELECT used FROM tokens WHERE token = :tok");
$chk->bindValue(":tok", $token, SQLITE3_TEXT);
$chk_row = $chk->execute()->fetchArray(SQLITE3_ASSOC);

if ($chk_row && (int)$chk_row["used"] === 1) {
    $db->close();
    die("USED");
}

$db->exec("BEGIN IMMEDIATE");

$upd = $db->prepare("
    UPDATE tokens SET used = 1, ip = :ip, used_at = :ts
    WHERE token = :tok AND used = 0
");
$upd->bindValue(":ip",  $ip,    SQLITE3_TEXT);
$upd->bindValue(":ts",  $now,   SQLITE3_INTEGER);
$upd->bindValue(":tok", $token, SQLITE3_TEXT);
$upd->execute();

if ($db->changes() === 0) {
    $db->exec("ROLLBACK");
    if ($rl) {
        $new_att = $rl["attempts"] + 1;
        $bu      = ($new_att >= RATE_LIMIT) ? $now + BLOCK_TIME : $rl["blocked_until"];
        $u = $db->prepare("UPDATE rate_limit SET attempts=:a,blocked_until=:b,last_attempt=:l WHERE ip=:ip");
        $u->bindValue(":a",  $new_att, SQLITE3_INTEGER);
        $u->bindValue(":b",  $bu,      SQLITE3_INTEGER);
        $u->bindValue(":l",  $now,     SQLITE3_INTEGER);
        $u->bindValue(":ip", $ip,      SQLITE3_TEXT);
        $u->execute();
    } else {
        $i = $db->prepare("INSERT INTO rate_limit (ip,attempts,blocked_until,last_attempt) VALUES(:ip,1,0,:l)");
        $i->bindValue(":ip", $ip,  SQLITE3_TEXT);
        $i->bindValue(":l",  $now, SQLITE3_INTEGER);
        $i->execute();
    }
    $db->close();
    die("DENY");
}

$db->exec("COMMIT");

$del = $db->prepare("DELETE FROM rate_limit WHERE ip = :ip");
$del->bindValue(":ip", $ip, SQLITE3_TEXT);
$del->execute();

$db->close();
die("OK");'

  # ── Hash del contenido nuevo ──────────────────────────────────
  local new_hash; new_hash=$(echo "$php_content" | md5sum | cut -d' ' -f1)

  # ── Si ya existe y es idéntico, no hacer nada ─────────────────
  if [[ -f "$dest" ]]; then
    local cur_hash; cur_hash=$(md5sum "$dest" | cut -d' ' -f1)
    if [[ "$new_hash" == "$cur_hash" ]]; then
      return  # Ya está actualizado, silencio total
    fi
    echo -e "${GOLD}⚠️  check.php desactualizado — actualizando...${RST}"
  else
    echo -e "${CYAN}📦 Instalando backend check.php...${RST}"
  fi

  # ── Escribir y permisar ───────────────────────────────────────
  mkdir -p "$DB_BASE_DIR"
  printf '%s\n' "$php_content" > "$dest"
  chown www-data:www-data "$dest" 2>/dev/null || true
  chmod 644 "$dest"

  echo -e "${GRN}✅ check.php instalado en ${dest}${RST}"
  sleep 1
}

# ── Helpers de instancia ──────────────────────────────────────
instance_conf()   { echo "${INSTANCES_DIR}/bot_${1}.conf"; }
instance_pid()    { echo "${INSTANCES_DIR}/bot_${1}.pid"; }
instance_db()     { echo "${DB_BASE_DIR}/db_${1}.db"; }
instance_backup() { echo "${BACKUP_BASE_DIR}/${1}"; }

instance_status() {
  local pidfile; pidfile=$(instance_pid "$1")
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "active"
  else
    rm -f "$pidfile" 2>/dev/null
    echo "inactive"
  fi
}

# ── Lee el flag enabled de la DB de una instancia ─────────────
instance_enabled() {
  local db_path; db_path=$(instance_db "$1")
  [[ ! -f "$db_path" ]] && echo "1" && return
  local val
  val=$(sqlite3 "$db_path" \
    "SELECT enabled FROM instance_meta WHERE id=1;" 2>/dev/null)
  echo "${val:-1}"
}

list_slugs() {
  for f in "${INSTANCES_DIR}"/bot_*.conf; do
    [[ -f "$f" ]] || continue
    local slug; slug=$(basename "$f" .conf)
    echo "${slug#bot_}"
  done
}

# ── Bootstrap: crea tablas si la DB no las tiene ──────────────
bootstrap_db() {
  local db="$1"
  sqlite3 "$db" <<'SQL'
CREATE TABLE IF NOT EXISTS tokens (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  token      TEXT    NOT NULL UNIQUE,
  user       TEXT    NOT NULL UNIQUE,
  used       INTEGER NOT NULL DEFAULT 0,
  ip         TEXT,
  used_at    INTEGER,
  created_at INTEGER,
  expires_at INTEGER
);
CREATE TABLE IF NOT EXISTS rate_limit (
  ip            TEXT    PRIMARY KEY,
  attempts      INTEGER NOT NULL DEFAULT 0,
  last_attempt  INTEGER,
  blocked_until INTEGER
);
CREATE TABLE IF NOT EXISTS instance_meta (
  id      INTEGER PRIMARY KEY CHECK (id = 1),
  enabled INTEGER NOT NULL DEFAULT 1
);
INSERT OR IGNORE INTO instance_meta (id, enabled) VALUES (1, 1);
SQL
  chown www-data:www-data "$db" 2>/dev/null || true
  chmod 660 "$db" 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════
#  OBSERVABILIDAD — Dashboard, actividad, métricas, auditoría
# ══════════════════════════════════════════════════════════════

# ── Dashboard global ─────────────────────────────────────────
do_dashboard_global() {
  clear
  local slugs=(); mapfile -t slugs < <(list_slugs)
  local now; now=$(date +%s)

  echo -e "${HOT}${BLD}╔══════════════════════════════════════════════╗${RST}"
  echo -e "${HOT}${BLD}║${RST}          ${MAG}${BLD}📊 DASHBOARD GLOBAL${RST}              ${HOT}${BLD}║${RST}"
  echo -e "${HOT}${BLD}╠══════════════════════════════════════════════╣${RST}"

  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo -e "${HOT}${BLD}║${RST}  ${GOLD}Sin instancias configuradas.${RST}"
    echo -e "${HOT}${BLD}╚══════════════════════════════════════════════╝${RST}"
    sleep 2; show_menu; return
  fi

  local g_total=0 g_used=0 g_free=0 g_ips=0 g_blocked=0

  for slug in "${slugs[@]}"; do
    local db_path; db_path=$(instance_db "$slug")
    [[ ! -f "$db_path" ]] && continue

    local t u f ips bl last_ts last_str st en
    t=$(sqlite3   "$db_path" "SELECT COUNT(*) FROM tokens;" 2>/dev/null || echo 0)
    u=$(sqlite3   "$db_path" "SELECT COUNT(*) FROM tokens WHERE used=1;" 2>/dev/null || echo 0)
    f=$((t - u))
    ips=$(sqlite3 "$db_path" "SELECT COUNT(DISTINCT ip) FROM tokens WHERE used=1 AND ip IS NOT NULL;" 2>/dev/null || echo 0)
    bl=$(sqlite3  "$db_path" "SELECT COUNT(*) FROM rate_limit WHERE blocked_until > ${now};" 2>/dev/null || echo 0)
    last_ts=$(sqlite3 "$db_path" "SELECT MAX(used_at) FROM tokens WHERE used=1 AND used_at IS NOT NULL;" 2>/dev/null || echo "")

    if [[ -n "$last_ts" && "$last_ts" != "NULL" ]]; then
      last_str=$(date -d "@${last_ts}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "—")
    else
      last_str="— sin uso —"
    fi

    st=$(instance_status "$slug")
    en=$(instance_enabled "$slug")
    local badge; badge="${GRN}●${RST}"
    [[ "$st" != "active" ]] && badge="${RED}○${RST}"
    [[ "$en"  == "0"     ]] && badge="${RED}⊗${RST}"

    g_total=$((g_total + t))
    g_used=$((g_used   + u))
    g_free=$((g_free   + f))
    g_ips=$((g_ips     + ips))
    g_blocked=$((g_blocked + bl))

    echo -e "${HOT}${BLD}║${RST} ${badge} ${BLD}${slug}${RST}"
    echo -e "${HOT}${BLD}║${RST}   💎 Total: ${GOLD}${t}${RST}  🟢 Libres: ${GRN}${f}${RST}  🔴 Usados: ${RED}${u}${RST}"
    echo -e "${HOT}${BLD}║${RST}   🌐 IPs únicas: ${CYAN}${ips}${RST}   🚫 Bloqueadas: ${RED}${bl}${RST}"
    echo -e "${HOT}${BLD}║${RST}   🕐 Último uso: ${PINK}${last_str}${RST}"
    echo -e "${HOT}${BLD}╠══════════════════════════════════════════════╣${RST}"
  done

  echo -e "${HOT}${BLD}║${RST}  ${MAG}${BLD}▸ TOTALES${RST}"
  echo -e "${HOT}${BLD}║${RST}  💎 Tokens: ${GOLD}${BLD}${g_total}${RST}   🌐 IPs únicas: ${CYAN}${g_ips}${RST}"
  echo -e "${HOT}${BLD}║${RST}  🟢 Libres: ${GRN}${BLD}${g_free}${RST}   🔴 Usados: ${RED}${BLD}${g_used}${RST}   🚫 Bloq: ${RED}${g_blocked}${RST}"
  echo -e "${HOT}${BLD}╚══════════════════════════════════════════════╝${RST}"
  echo ""
  echo -ne "${PINK}  [Enter] para volver al menú...${RST} "
  read -r
  show_menu
}

# ── Actividad detallada por instancia ────────────────────────
do_activity_instance() {
  local slugs=(); mapfile -t slugs < <(list_slugs)
  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo -e "${GOLD}⚠️  Sin instancias configuradas.${RST}"; sleep 1; show_menu; return
  fi

  clear
  echo -e "${HOT}${BLD}── 🔎 ACTIVIDAD POR INSTANCIA ──${RST}"
  echo ""
  local i=1
  for slug in "${slugs[@]}"; do
    local st; st=$(instance_status "$slug")
    local badge; badge="${RED}○${RST}"
    [[ "$st" == "active" ]] && badge="${GRN}●${RST}"
    echo -e "  ${GOLD}${i})${RST} ${badge} ${BLD}${slug}${RST}"
    ((i++))
  done
  echo -e "  ${PINK}0)${RST} Cancelar"
  echo ""
  echo -ne "${PINK}  Selecciona instancia: ${RST}"
  read -r sel

  if [[ "$sel" == "0" ]]; then show_menu; return; fi
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 || "$sel" -gt ${#slugs[@]} ]]; then
    echo -e "${RED}❌ Inválido.${RST}"; sleep 1; do_activity_instance; return
  fi

  local slug="${slugs[$((sel-1))]}"
  local db_path; db_path=$(instance_db "$slug")
  [[ ! -f "$db_path" ]] && { echo -e "${RED}❌ DB no encontrada.${RST}"; sleep 1; show_menu; return; }

  clear
  local t u f
  t=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM tokens;" 2>/dev/null || echo 0)
  u=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM tokens WHERE used=1;" 2>/dev/null || echo 0)
  f=$((t - u))

  echo -e "${HOT}${BLD}╔══════════════════════════════════════════════╗${RST}"
  printf "${HOT}${BLD}║${RST}  ${MAG}${BLD}🔎 ACTIVIDAD — %-30s${HOT}${BLD}║${RST}\n" "${slug}"
  echo -e "${HOT}${BLD}║${RST}  💎 Total: ${GOLD}${t}${RST}   🟢 Libres: ${GRN}${f}${RST}   🔴 Usados: ${RED}${u}${RST}"
  echo -e "${HOT}${BLD}╚══════════════════════════════════════════════╝${RST}"
  echo ""

  if [[ "$u" -gt 0 ]]; then
    echo -e "  ${RED}${BLD}── TOKENS USADOS (últimos 30, más reciente primero) ──${RST}"
    echo ""
    while IFS=$'\t' read -r user tok ip used_str created_str; do
      echo -e "  ${RED}🔴${RST} ${BLD}${user}${RST}"
      echo -e "     Token:   ${CYAN}${tok}${RST}"
      echo -e "     IP:      ${GOLD}${ip}${RST}"
      echo -e "     Usado:   ${RED}${used_str}${RST}"
      echo -e "     Creado:  ${PINK}${created_str}${RST}"
      echo -e "     ${HOT}─────────────────────────────────────${RST}"
    done < <(sqlite3 -separator $'\t' "$db_path" \
      "SELECT user, token,
       COALESCE(ip,'—'),
       CASE WHEN used_at IS NOT NULL
            THEN datetime(used_at,'unixepoch','localtime') ELSE '—' END,
       CASE WHEN created_at IS NOT NULL
            THEN datetime(created_at,'unixepoch','localtime') ELSE '—' END
       FROM tokens WHERE used=1
       ORDER BY used_at DESC LIMIT 30;" 2>/dev/null)
    echo ""
  fi

  if [[ "$f" -gt 0 ]]; then
    echo -e "  ${GRN}${BLD}── TOKENS LIBRES ──${RST}"
    echo ""
    while IFS=$'\t' read -r user tok created_str; do
      echo -e "  ${GRN}🟢${RST} ${BLD}${user}${RST}   ${CYAN}${tok}${RST}   ${PINK}(${created_str})${RST}"
    done < <(sqlite3 -separator $'\t' "$db_path" \
      "SELECT user, token,
       CASE WHEN created_at IS NOT NULL
            THEN datetime(created_at,'unixepoch','localtime') ELSE '—' END
       FROM tokens WHERE used=0
       ORDER BY user ASC LIMIT 50;" 2>/dev/null)
    echo ""
  fi

  [[ "$t" -eq 0 ]] && echo -e "  ${GOLD}Sin tokens registrados.${RST}"
  echo -ne "${PINK}  [Enter] para volver...${RST} "
  read -r
  show_menu
}

# ── IPs sospechosas globales ──────────────────────────────────
do_suspicious_ips_global() {
  clear
  local slugs=(); mapfile -t slugs < <(list_slugs)
  local now; now=$(date +%s)

  echo -e "${HOT}${BLD}╔══════════════════════════════════════════════╗${RST}"
  echo -e "${HOT}${BLD}║${RST}      ${RED}${BLD}🚨 IPs SOSPECHOSAS — GLOBAL${RST}           ${HOT}${BLD}║${RST}"
  echo -e "${HOT}${BLD}╚══════════════════════════════════════════════╝${RST}"
  echo ""

  local found_abuse=0
  echo -e "  ${RED}${BLD}── MULTI-TOKEN POR IP ──${RST}"
  echo ""
  for slug in "${slugs[@]}"; do
    local db_path; db_path=$(instance_db "$slug")
    [[ ! -f "$db_path" ]] && continue
    local has_rows=0
    while IFS=$'\t' read -r ip cnt users last_ts; do
      [[ $has_rows -eq 0 ]] && echo -e "  ${MAG}${BLD}[${slug}]${RST}" && has_rows=1
      local last_str; last_str=$(date -d "@${last_ts}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "—")
      echo -e "    ${RED}⚠️  IP: ${CYAN}${ip}${RST}  —  ${RED}${BLD}${cnt} usos${RST}"
      echo -e "       Usuarios: ${GOLD}${users}${RST}"
      echo -e "       Último:   ${PINK}${last_str}${RST}"
      ((found_abuse++))
    done < <(sqlite3 -separator $'\t' "$db_path" \
      "SELECT ip, COUNT(*) as c, GROUP_CONCAT(user,', '), MAX(used_at)
       FROM tokens WHERE used=1 AND ip IS NOT NULL
       GROUP BY ip HAVING c > 1 ORDER BY c DESC;" 2>/dev/null)
  done
  [[ $found_abuse -eq 0 ]] && echo -e "  ${GRN}✅ Sin IPs con múltiples tokens.${RST}"

  echo ""
  local found_blocked=0
  echo -e "  ${RED}${BLD}── IPs BLOQUEADAS POR RATE LIMIT ──${RST}"
  echo ""
  for slug in "${slugs[@]}"; do
    local db_path; db_path=$(instance_db "$slug")
    [[ ! -f "$db_path" ]] && continue
    local has_rows=0
    while IFS=$'\t' read -r ip att until_ts; do
      [[ $has_rows -eq 0 ]] && echo -e "  ${MAG}${BLD}[${slug}]${RST}" && has_rows=1
      local until_str; until_str=$(date -d "@${until_ts}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "—")
      echo -e "    ${RED}🚫 IP: ${CYAN}${ip}${RST}  —  ${RED}${att} intentos${RST}  —  hasta ${GOLD}${until_str}${RST}"
      ((found_blocked++))
    done < <(sqlite3 -separator $'\t' "$db_path" \
      "SELECT ip, attempts, blocked_until FROM rate_limit
       WHERE blocked_until > ${now} ORDER BY blocked_until DESC;" 2>/dev/null)
  done
  [[ $found_blocked -eq 0 ]] && echo -e "  ${GRN}✅ Sin IPs bloqueadas.${RST}"

  echo ""
  echo -ne "${PINK}  [Enter] para volver...${RST} "
  read -r
  show_menu
}

# ── Últimos tokens usados (feed cross-instancia) ─────────────
do_last_used_tokens() {
  clear
  local slugs=(); mapfile -t slugs < <(list_slugs)

  echo -e "${HOT}${BLD}╔══════════════════════════════════════════════╗${RST}"
  echo -e "${HOT}${BLD}║${RST}       ${GRN}${BLD}📈 ÚLTIMOS TOKENS USADOS${RST}           ${HOT}${BLD}║${RST}"
  echo -e "${HOT}${BLD}╚══════════════════════════════════════════════╝${RST}"
  echo ""

  local tmpfile; tmpfile="/tmp/lastused_$(date +%s).txt"

  for slug in "${slugs[@]}"; do
    local db_path; db_path=$(instance_db "$slug")
    [[ ! -f "$db_path" ]] && continue
    sqlite3 -separator $'\t' "$db_path" \
      "SELECT used_at, '${slug}', user, token, COALESCE(ip,'—')
       FROM tokens WHERE used=1 AND used_at IS NOT NULL
       ORDER BY used_at DESC LIMIT 20;" 2>/dev/null >> "$tmpfile"
  done

  if [[ ! -s "$tmpfile" ]]; then
    echo -e "  ${GOLD}Sin actividad registrada en ninguna instancia.${RST}"
    rm -f "$tmpfile"
    echo ""
    echo -ne "${PINK}  [Enter] para volver...${RST} "
    read -r
    show_menu; return
  fi

  local count=0
  while IFS=$'\t' read -r ts slug user tok ip; do
    ((count++))
    local ts_str; ts_str=$(date -d "@${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "—")
    echo -e "  ${RED}🔴${RST}  ${GOLD}${BLD}[${slug}]${RST} ${BLD}${user}${RST}"
    echo -e "       Token: ${CYAN}${tok}${RST}"
    echo -e "       IP:    ${GOLD}${ip}${RST}"
    echo -e "       Fecha: ${PINK}${ts_str}${RST}"
    echo ""
  done < <(sort -t$'\t' -k1 -rn "$tmpfile" | head -30)

  rm -f "$tmpfile"

  echo -e "  ${CYAN}(últimos ${count} usos en todas las instancias)${RST}"
  echo ""
  echo -ne "${PINK}  [Enter] para volver...${RST} "
  read -r
  show_menu
}

# ══════════════════════════════════════════════════════════════
#  MENÚ PRINCIPAL — solo instancias ACTIVAS visibles
#  Las inactivas siguen existiendo (.conf intacto) y pueden
#  reactivarse desde opción 1 (Crear / Reconfigurar).
# ══════════════════════════════════════════════════════════════
show_menu() {
  clear
  mkdir -p "$INSTANCES_DIR"

  echo -e "${HOT}${BLD}╔══════════════════════════════════════════════╗${RST}"
  echo -e "${HOT}${BLD}║${RST}  ${MAG}${BLD}🤖 TOKENS BOT — TELEGRAM v2.1 MULTI${RST}        ${HOT}${BLD}║${RST}"
  echo -e "${HOT}${BLD}╠══════════════════════════════════════════════╣${RST}"

  local slugs=(); mapfile -t slugs < <(list_slugs)
  local active_count=0 inactive_count=0

  # ── Contar inactivas (para el hint) ──
  for slug in "${slugs[@]}"; do
    if [[ $(instance_status "$slug") == "active" ]]; then
      ((active_count++))
    else
      ((inactive_count++))
    fi
  done

  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo -e "${HOT}${BLD}║${RST}  ${GOLD}Sin instancias configuradas.${RST}"
  elif [[ $active_count -eq 0 ]]; then
    echo -e "${HOT}${BLD}║${RST}  ${GOLD}No hay instancias activas en este momento.${RST}"
    if [[ $inactive_count -gt 0 ]]; then
      echo -e "${HOT}${BLD}║${RST}  ${CYAN}(${inactive_count} detenida(s) — usa opción 1 para reactivar)${RST}"
    fi
  else
    # ── Solo mostrar las ACTIVAS ──
    echo -e "${HOT}${BLD}║${RST}  ${GRN}${BLD}▸ INSTANCIAS ACTIVAS${RST}"
    for slug in "${slugs[@]}"; do
      [[ $(instance_status "$slug") == "active" ]] || continue
      local pidfile; pidfile=$(instance_pid "$slug")
      local pid_str=" (PID: $(cat "$pidfile"))"
      local en; en=$(instance_enabled "$slug")
      local en_badge=""
      [[ "$en" == "0" ]] && en_badge="  ${RED}[TOKENS OFF]${RST}"
      echo -e "${HOT}${BLD}║${RST}    ${GRN}●${RST} ${BLD}${slug}${RST}${GRN}${pid_str}${RST}${en_badge}"
    done
    # ── Hint discreto si hay inactivas ──
    if [[ $inactive_count -gt 0 ]]; then
      echo -e "${HOT}${BLD}║${RST}  ${CYAN}(${inactive_count} instancia(s) detenida(s) — opción 1 para reactivar)${RST}"
    fi
  fi

echo ""
echo -e " ${HOT}─────────────────────────────────────${RST}"
echo ""

echo -e "   ${GRN}1)${RST} ➕  Crear / Reconfigurar instancia"
echo -e "   ${RED}2)${RST} 🔴  Detener instancia"
echo -e "   ${GOLD}3)${RST} 🛑  Detener TODAS las instancias"
echo -e "   ${MAG}4)${RST} 🗑️   Eliminar instancia"
echo -e "   ${CYAN}5)${RST} 🔌  Activar / Desactivar tokens"

echo ""
echo -e " ${HOT}─────────────────────────────────────${RST}"
echo ""

echo -e "   ${GOLD}6)${RST} 📊  Dashboard global"
echo -e "   ${MAG}7)${RST} 🔎  Actividad por instancia"
echo -e "   ${RED}8)${RST} 🚨  IPs sospechosas"
echo -e "   ${GRN}9)${RST} 📈  Últimos tokens usados"

echo ""
echo -e " ${HOT}─────────────────────────────────────${RST}"
echo ""

echo -e "   ${PINK}0)${RST} 🚪  Salir"

echo ""
echo -ne "${PINK} Opción:${RST} "
read -r OPT

case "$OPT" in
  1) do_activate ;;
  2) do_stop_one ;;
  3) do_stop_all ;;
  4) do_delete_instance ;;
  5) do_toggle_instance ;;
  6) do_dashboard_global ;;
  7) do_activity_instance ;;
  8) do_suspicious_ips_global ;;
  9) do_last_used_tokens ;;
  0) exit 0 ;;
  *)
    echo -e "${RED}❌ Opción inválida.${RST}"
    sleep 1
    show_menu
    ;;
esac

# ── Crear / Reconfigurar instancia ────────────────────────────
do_activate() {
  echo ""
  echo -e "${HOT}${BLD}── NUEVA / RECONFIGURAR INSTANCIA ──${RST}"
  echo ""

  # ── Mostrar instancias detenidas disponibles para reactivar ──
  local slugs=(); mapfile -t slugs < <(list_slugs)
  local inactive_slugs=()
  for slug in "${slugs[@]}"; do
    [[ $(instance_status "$slug") == "inactive" ]] && inactive_slugs+=("$slug")
  done
  if [[ ${#inactive_slugs[@]} -gt 0 ]]; then
    echo -e "${CYAN}💤 Instancias detenidas (puedes reactivar escribiendo su nombre):${RST}"
    for s in "${inactive_slugs[@]}"; do
      echo -e "   ${GOLD}→ ${s}${RST}"
    done
    echo ""
  fi

  echo -e "${CYAN}ℹ️  El slug identifica la instancia (letras, números, guion bajo).${RST}"
  echo -e "${CYAN}   Ejemplo: pepe, juan, tienda1${RST}"
  echo -ne "${PINK}👉 Nombre de la instancia (slug): ${RST}"
  read -r in_slug
  in_slug="${in_slug//[^a-zA-Z0-9_]/}"
  if [[ -z "$in_slug" ]]; then
    echo -e "${RED}❌ Slug requerido.${RST}"; sleep 1; show_menu; return
  fi

  local conf_file; conf_file=$(instance_conf  "$in_slug")
  local pid_file;  pid_file=$(instance_pid    "$in_slug")
  local db_path;   db_path=$(instance_db      "$in_slug")
  local bak_dir;   bak_dir=$(instance_backup  "$in_slug")

  local ex_tok="" ex_ids="" ex_name=""
  if [[ -f "$conf_file" ]]; then
    ex_tok=$(grep  "^TOKEN="      "$conf_file" | cut -d= -f2)
    ex_ids=$(grep  "^USER_IDS="  "$conf_file" | cut -d= -f2 | tr ' ' ',')
    ex_name=$(grep "^ADMIN_NAME=" "$conf_file" | cut -d= -f2)
    echo -e "${CYAN}ℹ️  Config anterior encontrada para '${in_slug}' (Enter = conservar)${RST}"
  fi
  echo ""

  echo -ne "${PINK}👉 Token del bot (BotFather)${ex_tok:+ [Enter=conservar]}: ${RST}"
  read -r in_tok
  [[ -z "$in_tok" && -n "$ex_tok" ]] && in_tok="$ex_tok"
  if [[ -z "$in_tok" ]]; then
    echo -e "${RED}❌ Token requerido.${RST}"; sleep 1; show_menu; return
  fi

  echo -ne "${PINK}👉 IDs Telegram permitidos${ex_ids:+ [Enter=${ex_ids}]}: ${RST}"
  echo -e "${CYAN}   (separados por coma, ej: 123456789,987654321)${RST}"
  echo -ne "   → "
  read -r in_ids
  [[ -z "$in_ids" && -n "$ex_ids" ]] && in_ids="$ex_ids"
  if [[ -z "$in_ids" ]]; then
    echo -e "${RED}❌ Al menos 1 ID requerido.${RST}"; sleep 1; show_menu; return
  fi
  in_ids="${in_ids//[[:space:]]/}"

  echo -ne "${PINK}👉 Nombre del admin${ex_name:+ [Enter=${ex_name}]}: ${RST}"
  read -r in_name
  [[ -z "$in_name" && -n "$ex_name" ]] && in_name="$ex_name"
  [[ -z "$in_name" ]] && in_name="Admin"

  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo -e "${GOLD}⚠️  Deteniendo instancia anterior de '${in_slug}'...${RST}"
    kill -9 "$(cat "$pid_file")" 2>/dev/null; sleep 1
    rm -f "$pid_file"
  fi

  mkdir -p "$INSTANCES_DIR"
  cat > "$conf_file" <<EOF
TOKEN=$in_tok
USER_IDS=${in_ids//,/ }
ADMIN_NAME=$in_name
DB=$db_path
BACKUP_DIR=$bak_dir
EOF

  mkdir -p "$bak_dir"
  bootstrap_db "$db_path"

  # Si la instancia estaba desactivada, la reactivamos al reconfigurar
  sqlite3 "$db_path" "UPDATE instance_meta SET enabled=1 WHERE id=1;" 2>/dev/null || true

  nohup bash "$SCRIPT_PATH" --daemon \
    "$in_tok" "$in_ids" "$in_name" "$db_path" "$bak_dir" \
    >/dev/null 2>&1 &
  echo $! > "$pid_file"

  echo ""
  echo -e "${GRN}${BLD}✅ Instancia '${in_slug}' activada! (PID: $(cat "$pid_file"))${RST}"
  echo -e "${GOLD}   DB      : ${db_path}${RST}"
  echo -e "${GOLD}   Backups : ${bak_dir}${RST}"
  echo -e "${GOLD}   IDs     : ${in_ids}${RST}"
  echo -e "${CYAN}💡 Escribe 'hola' en Telegram para ver el menú.${RST}"
  sleep 2; show_menu
}

# ── Detener una instancia específica ─────────────────────────
do_stop_one() {
  local slugs=(); mapfile -t slugs < <(list_slugs)
  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo -e "${GOLD}⚠️  No hay instancias configuradas.${RST}"; sleep 1; show_menu; return
  fi

  # ── Solo mostrar activas para detener ──
  local active_slugs=()
  for slug in "${slugs[@]}"; do
    [[ $(instance_status "$slug") == "active" ]] && active_slugs+=("$slug")
  done

  if [[ ${#active_slugs[@]} -eq 0 ]]; then
    echo -e "${GOLD}⚠️  No hay instancias activas para detener.${RST}"; sleep 1; show_menu; return
  fi

  echo ""
  echo -e "${HOT}${BLD}── DETENER INSTANCIA ──${RST}"
  echo ""
  local i=1
  for slug in "${active_slugs[@]}"; do
    local pidfile; pidfile=$(instance_pid "$slug")
    echo -e "  ${GRN}${i})${RST} ${BLD}${slug}${RST} ${GRN}(PID: $(cat "$pidfile"))${RST}"
    ((i++))
  done
  echo -e "  ${PINK}0)${RST} Cancelar"
  echo ""
  echo -ne "${PINK}  Número a detener: ${RST}"
  read -r sel

  if [[ "$sel" == "0" ]]; then show_menu; return; fi
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 || "$sel" -gt ${#active_slugs[@]} ]]; then
    echo -e "${RED}❌ Selección inválida.${RST}"; sleep 1; do_stop_one; return
  fi

  local slug="${active_slugs[$((sel-1))]}"
  local pid_file; pid_file=$(instance_pid "$slug")
  local pid; pid=$(cat "$pid_file")
  kill -9 "$pid" 2>/dev/null
  rm -f "$pid_file"
  echo -e "${RED}🔴 Instancia '${slug}' detenida. (PID: $pid)${RST}"
  sleep 1; show_menu
}

# ── Detener TODAS ─────────────────────────────────────────────
do_stop_all() {
  local slugs=(); mapfile -t slugs < <(list_slugs)
  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo -e "${GOLD}⚠️  No hay instancias configuradas.${RST}"; sleep 1; show_menu; return
  fi

  echo ""
  echo -e "${GOLD}⚠️  Deteniendo todas las instancias...${RST}"
  local stopped=0
  for slug in "${slugs[@]}"; do
    local pid_file; pid_file=$(instance_pid "$slug")
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
      local pid; pid=$(cat "$pid_file")
      kill -9 "$pid" 2>/dev/null
      rm -f "$pid_file"
      echo -e "  ${RED}🔴 '${slug}' detenido (PID: $pid)${RST}"
      ((stopped++))
    else
      rm -f "$pid_file" 2>/dev/null
    fi
  done
  echo ""
  echo -e "${GRN}✅ Listo. ${stopped} instancia(s) detenida(s).${RST}"
  sleep 2; show_menu
}

# ══════════════════════════════════════════════════════════════
#  ELIMINAR INSTANCIA — mata PID + borra .conf + .pid
#  Pregunta por separado si también borrar DB y backups
# ══════════════════════════════════════════════════════════════
do_delete_instance() {
  local slugs=(); mapfile -t slugs < <(list_slugs)
  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo -e "${GOLD}⚠️  No hay instancias configuradas.${RST}"; sleep 1; show_menu; return
  fi

  echo ""
  echo -e "${HOT}${BLD}── ELIMINAR INSTANCIA ──${RST}"
  echo -e "${RED}  Esta acción elimina la configuración de la instancia.${RST}"
  echo -e "${RED}  Opcionalmente también puede borrar la DB y los backups.${RST}"
  echo ""

  local i=1
  for slug in "${slugs[@]}"; do
    local st; st=$(instance_status "$slug")
    if [[ "$st" == "active" ]]; then
      echo -e "  ${GRN}${i})${RST} ${BLD}${slug}${RST} ${GRN}[ACTIVO]${RST}"
    else
      echo -e "  ${RED}${i})${RST} ${BLD}${slug}${RST} ${RED}[INACTIVO]${RST}"
    fi
    ((i++))
  done
  echo -e "  ${PINK}0)${RST} Cancelar"
  echo ""
  echo -ne "${PINK}  Número a eliminar: ${RST}"
  read -r sel

  if [[ "$sel" == "0" ]]; then show_menu; return; fi
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 || "$sel" -gt ${#slugs[@]} ]]; then
    echo -e "${RED}❌ Selección inválida.${RST}"; sleep 1; do_delete_instance; return
  fi

  local slug="${slugs[$((sel-1))]}"
  local conf_file; conf_file=$(instance_conf  "$slug")
  local pid_file;  pid_file=$(instance_pid    "$slug")
  local db_path;   db_path=$(instance_db      "$slug")
  local bak_dir;   bak_dir=$(instance_backup  "$slug")

  echo ""
  echo -e "${GOLD}  Instancia seleccionada: ${BLD}${slug}${RST}"
  echo ""

  # ── Confirmar eliminación ──
  echo -ne "${RED}  ¿Eliminar configuración de '${slug}'? (escribe ELIMINAR): ${RST}"
  read -r confirm
  if [[ "$confirm" != "ELIMINAR" ]]; then
    echo -e "${GOLD}🛡️  Cancelado.${RST}"; sleep 1; show_menu; return
  fi

  # ── Matar daemon si corre ──
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    local pid; pid=$(cat "$pid_file")
    kill -9 "$pid" 2>/dev/null
    echo -e "  ${RED}🔴 Daemon detenido (PID: $pid)${RST}"
  fi

  # ── Borrar .pid y .conf ──
  rm -f "$pid_file" "$conf_file"
  echo -e "  ${GRN}✅ .pid y .conf eliminados${RST}"

  # ── Preguntar por DB ──
  echo ""
  if [[ -f "$db_path" ]]; then
    echo -ne "${PINK}  ¿Borrar también la DB (${db_path})? [s/N]: ${RST}"
    read -r del_db
    if [[ "${del_db,,}" == "s" ]]; then
      rm -f "$db_path"
      echo -e "  ${GRN}✅ DB eliminada${RST}"
    else
      echo -e "  ${GOLD}  DB conservada en ${db_path}${RST}"
    fi
  fi

  # ── Preguntar por backups ──
  if [[ -d "$bak_dir" ]]; then
    local nbak; nbak=$(find "$bak_dir" -name "*.db" 2>/dev/null | wc -l)
    if [[ $nbak -gt 0 ]]; then
      echo -ne "${PINK}  ¿Borrar también los backups (${nbak} archivos en ${bak_dir})? [s/N]: ${RST}"
      read -r del_bak
      if [[ "${del_bak,,}" == "s" ]]; then
        rm -rf "$bak_dir"
        echo -e "  ${GRN}✅ Backups eliminados${RST}"
      else
        echo -e "  ${GOLD}  Backups conservados en ${bak_dir}${RST}"
      fi
    fi
  fi

  echo ""
  echo -e "${GRN}${BLD}✅ Instancia '${slug}' eliminada del manager.${RST}"
  sleep 2; show_menu
}

# ══════════════════════════════════════════════════════════════
#  ACTIVAR / DESACTIVAR TOKENS DE UNA INSTANCIA
#  Solo cambia instance_meta.enabled en la DB.
#  No toca el daemon, no borra nada, no cambia configs.
#  check.php lee este flag antes de validar cualquier token.
# ══════════════════════════════════════════════════════════════
do_toggle_instance() {
  local slugs=(); mapfile -t slugs < <(list_slugs)
  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo -e "${GOLD}⚠️  No hay instancias configuradas.${RST}"; sleep 1; show_menu; return
  fi

  echo ""
  echo -e "${HOT}${BLD}── ACTIVAR / DESACTIVAR TOKENS ──${RST}"
  echo -e "${CYAN}  Bloquea o habilita todos los tokens de una instancia${RST}"
  echo -e "${CYAN}  sin detener el bot ni borrar ningún dato.${RST}"
  echo ""

  local i=1
  for slug in "${slugs[@]}"; do
    local en; en=$(instance_enabled "$slug")
    local st_label
    if [[ "$en" == "1" ]]; then
      st_label="${GRN}[TOKENS ON  ✅]${RST}"
    else
      st_label="${RED}[TOKENS OFF 🔌]${RST}"
    fi
    echo -e "  ${GOLD}${i})${RST} ${BLD}${slug}${RST}  ${st_label}"
    ((i++))
  done
  echo -e "  ${PINK}0)${RST} Cancelar"
  echo ""
  echo -ne "${PINK}  Número a cambiar: ${RST}"
  read -r sel

  if [[ "$sel" == "0" ]]; then show_menu; return; fi
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 || "$sel" -gt ${#slugs[@]} ]]; then
    echo -e "${RED}❌ Selección inválida.${RST}"; sleep 1; do_toggle_instance; return
  fi

  local slug="${slugs[$((sel-1))]}"
  local db_path; db_path=$(instance_db "$slug")

  if [[ ! -f "$db_path" ]]; then
    echo -e "${RED}❌ DB no encontrada para '${slug}'.${RST}"; sleep 1; show_menu; return
  fi

  # Asegurar que instance_meta exista (DBs antiguas sin migrar)
  sqlite3 "$db_path" <<'SQL' 2>/dev/null
CREATE TABLE IF NOT EXISTS instance_meta (
  id      INTEGER PRIMARY KEY CHECK (id = 1),
  enabled INTEGER NOT NULL DEFAULT 1
);
INSERT OR IGNORE INTO instance_meta (id, enabled) VALUES (1, 1);
SQL

  local cur_enabled
  cur_enabled=$(sqlite3 "$db_path" "SELECT enabled FROM instance_meta WHERE id=1;")

  echo ""
  if [[ "$cur_enabled" == "1" ]]; then
    echo -ne "${RED}  ¿Desactivar tokens de '${slug}'? check.php devolverá DENY. [s/N]: ${RST}"
    read -r conf
    if [[ "${conf,,}" == "s" ]]; then
      sqlite3 "$db_path" "UPDATE instance_meta SET enabled=0 WHERE id=1;"
      echo ""
      echo -e "${RED}${BLD}🔌 '${slug}' DESACTIVADO — todos sus tokens devolverán DENY.${RST}"
    else
      echo -e "${GOLD}🛡️  Cancelado. Sin cambios.${RST}"
    fi
  else
    echo -ne "${GRN}  ¿Reactivar tokens de '${slug}'? [s/N]: ${RST}"
    read -r conf
    if [[ "${conf,,}" == "s" ]]; then
      sqlite3 "$db_path" "UPDATE instance_meta SET enabled=1 WHERE id=1;"
      echo ""
      echo -e "${GRN}${BLD}✅ '${slug}' ACTIVADO — tokens válidos de nuevo.${RST}"
    else
      echo -e "${GOLD}🛡️  Cancelado. Sin cambios.${RST}"
    fi
  fi

  sleep 2; show_menu
}

# ── Entry point ───────────────────────────────────────────────
check_deps
install_backend
show_menu
