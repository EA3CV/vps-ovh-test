import telnetlib
import threading
import time
import logging
import re
import redis
import json
from config import CONFIG

logger = logging.getLogger(__name__)

# Inicializa Redis
redis_client = redis.Redis(host="redis", port=6379, decode_responses=True)

def parse_rbn_line(line: str):
    match = re.search(
        r"DX de ([\w\-]+)-?#:\s+(\d+\.\d+)\s+(\w+)\s+(CW|FT8|FT4|RTT|PSK)\s+(-?\d+)\s+dB",
        line
    )
    if match:
        spotter = match.group(1).replace("-", "")  # Eliminar también guión
        frequency = float(match.group(2))
        dx = match.group(3)
        mode = match.group(4)
        level = int(match.group(5))
        return {
            "spotter": spotter,
            "dx": dx,
            "frequency": round(frequency / 1000.0, 1) if frequency > 1000 else round(frequency, 1),
            "mode": mode,
            "level": level,
        }
    return None

def listen_to_rbn(label, host, port, username, ttl):
    while True:
        try:
            with telnetlib.Telnet(host, port, timeout=10) as tn:
                logger.info(f"🔌 [{label}] Conectado a {host}:{port} como {username}")
                time.sleep(2)
                tn.write(username.encode("ascii") + b"\n")
                last_activity = time.time()

                while True:
                    line = tn.read_until(b"\n").decode("utf-8", errors="ignore").strip()
                    if line:
                        logger.info(f"📡 [{label}] {line}")
                        last_activity = time.time()

                        spot = parse_rbn_line(line)
                        if spot:
                            freq = spot["frequency"]
                            if freq > 30.0:
                                logger.debug(f"⏭️ Frecuencia ignorada: {freq} MHz")
                                continue

                            now_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                            payload = {
                                "user": "rbn",
                                "spotter": spot["spotter"],
                                "dx": spot["dx"],
                                "freq": freq,
                                "mode": spot["mode"],
                                "ts": now_utc,
                                "source": "rbn",
                                "modulation": "DIGITAL"
                            }
                            message = "|".join(str(payload[k]) for k in ["user", "spotter", "dx", "freq", "mode", "ts"])
                            redis_client.publish("predict-hf", message)
                            logger.info(f"📤 Spot RBN publicado: {message}")

                    if time.time() - last_activity > ttl:
                        logger.warning(f"⚠️ [{label}] TTL superado, reconectando...")
                        break
        except Exception as e:
            logger.error(f"❌ [{label}] Error Telnet: {e}")
        time.sleep(5)

def start_telnet_sessions():
    rbn_conf = CONFIG.get("rbn", {})

    if rbn_conf.get("cw", {}).get("enabled", False):
        cw = rbn_conf["cw"]
        threading.Thread(
            target=listen_to_rbn,
            args=("CW", cw["host"], cw["port"], cw["username"], cw.get("ttl_minutes", 10) * 60),
            daemon=True
        ).start()

    if rbn_conf.get("digi", {}).get("enabled", False):
        digi = rbn_conf["digi"]
        threading.Thread(
            target=listen_to_rbn,
            args=("DIGI", digi["host"], digi["port"], digi["username"], digi.get("ttl_minutes", 10) * 60),
            daemon=True
        ).start()
