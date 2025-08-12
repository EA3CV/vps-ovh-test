# app/hf_utils.py
import json
import os
import logging
import subprocess
import tempfile
from datetime import datetime, timedelta

import redis
import requests

from config import CONFIG  # lee config.yaml

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Redis
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
CACHE_EXPIRE = int(os.getenv("CACHE_EXPIRE", "3600"))

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

# --- Prefijos indicativos de QTH por indicativo ---
try:
    with open("/app/callsign_prefixes.json", "r") as f:
        callsign_prefix_map = json.load(f)
    logger.info("Loaded %d prefixes", len(callsign_prefix_map))
except Exception:
    logger.exception("Error decoding JSON prefixes")
    callsign_prefix_map = {}


def lookup_coords(callsign: str):
    cs = callsign.upper()
    matched = [
        (prefix, coords)
        for prefix, coords in callsign_prefix_map.items()
        if cs.startswith(prefix.upper())
    ]
    if not matched:
        return None
    return max(matched, key=lambda x: len(x[0]))[1]


# --------------------------------------------------------------------
#  Space weather desde Redis: f107/kp/ap  (ap se ignora por ahora)
# --------------------------------------------------------------------

def _spacewx_from_redis():
    key = CONFIG.get("spacewx", {}).get("redis_key", "spacewx:latest")
    data = r.get(key)
    if not data:
        return None
    try:
        return json.loads(data)
    except Exception:
        logger.warning("spacewx: invalid JSON in Redis key=%s", key)
        return None


def get_spacewx_indices(now_utc: datetime):
    """
    Lee f107/kp/ap desde Redis y valida frescura.
    Devuelve dict con f107, kp, ap y ts; o None si no válido.
    """
    cfg = CONFIG.get("spacewx", {})
    max_age_h = int(cfg.get("max_age_hours", 6))
    data = _spacewx_from_redis()
    if not data:
        return None

    ts_str = data.get("fetched_utc") or data.get("kp_time")
    if not ts_str:
        return None

    try:
        ts_norm = ts_str.replace("Z", "+00:00").replace(" ", "T")
        base = ts_norm.split("+")[0]
        ts = datetime.fromisoformat(base)
    except Exception:
        logger.warning("spacewx: bad timestamp: %s", ts_str)
        return None

    if (now_utc - ts) > timedelta(hours=max_age_h):
        logger.warning("spacewx: data too old (> %dh)", max_age_h)
        return None

    def _flt(x):
        try:
            return float(x)
        except Exception:
            return None

    return {
        "f107": _flt(data.get("f107")),
        "kp": _flt(data.get("kp")),   # puede venir o no; opcional
        "ap": _flt(data.get("ap")),   # ignorado de momento
        "ts": ts,
    }


def f107_to_ssn(f107: float) -> int:
    """
    Conversión configurable F10.7 -> SSN (proxy para ITURHFProp).
    SSN ≈ a * (F10.7 - b)
    """
    conv = CONFIG.get("spacewx", {}).get("f107_to_ssn", {})
    a = float(conv.get("a", 1.61))
    b = float(conv.get("b", 67.0))
    ssn = a * (float(f107) - b)
    return max(1, min(311, int(round(ssn))))  # rango típico


# ---------------------------
#  Fallback SSN NOAA (como tenías)
# ---------------------------

def get_ssn_value(dt: datetime) -> int:
    yest = dt.date() - timedelta(days=1)
    cache_key = f"ssn:{yest.isoformat()}"
    if (cached := r.get(cache_key)):
        return int(cached)

    url = "https://services.swpc.noaa.gov/text/daily-solar-indices.txt"
    try:
        resp = requests.get(url, timeout=5)
        resp.raise_for_status()
        for line in resp.text.splitlines():
            if line.startswith(f"{yest.year} {yest.month:02d} {yest.day:02d}"):
                parts = line.split()
                ssn = int(parts[3])
                r.set(cache_key, ssn, ex=86400 * 7)
                return ssn
    except Exception:
        logger.warning("Failed to fetch SSN, using fallback=100")

    return 100


def get_effective_ssn(dt: datetime) -> int:
    """
    Usa F10.7 reciente en Redis → SSN equivalente; si no, NOAA.
    """
    wx = get_spacewx_indices(datetime.utcnow())
    if wx and wx.get("f107") is not None:
        ssn = f107_to_ssn(wx["f107"])
        logger.info("spacewx: F10.7=%.1f -> SSN=%d", wx["f107"], ssn)
        return ssn
    return get_ssn_value(dt)


# ---------------------------
#  ITURHFProp (perfil + métrica única por camino)
# ---------------------------

def run_iturhfprop(path_type: str, tx, rx, dt, freq, mode) -> dict:
    """
    Ejecuta ITURHFProp para SHORTPATH/LONGPATH y devuelve:
      { snr:int, reliability:int, metric:str, bcr:int|None, ocr:int|None, sir:float|None, snr_margin_db:float }
    Reglas:
      - DIGITAL (FT8/FT4): base = BCR (OCR se ignora). BW=2.5 kHz, SNRr=-12, SIRr=8, SNRXXp=50.
      - ANALOG (SSB/CW):   base = OCR si SIR creíble (si no, BCR). BW=2.7 kHz, SNRr=22, SIRr=15, SNRXXp=50.
      - Penalización por margen SNR: >=0 dB → sin penalizar; [-3,0) → ×0.6; [-6,-3) → ×0.3; < -6 → 0.
    """
    infile = tempfile.NamedTemporaryFile("w+", suffix=".in", delete=False)
    outfile = tempfile.NamedTemporaryFile("w+", suffix=".out", delete=False)
    infile.close()
    outfile.close()

    in_path = infile.name
    out_path = outfile.name

    # SSN efectivo (F10.7->SSN si hay; si no, NOAA)
    ssn = get_effective_ssn(dt)

    # Convertir frecuencia a MHz si viene en kHz
    freq_mhz = freq / 1000.0 if freq > 1000 else float(freq)
    logger.info("Frecuencia convertida: %.3f MHz (original: %.1f)", freq_mhz, freq)

    # Traducir modo a ANALOG/DIGITAL (SSB y CW caen en ANALOG por ahora)
    mod = str(mode or "").upper()
    modulation = "DIGITAL" if mod in ["DIGI", "DIGITAL", "FT8", "FT4"] else "ANALOG"
    logger.info("Modo ITURHFProp: %s (original: %s)", modulation, mode)

    # Perfiles realistas
    if modulation == "DIGITAL":
        bw_hz       = 2500.0
        snr_r       = -12.0    # cómodo FT8 en 2.5 kHz (–18 mínimo)
        sir_r       = 8.0
        snr_pctl    = 50       # p50 por defecto
        use_ocr     = False    # OCR/SIR poco fiables en digital NB, ahorro CPU
    else:
        # ANALOG (SSB y CW — de momento iguales)
        bw_hz       = 2700.0   # si separas CW, cámbialo a 500.0 y SNRr≈11, SIRr≈10
        snr_r       = 22.0     # umbral cómodo SSB
        sir_r       = 15.0
        snr_pctl    = 50       # p50; usa 80–90 para conservador (tu build interpreta “excedido XX%”)
        use_ocr     = True

    # Entorno y antenas por defecto (realistas)
    noise_env   = "RESIDENTIAL"  # "RURAL" si QTH muy limpio
    txgos_db    = 6.0            # dipolo/vertical (+pérdidas)
    rxgos_db    = 6.0
    txpower_dbw = 20.0           # 100 W

    hf_input = f"""\  
PathName "HF P2P Prediction"
PathTXName "TX"
Path.L_tx.lat {tx[0]}
Path.L_tx.lng {tx[1]}
TXAntFilePath "ISOTROPIC"
TXGOS {txgos_db}
PathRXName "RX"
Path.L_rx.lat {rx[0]}
Path.L_rx.lng {rx[1]}
RXAntFilePath "ISOTROPIC"
RXGOS {rxgos_db}
AntennaOrientation "TX2RX"
TXBearing 0.0
RXBearing 0.0
Path.year {dt.year}
Path.month {dt.month}
Path.hour {dt.hour}
Path.SSN {ssn}
Path.frequency {freq_mhz}
Path.txpower {txpower_dbw}
Path.BW {bw_hz}
Path.SNRr {snr_r}
Path.Relr 90
Path.SNRXXp {snr_pctl}
Path.SIRr {sir_r}
Path.type 1
Path.tx_mode 0
Path.SorL "{path_type}"
Path.ManMadeNoise "{noise_env}"
Path.Modulation "{modulation}"
LL.lat {rx[0]}
LL.lng {rx[1]}
LR.lat {rx[0]}
LR.lng {rx[1]}
UL.lat {rx[0]}
UL.lng {rx[1]}
UR.lat {rx[0]}
UR.lng {rx[1]}
latinc 1.0
lnginc 1.0
DataFilePath "/opt/iturhf/data/"
RptFilePath "/tmp/"
{ 'RptFileFormat "RPT_SNRXX | RPT_BCR"' if not use_ocr else 'RptFileFormat "RPT_SNRXX | RPT_SIRXX | RPT_BCR | RPT_OCR"' }
"""

    with open(in_path, "w") as f:
        f.write(hf_input)

    logger.info("ITURHFProp INPUT (Path: %s, SSN:%d):\n%s", path_type, ssn, hf_input)

    cmd = ["/usr/bin/ITURHFProp", "-s", "-c", "-t", in_path, out_path]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        logger.error("ITURHFProp failed for %s: %s", path_type, proc.stdout)
        raise Exception(f"ITURHFProp failed for {path_type}")

    # --- Parseo robusto por cabecera ---
    snr = None; bcr = None; ocr = None; sir = None
    try:
        with open(out_path, "r") as f:
            lines = [ln.strip() for ln in f if ln.strip()]
        if len(lines) < 2:
            raise RuntimeError("empty report")
        header = lines[0].split(",")
        data   = lines[-1].split(",")
        idx = {name: header.index(name) for name in header}
        # SNR
        if "SNRXXp" in idx:
            snr = float(data[idx["SNRXXp"]])
        elif "SNR" in idx:
            snr = float(data[idx["SNR"]])
        # BCR / OCR
        if "BCR" in idx:
            bcr = float(data[idx["BCR"]])
        if "OCR" in idx:
            ocr = float(data[idx["OCR"]])
        # SIR (algunas builds devuelven SIR a secas)
        if "SIRXXp" in idx:
            sir = float(data[idx["SIRXXp"]])
        elif "SIR" in idx:
            sir = float(data[idx["SIR"]])
    except Exception:
        logger.exception(f"Error parsing report ({path_type})")
        raise Exception(f"Failed reading report for {path_type}")

    if snr is None or bcr is None:
        raise Exception(f"No data found in report for {path_type}")

    # --- Selección de métrica base (un único %) ---
    # DIGITAL: siempre BCR. ANALOG: OCR si SIR creíble; si no, BCR.
    sir_valid = False
    if sir is not None:
        # filtra valores imposibles/sentinela (e.g. -307)
        sir_valid = (-100.0 < sir < 200.0) and (abs(sir + 307.0) > 1e-3)

    base_metric = "BCR"
    base_rel = bcr
    if (modulation == "ANALOG") and sir_valid and (ocr is not None):
        base_metric = "OCR"
        base_rel = ocr

    # --- Penalización por margen SNR respecto a SNRr ---
    margin = snr - snr_r
    if margin >= 0:
        reliability = base_rel
    elif margin >= -3:
        reliability = base_rel * 0.6
    elif margin >= -6:
        reliability = base_rel * 0.3
    else:
        reliability = 0.0

    # --- Ajuste opcional por Kp sobre la fiabilidad (post-proceso) ---
    adj_cfg = CONFIG.get("spacewx", {}).get("reliability_adjust", {})
    if adj_cfg.get("enabled", False):
        wx = get_spacewx_indices(datetime.utcnow())
        kp = wx.get("kp") if wx else None
        if kp is not None:
            slope = float(adj_cfg.get("slope", 0.07))
            kp0   = float(adj_cfg.get("kp0", 3.0))
            minf  = float(adj_cfg.get("min", 0.10))
            factor = 1.0 - slope * max(0.0, float(kp) - kp0)
            factor = max(minf, min(1.0, factor))
            reliability = reliability * factor
            logger.info("Kp adjust: Kp=%.1f factor=%.2f → rel=%d",
                        kp, factor, int(round(reliability)))

    # Redondeos finales (mantén compatibilidad con tu UI)
    return {
        "snr": int(round(snr)),
        "reliability": int(round(reliability)),
        # info extra útil para logs/diagnóstico (no rompe al consumidor actual)
        "metric": base_metric,
        "bcr": int(round(bcr)) if bcr is not None else None,
        "ocr": int(round(ocr)) if ocr is not None else None,
        "sir": None if not sir_valid else round(sir, 1),
        "snr_margin_db": round(margin, 1),
    }
