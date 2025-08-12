# app/predict_from_spots.py
import redis
import threading
import json
import logging
from datetime import datetime
from hf_utils import lookup_coords, run_iturhfprop
from config import CONFIG

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

REDIS_HOST = CONFIG["redis"]["host"]
REDIS_PORT = CONFIG["redis"]["port"]
OUTPUT_FILE = "/data/hf_predictions.log"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

# -----------------------
# Utilidades
# -----------------------

def _normalize_freq_mhz(freq):
    """
    Acepta string/float en MHz o kHz y devuelve MHz con 1 decimal (para clave).
    telnet_rbn.py ya manda frecuencia en MHz, pero normalizamos por si acaso.
    """
    f = float(freq)
    if f > 1000.0:
        f = f / 1000.0
    return round(f, 1)

def _parse_ts_to_dt(ts):
    """
    Soporta 'HHMMZ' (día actual UTC) o ISO 'YYYY-MM-DDTHH:MM:SSZ'
    """
    now = datetime.utcnow()
    ts = ts.strip()
    if ts.endswith("Z") and len(ts) == 5 and ts[:-1].isdigit():
        hour = int(ts[:2]); minute = int(ts[2:4])
        return datetime(year=now.year, month=now.month, day=now.day, hour=hour, minute=minute)
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))

def _ttl_for_rbn_mode(mode: str) -> int:
    """
    TTL por modo según config.yaml -> rbn.cw.ttl_minutes / rbn.digi.ttl_minutes
    """
    rbn_conf = CONFIG.get("rbn", {})
    m = (mode or "").upper()
    if m == "CW":
        return int(rbn_conf.get("cw", {}).get("ttl_minutes", 10)) * 60
    # El resto lo consideramos 'digi'
    return int(rbn_conf.get("digi", {}).get("ttl_minutes", 10)) * 60

# -----------------------
# Procesado de mensajes RBN (pubsub predict-hf)
# -----------------------

def _handle_rbn_message(msg: str):
    """
    Mensaje publicado por telnet_rbn.py:
      "rbn|<spotter>|<dx>|<freq_mhz>|<mode>|<ts_iso>"
    """
    parts = msg.strip().split("|")
    if len(parts) != 6:
        logger.warning(f"RBN mensaje inválido: {msg}")
        return

    user, spotter, dx, freq_s, mode, ts = parts
    if user != "rbn":
        logger.debug(f"Ignorado no-RBN en canal predict-hf: {msg}")
        return

    try:
        freq_mhz = _normalize_freq_mhz(freq_s)
        dt = _parse_ts_to_dt(ts)
    except Exception as e:
        logger.warning(f"RBN parse error (freq/ts): {e} msg={msg}")
        return

    # Coordenadas
    spotter_coords = lookup_coords(spotter)
    dx_coords = lookup_coords(dx)

    prediction = None
    if spotter_coords and dx_coords:
        try:
            # Usamos el modo tal cual llega (CW/FT8/FT4/PSK/RTTY…)
            sp = run_iturhfprop("SHORTPATH", spotter_coords, dx_coords, dt, freq_mhz, mode)
            lp = run_iturhfprop("LONGPATH",  spotter_coords, dx_coords, dt, freq_mhz, mode)
            prediction = {"short_path": sp, "long_path": lp}
        except Exception as e:
            logger.warning(f"RBN predicción fallida {spotter}->{dx} @ {freq_mhz} {mode}: {e}")

    # Guardar en Redis
    key = f"spot:rbn:{spotter}:{dx}:{freq_mhz:.1f}"
    payload = {
        "source": "rbn",
        "spotter": spotter,
        "dx": dx,
        "frequency": float(f"{freq_mhz:.1f}"),
        "mode": mode or "",
        "timestamp": dt.isoformat(),
    }
    if spotter_coords:
        payload["spotter_coords"] = spotter_coords
    if dx_coords:
        payload["dx_coords"] = dx_coords
    if prediction:
        payload["prediction"] = prediction

    ttl = _ttl_for_rbn_mode(mode)
    r.setex(key, ttl, json.dumps(payload, ensure_ascii=False))
    logger.info(f"💾 RBN cacheado: {key} (ttl {ttl}s)")

def _rbn_subscriber_loop():
    logger.info("📡 Suscriptor RBN en Redis canal 'predict-hf' iniciado.")
    pubsub = r.pubsub()
    pubsub.subscribe("predict-hf")
    for item in pubsub.listen():
        if not item or item.get("type") != "message":
            continue
        data = item.get("data")
        if not data:
            continue
        try:
            _handle_rbn_message(data)
        except Exception:
            logger.exception(f"Error procesando mensaje RBN: {data}")

# -----------------------
# (Opcional) soporte legado para spots humanos
# -----------------------

def normalize_freq(freq):
    freq = float(freq)
    return round(freq / 1000, 1) if freq > 1000 else round(freq, 1)

def clean_spotter(spotter):
    return spotter.rstrip("-#")

def handle_spot(msg: str):
    """
    Flujo legado para spots humanos. /predict (FastAPI) es lo real.
    """
    logger.info(f"📩 SPOT recibido: {msg}")
    try:
        parts = msg.strip().split("|")
        if len(parts) != 6:
            logger.warning(f"❌ Formato inválido en spot: {msg}")
            return

        user, spotter_raw, dx, freq_raw, mode, ts = parts
        freq = normalize_freq(freq_raw)
        spotter_clean = clean_spotter(spotter_raw)

        if freq > 30.0:
            logger.info(f"⛔ Spot ignorado (>30 MHz): {msg}")
            return

        now = datetime.utcnow()
        if ts.endswith("Z"):
            ts = ts[:-1]
        if len(ts) == 4 and ts.isdigit():
            hour = int(ts[:2]); minute = int(ts[2:])
            dt = datetime(year=now.year, month=now.month, day=now.day, hour=hour, minute=minute)
        else:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))

        user_coords = lookup_coords(user)
        dx_coords = lookup_coords(dx)
        if not user_coords or not dx_coords:
            logger.warning(f"⚠️ Coordenadas no encontradas para DXSpider: {user} o {dx}")
            return

        sp1 = run_iturhfprop("SHORTPATH", user_coords, dx_coords, dt, freq, "ANALOG")
        lp1 = run_iturhfprop("LONGPATH", user_coords, dx_coords, dt, freq, "ANALOG")

        # (opcional) muestra métrica usada (BCR/OCR)
        msp = sp1.get("metric",""); mlp = lp1.get("metric","")
        comment = f"[SP:{sp1['snr']}:{sp1['reliability']}{('/'+msp) if msp else ''}] " \
                  f"[LP:{lp1['snr']}:{lp1['reliability']}{('/'+mlp) if mlp else ''}]"

        max_len = 72 - len(f"{user}> DX de {spotter_clean}:  {freq}  {dx}  ") - len(f"  {ts}")
        comment = comment[:max_len].rstrip()
        line = f"{user}> DX de {spotter_clean}:  {freq}  {dx}  {comment}  {ts}"

        if CONFIG.get("human_spot", {}).get("log_predictions", False):
            with open(OUTPUT_FILE, "a") as f:
                f.write(line + "\n")
            logger.info(f"📝 Spot humano logueado: {line}")

        # Si quisieras cachear también este flujo:
        # spotter_coords = lookup_coords(spotter_clean)
        # if spotter_coords and dx_coords:
        #     ttl = 60 * CONFIG["human_spot"].get("ttl_minutes", 10)
        #     cache_key = f"spot:human:{spotter_clean}:{dx}:{freq}"
        #     cache_value = {
        #         "spotter": spotter_clean,
        #         "dx": dx,
        #         "frequency": freq,
        #         "mode": "ANALOG",
        #         "timestamp": dt.isoformat(),
        #         "spotter_coords": spotter_coords,
        #         "dx_coords": dx_coords,
        #         "source": "human",
        #         "prediction": {"short_path": sp1, "long_path": lp1}
        #     }
        #     r.setex(cache_key, ttl, json.dumps(cache_value))
        #     logger.info(f"💾 Spot humano cacheado en Redis: {cache_key}")

    except Exception as e:
        logger.exception(f"❌ Error procesando spot: {msg}")

# -----------------------
# Arranque
# -----------------------

def start_spot_predictor():
    """
    Arranca el hilo que escucha el canal 'predict-hf' para RBN.
    """
    t = threading.Thread(target=_rbn_subscriber_loop, daemon=True)
    t.start()
    logger.info("🧵 Hilo de predicción por spots (RBN subscriber) arrancado.")
