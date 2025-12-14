#!/usr/bin/env python3

import socket
import threading
import sys

if len(sys.argv) < 4:
    print("Uso: python3 proxy.py <puerto_proxy> <puerto_destino> <response_code>")
    sys.exit(1)

listen_port = int(sys.argv[1])
target_port = int(sys.argv[2])
response_code = sys.argv[3]

def pipe(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.send(data)
    except:
        pass
    finally:
        src.close()
        dst.close()

def handle(conn, addr):
    try:
        data = conn.recv(4096)
        if not data:
            conn.close()
            return

        host = ''
        for line in data.decode(errors='ignore').split('\r\n'):
            if line.lower().startswith('host:'):
                host = line.split(':', 1)[1].strip()
                break

        if not host:
            conn.close()
            return

        target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target.connect(('127.0.0.1', target_port))

        if response_code == '101':
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n\r\n"
            )
            conn.send(response.encode())

        target.send(data)

        threading.Thread(target=pipe, args=(conn, target)).start()
        threading.Thread(target=pipe, args=(target, conn)).start()
    except Exception as e:
        conn.close()

def start():
    print(f"[+] Proxy activo en puerto {listen_port} → {target_port} con respuesta {response_code}")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', listen_port))
    server.listen(100)
    while True:
        conn, addr = server.accept()
        threading.Thread(target=handle, args=(conn, addr)).start()

if __name__ == "__main__":
    start()
