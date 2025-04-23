#!/usr/bin/env python3
"""
proxy.py - Un proxy TCP avanzado con soporte para WebSocket.

Este script crea un proxy que escucha en un puerto especificado y redirige el tráfico
a un puerto destino en localhost. Soporta respuestas WebSocket (código 101) y está diseñado
para ser robusto, con logging detallado y manejo de errores.

Uso:
    python3 proxy.py <puerto_proxy> <puerto_destino> <response_code>

Ejemplo:
    python3 proxy.py 80 444 101
"""

import socket
import threading
import sys
import logging
import signal
import time
from typing import Tuple, Optional

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("proxy.log")
    ]
)
logger = logging.getLogger(__name__)

class ProxyConfig:
    """Clase para almacenar la configuración del proxy."""
    def __init__(self, listen_port: int, target_port: int, response_code: str):
        self.listen_host = "0.0.0.0"  # Escuchar en todas las interfaces
        self.target_host = "127.0.0.1"  # Destino fijo (localhost)
        self.listen_port = listen_port
        self.target_port = target_port
        self.response_code = response_code
        self.backlog = 100  # Máximo de conexiones en cola
        self.buffer_size = 4096  # Tamaño del buffer para recv/send
        self.timeout = 10  # Timeout para conexiones (segundos)

class ProxyServer:
    """Clase principal del proxy."""
    def __init__(self, config: ProxyConfig):
        self.config = config
        self.server_socket: Optional[socket.socket] = None
        self.running = False

    def validate_config(self) -> None:
        """Valida la configuración del proxy."""
        if not (1 <= self.config.listen_port <= 65535):
            raise ValueError(f"Puerto de escucha {self.config.listen_port} fuera de rango (1-65535).")
        if not (1 <= self.config.target_port <= 65535):
            raise ValueError(f"Puerto destino {self.config.target_port} fuera de rango (1-65535).")
        if self.config.response_code not in ["101", "none"]:
            raise ValueError(f"Código de respuesta {self.config.response_code} no soportado. Usa '101' o 'none'.")

    def setup_socket(self) -> None:
        """Configura el socket del servidor."""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.settimeout(self.config.timeout)
        try:
            self.server_socket.bind((self.config.listen_host, self.config.listen_port))
            self.server_socket.listen(self.config.backlog)
            logger.info(
                f"Proxy activo en {self.config.listen_host}:{self.config.listen_port}, "
                f"redirigiendo a {self.config.target_host}:{self.config.target_port} "
                f"(respuesta: {self.config.response_code})"
            )
        except socket.error as e:
            logger.error(f"Error al iniciar el servidor: {e}")
            raise

    def handle_client(self, client_sock: socket.socket, addr: Tuple[str, int]) -> None:
        """Maneja una conexión de cliente."""
        logger.info(f"Nueva conexión desde {addr[0]}:{addr[1]}")
        client_sock.settimeout(self.config.timeout)

        try:
            # Recibir datos del cliente
            data = client_sock.recv(self.config.buffer_size)
            if not data:
                logger.warning(f"Conexión vacía desde {addr[0]}:{addr[1]}")
                client_sock.close()
                return

            # Extraer el encabezado Host (para logging)
            host = self.extract_host(data)
            logger.debug(f"Encabezado Host: {host}")

            # Conectar al destino
            target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_sock.settimeout(self.config.timeout)
            target_sock.connect((self.config.target_host, self.config.target_port))
            logger.debug(f"Conectado al destino {self.config.target_host}:{self.config.target_port}")

            # Enviar respuesta WebSocket si es necesario
            if self.config.response_code == "101":
                response = (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    "\r\n"
                )
                client_sock.send(response.encode())
                logger.debug("Enviada respuesta WebSocket (101 Switching Protocols)")

            # Enviar datos iniciales al destino
            target_sock.send(data)

            # Iniciar hilos para encaminar datos
            threading.Thread(
                target=self.pipe, args=(client_sock, target_sock, f"{addr[0]}:{addr[1]} -> destino")
            ).start()
            threading.Thread(
                target=self.pipe, args=(target_sock, client_sock, f"destino -> {addr[0]}:{addr[1]}")
            ).start()

        except socket.timeout:
            logger.error(f"Timeout en conexión con {addr[0]}:{addr[1]}")
            client_sock.close()
        except socket.error as e:
            logger.error(f"Error en conexión con {addr[0]}:{addr[1]}: {e}")
            client_sock.close()
        except Exception as e:
            logger.error(f"Error inesperado con {addr[0]}:{addr[1]}: {e}", exc_info=True)
            client_sock.close()

    def extract_host(self, data: bytes) -> str:
        """Extrae el encabezado Host de los datos recibidos."""
        try:
            for line in data.decode(errors="ignore").split("\r\n"):
                if line.lower().startswith("host:"):
                    return line.split(":", 1)[1].strip()
        except Exception as e:
            logger.debug(f"Error al extraer Host: {e}")
        return "desconocido"

    def pipe(self, src: socket.socket, dst: socket.socket, direction: str) -> None:
        """Encamina datos entre dos sockets."""
        try:
            while self.running:
                data = src.recv(self.config.buffer_size)
                if not data:
                    logger.debug(f"Conexión cerrada ({direction})")
                    break
                dst.send(data)
                logger.debug(f"Encaminados {len(data)} bytes ({direction})")
        except socket.timeout:
            logger.warning(f"Timeout en encaminamiento ({direction})")
        except socket.error as e:
            logger.warning(f"Error en encaminamiento ({direction}): {e}")
        except Exception as e:
            logger.error(f"Error inesperado en encaminamiento ({direction}): {e}", exc_info=True)
        finally:
            src.close()
            dst.close()
            logger.debug(f"Sockets cerrados ({direction})")

    def start(self) -> None:
        """Inicia el proxy."""
        self.running = True
        self.setup_socket()
        try:
            while self.running:
                try:
                    client_sock, addr = self.server_socket.accept()
                    threading.Thread(
                        target=self.handle_client, args=(client_sock, addr)
                    ).start()
                except socket.timeout:
                    continue
                except Exception as e:
                    logger.error(f"Error al aceptar conexión: {e}", exc_info=True)
                    if not self.running:
                        break
        finally:
            self.shutdown()

    def shutdown(self) -> None:
        """Cierra el proxy limpiamente."""
        self.running = False
        if self.server_socket:
            self.server_socket.close()
            logger.info("Proxy detenido.")

def parse_arguments() -> ProxyConfig:
    """Parsea y valida los argumentos de la línea de comandos."""
    if len(sys.argv) < 4:
        print("Uso: python3 proxy.py <puerto_proxy> <puerto_destino> <response_code>")
        sys.exit(1)

    try:
        listen_port = int(sys.argv[1])
        target_port = int(sys.argv[2])
        response_code = sys.argv[3]
    except ValueError:
        print("Error: Los puertos deben ser números enteros.")
        sys.exit(1)

    return ProxyConfig(listen_port, target_port, response_code)

def main():
    """Función principal."""
    # Configurar manejo de señales para cierre limpio
    proxy = None
    def signal_handler(sig, frame):
        logger.info("Recibida señal de terminación. Deteniendo proxy...")
        if proxy:
            proxy.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Iniciar el proxy
    try:
        config = parse_arguments()
        proxy = ProxyServer(config)
        proxy.validate_config()
        proxy.start()
    except Exception as e:
        logger.error(f"Error al iniciar el proxy: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
