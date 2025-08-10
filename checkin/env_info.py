"""Environment & printer status utilities."""

from __future__ import annotations

import subprocess
from datetime import datetime
from typing import Dict

import requests


def get_external_ip() -> str:
    """Return external IP address via ipify service (best effort)."""
    try:
        response = requests.get("https://api.ipify.org?format=json", timeout=5)
        response.raise_for_status()
        return str(response.json().get("ip"))
    except Exception as e:  # pragma: no cover - network variability
        return f"Error: {e}"


def get_last_checkin_time() -> str:
    """Return current UTC timestamp in RFC3339-like format."""
    return datetime.utcnow().isoformat() + "Z"

def get_printer_status() -> str:
    """Return default printer + status lines using lpstat (best effort)."""
    try:
        default = subprocess.check_output(["lpstat", "-d"]).decode().strip()
    except Exception:
        default = "No default printer found"
    try:
        printers = subprocess.check_output(["lpstat", "-p"]).decode().strip()
    except Exception as e:  # pragma: no cover
        printers = f"Error: {e}"
    return f"{default}\n{printers}"


def gather_env_info() -> Dict[str, str]:
    """Gather environment attributes for check-in payload."""
    return {
        "external_ip": get_external_ip(),
        "last_checkin": get_last_checkin_time(),
        "printer_status": get_printer_status(),
    }

if __name__ == "__main__":
    import json
    print(json.dumps(gather_env_info(), indent=2))
