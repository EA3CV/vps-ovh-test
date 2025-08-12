# app/main.py

import os
import json
import time
import logging
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from predict_from_spots import start_spot_predictor
from telnet_rbn import start_telnet_sessions
from hf_utils import lookup_coords, run_iturhfprop
from config import CONFIG

import redis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

@app.on_event("startup")
def startup_event():
    start_telnet_sessions()
    start_spot_predictor()

@app.get("/health")
def health():
    return {"status": "ok"}

# ------------------ Config cache/binning ------------------

# Redis
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0, decode_responses=True)

# TTL cache principal
CACHE_EXPIRE = int(os.getenv("CACHE_EXPIRE", "600"))  # 10 min por defecto

# Binning para maximizar hits de cache sin perder utilidad operativa
FREQ_BIN_MHZ = float(os.getenv("FREQ_BIN_MHZ", "1.0"))  # agrupa por 1 MHz
TIME_BIN_MIN = int(os.getenv("TIME_BIN_MIN", "15"))     # agrupa por 15 min
COORD_DECIMALS = int(os.getenv("COORD_DECIMALS", "2"))  # 2 decimales ~1-2 km

# Versión de esquema de clave (si cambias binning o formato, súbela)
CACHE_KEY_VER = "v2"

DIGITAL_MODES = {"DIGITAL", "FT8", "FT4", "RTTY", "PSK", "CW"}

# ------------------ Modelos ------------------

class PredictionInput(BaseModel):
    callsign_user: str        # ← $user de DXSpider
    callsign_spotter: str     # ← quien hizo el spot
    callsign_dx: str          # ← el DX
    frequency: float
    mode: str = "ANALOG"
    timestamp: str            # ISO 8601
    comment: str = ""         # comentario original opcional

# ------------------ Utilidades de formato ------------------

def format_dxspider_comment(comment, sp_snr, sp_rel, lp_snr, lp_rel):
    """Formato COMPLETO (para logs): [SP:snr:rel] [LP:snr:rel] + comentario."""
    pred = f"[SP:{sp_snr}:{sp_rel}] [LP:{lp_snr}:{lp_rel}]"
    final = f"{pred} {comment}".strip()
    return final[:80]

def format_dxspider_compact(sp_rel: int, lp_rel: int, suffix_comment: str = "") -> str:
    """
    Formato COMPACTO (para DXSpider):
      - ambos 0  -> [0]
      - solo SP  -> [SP:<rel>]
      - solo LP  -> [LP:<rel>]
      - ambos    -> [SP:<rel>,LP:<rel>]
    Luego añade el comentario original (si existe).
    """
    parts = []
    if sp_rel != 0:
        parts.append(f"SP:{sp_rel}")
    if lp_rel != 0:
        parts.append(f"LP:{lp_rel}")

    if not parts:
        pred_str = "[0]"
    elif len(parts) == 1:
        pred_str = f"[{parts[0]}]"
    else:
        pred_str = f"[{','.join(parts)}]"

    if suffix_comment:
        return f"{pred_str} {suffix_comment}".strip()[:80]
    return pred_str[:80]

# ------------------ Normalización, frecuencia y claves de cache ------------------

def _is_digital(mode: str) -> bool:
    return (mode or "").upper() in DIGITAL_MODES

def _norm_mode(mode: str) -> str:
    return "DIGITAL" if _is_digital(mode) else "ANALOG"

def _to_mhz(freq: float) -> float:
    """Si parece kHz (>1000), convierte a MHz; si ya es MHz, deja igual."""
    f = float(freq)
    if f > 1000.0:
        # Mensaje solo a nivel debug para no ensuciar logs
        logger.debug("Convirtiendo frecuencia de kHz a MHz: %.3f kHz -> %.3f MHz", f, f / 1000.0)
        return f / 1000.0
    return f

def _freq_bin_mhz(f_mhz: float) -> float:
    # Redondeo al múltiplo más cercano de 1 MHz (o del paso configurado)
    step = FREQ_BIN_MHZ if FREQ_BIN_MHZ > 0 else 1.0
    binned = round(round(float(f_mhz) / step) * step, 0)
    return float(binned)

def _time_bin(dt: datetime) -> str:
    # Devuelve cadena YYYYMMDDTHHZ al múltiplo inferior de TIME_BIN_MIN
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    dt = dt.astimezone(timezone.utc)
    minute = (dt.minute // TIME_BIN_MIN) * TIME_BIN_MIN
    dtb = dt.replace(minute=minute, second=0, microsecond=0)
    return dtb.strftime("%Y%m%dT%H%MZ")

def _cache_key(src_lat, src_lon, dst_lat, dst_lon, f_mhz: float, mode: str, dt: datetime) -> str:
    # Asegura floats aunque vengan como str
    try:
        src_lat = float(src_lat); src_lon = float(src_lon)
        dst_lat = float(dst_lat); dst_lon = float(dst_lon)
    except Exception:
        raise HTTPException(400, "Invalid coordinates (not numeric)")

    fz = _freq_bin_mhz(f_mhz)
    tz = _time_bin(dt)
    mod = _norm_mode(mode)

    fmt = f"{{:.{COORD_DECIMALS}f}}"
    s_lat = fmt.format(src_lat); s_lon = fmt.format(src_lon)
    d_lat = fmt.format(dst_lat); d_lon = fmt.format(dst_lon)
    return f"pred:{CACHE_KEY_VER}:{s_lat},{s_lon}->{d_lat},{d_lon}:{fz:.0f}MHz:{mod}:{tz}"

# ------------------ Núcleo: cache + singleflight ------------------

def _to_float_coords(coords):
    # coords puede venir como ('41.12','2.22') → devuelve (41.12, 2.22)
    return (float(coords[0]), float(coords[1]))

def _compute_sp_lp(src_coords, dst_coords, dt: datetime, freq_mhz: float, mode: str) -> dict:
    """
    Ejecuta ITURHFProp dos veces (SP/LP) y devuelve:
    {
      "short_path": {"snr": int, "reliability": int},
      "long_path":  {"snr": int, "reliability": int}
    }
    """
    short_path = run_iturhfprop("SHORTPATH", src_coords, dst_coords, dt, freq_mhz, mode)
    long_path  = run_iturhfprop("LONGPATH",  src_coords, dst_coords, dt, freq_mhz, mode)
    return {"short_path": short_path, "long_path": long_path}

def get_prediction_with_cache(src_coords, dst_coords, dt: datetime, freq_mhz: float, mode: str):
    """
    Lee de cache por clave normalizada. Si no existe:
    - Usa lock distribuido de Redis para que solo 1 proceso calcule (singleflight).
    - El resto espera resultado en cache (poll ligero) sin recálculo.
    Devuelve (prediction_dict, cached_bool).
    """
    # Asegura que trabajamos con floats siempre
    src_coords = _to_float_coords(src_coords)
    dst_coords = _to_float_coords(dst_coords)

    key = _cache_key(src_coords[0], src_coords[1],
                     dst_coords[0], dst_coords[1],
                     freq_mhz, mode, dt)

    cached = r.get(key)
    if cached:
        return json.loads(cached), True

    # Singleflight con Redis Lock
    lock = r.lock(f"lock:{key}", timeout=30, blocking_timeout=5)
    got = False
    try:
        got = lock.acquire(blocking=True)
        if got:
            # Doble-check de cache tras adquirir el lock
            cached2 = r.get(key)
            if cached2:
                return json.loads(cached2), True

            result = _compute_sp_lp(src_coords, dst_coords, dt, freq_mhz, mode)
            r.setex(key, CACHE_EXPIRE, json.dumps(result))
            return result, False
        else:
            # No adquirida: esperar a que aparezca en cache hasta 5s
            deadline = time.time() + 5.0
            while time.time() < deadline:
                val = r.get(key)
                if val:
                    return json.loads(val), True
                time.sleep(0.05)
            # Último intento: si seguimos sin valor, calculamos nosotros
            got2 = lock.acquire(blocking=False)
            if got2:
                try:
                    result = _compute_sp_lp(src_coords, dst_coords, dt, freq_mhz, mode)
                    r.setex(key, CACHE_EXPIRE, json.dumps(result))
                    return result, False
                finally:
                    lock.release()
            raise HTTPException(503, "Prediction busy, try again")
    finally:
        if got:
            try:
                lock.release()
            except Exception:
                pass

# ------------------ Endpoints ------------------

@app.post("/predict")
def predict(req: PredictionInput):
    logger.info("📥 API /predict recibió: %s", req.dict())

    # 1. Predicción para devolver (user → dx)
    user_coords = lookup_coords(req.callsign_user)
    dx_coords   = lookup_coords(req.callsign_dx)
    if not user_coords or not dx_coords:
        raise HTTPException(400, "No coords for one callsign")

    # Fuerza floats
    user_coords = _to_float_coords(user_coords)
    dx_coords   = _to_float_coords(dx_coords)

    # timestamp
    try:
        dt = datetime.fromisoformat(req.timestamp.replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(400, "Invalid timestamp")

    # Frecuencia en MHz (convierte si viene en kHz)
    freq_mhz = _to_mhz(req.frequency)
    mode_norm = _norm_mode(req.mode)

    # Cache + singleflight
    prediction, was_cached = get_prediction_with_cache(user_coords, dx_coords, dt, freq_mhz, mode_norm)

    # → DXSpider: formato compacto + comentario original
    new_comment = format_dxspider_compact(
        prediction["short_path"]["reliability"],
        prediction["long_path"]["reliability"],
        req.comment
    )

    # 2. Procesar si es humano (reutiliza cache también para spotter→dx)
    is_human = not _is_digital(req.mode)
    if is_human:
        cfg = CONFIG.get("human_spot", {})
        if cfg.get("enabled", True):
            spotter_coords = lookup_coords(req.callsign_spotter)
            if spotter_coords and dx_coords:
                spotter_coords = _to_float_coords(spotter_coords)
                sp_pred, _ = get_prediction_with_cache(spotter_coords, dx_coords, dt, freq_mhz, "ANALOG")

                # Guarda objeto combinado (como ya hacías)
                redis_key = f"spot:human:{req.callsign_spotter}:{req.callsign_dx}:{round(freq_mhz,1)}"
                r.setex(redis_key, cfg.get("ttl_minutes", 10) * 60, json.dumps({
                    "spotter": req.callsign_spotter,
                    "dx": req.callsign_dx,
                    "frequency": round(freq_mhz, 1),
                    "mode": "",  # modo real no conocido
                    "timestamp": dt.isoformat(),
                    "spotter_coords": spotter_coords,
                    "dx_coords": dx_coords,
                    "source": "human",
                    "prediction": sp_pred
                }))

        # Loguear en fichero (formato COMPLETO) si está habilitado
        if cfg.get("log_predictions", False):
            try:
                comment_for_log = format_dxspider_comment(
                    req.comment,
                    prediction["short_path"]["snr"], prediction["short_path"]["reliability"],
                    prediction["long_path"]["snr"],  prediction["long_path"]["reliability"]
                )
                line = f"{req.callsign_user}> DX de {req.callsign_spotter}:  {freq_mhz}  {req.callsign_dx}  {comment_for_log}  {req.timestamp}"
                with open("/data/hf_predictions.log", "a") as f:
                    f.write(line + "\n")
                logger.info(f"📝 Spot humano logueado: {line}")
            except Exception as e:
                logger.warning(f"⚠️ Error writing to log: {e}")

    return {
        "prediction": prediction,
        "cached": was_cached,
        "new_comment": new_comment
    }

@app.post("/predict_manual")
def predict_manual(req: PredictionInput):
    """
    Predicción directa: no se cachea, no se almacena, no se loguea.
    """
    tx = lookup_coords(req.callsign_user)
    rx = lookup_coords(req.callsign_dx)
    if not tx or not rx:
        raise HTTPException(400, "No coords for one callsign")

    # Fuerza floats
    tx = _to_float_coords(tx)
    rx = _to_float_coords(rx)

    try:
        dt = datetime.fromisoformat(req.timestamp.replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(400, "Invalid timestamp")

    freq_mhz = _to_mhz(req.frequency)
    short_path = run_iturhfprop("SHORTPATH", tx, rx, dt, freq_mhz, req.mode)
    long_path  = run_iturhfprop("LONGPATH",  tx, rx, dt, freq_mhz, req.mode)

    prediction = {"short_path": short_path, "long_path": long_path}

    return {"prediction": prediction, "cached": False}
