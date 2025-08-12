import os
import yaml
from pathlib import Path

CONFIG_FILE = os.getenv("CONFIG_FILE", "config.yaml")

try:
    with open(CONFIG_FILE, "r") as f:
        CONFIG = yaml.safe_load(f)
except Exception as e:
    raise RuntimeError(f"Error loading configuration file: {CONFIG_FILE}") from e
