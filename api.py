from flask import Flask, jsonify
import sqlite3
from datetime import datetime, timedelta, timezone

DB_PATH = '/root/telegram-bot/keys.db'
app = Flask(__name__)

def validar_key(clave):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    # Buscar la key
    cursor.execute("SELECT fecha_creacion, usado, expirado FROM keys WHERE key = ?", (clave,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return {"valida": False, "motivo": "KEY no encontrada"}
    fecha_creacion, usado, expirado = row
    fecha_creacion = datetime.fromisoformat(fecha_creacion)
    # Revisar si está usada, expirada o pasada de tiempo
    if usado:
        conn.close()
        return {"valida": False, "motivo": "KEY ya usada"}
    if expirado:
        conn.close()
        return {"valida": False, "motivo": "KEY expirada"}
    if datetime.now(timezone.utc) - fecha_creacion > timedelta(hours=3):
        cursor.execute("UPDATE keys SET expirado = 1 WHERE key = ?", (clave,))
        conn.commit()
        conn.close()
        return {"valida": False, "motivo": "KEY expirada (auto)"}
    # Marcar como usada
    cursor.execute("UPDATE keys SET usado = 1 WHERE key = ?", (clave,))
    conn.commit()
    conn.close()
    return {"valida": True, "motivo": "KEY válida"}

@app.route('/validate/<path:key>')
def validate(key):
    return jsonify(validar_key(key))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=40412)
