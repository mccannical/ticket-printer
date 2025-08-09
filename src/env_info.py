import socket
import requests
import time
from datetime import datetime


def get_external_ip():
    """Get the external IP address using an external service."""
    try:
        response = requests.get('https://api.ipify.org?format=json', timeout=5)
        response.raise_for_status()
        return response.json().get('ip')
    except Exception as e:
        return f"Error: {e}"

def get_last_checkin_time():
    """Return the current UTC time as last check-in time."""
    return datetime.utcnow().isoformat() + 'Z'


def get_printer_status():
    """Stub for printer status. Replace with actual printer check logic."""
    # TODO: Implement actual printer status check
    return "OK"


def gather_env_info():
    """Gather all environment info to send to backend."""
    return {
        'external_ip': get_external_ip(),
        'last_checkin': get_last_checkin_time(),
        'printer_status': get_printer_status(),
    }

if __name__ == "__main__":
    import json
    print(json.dumps(gather_env_info(), indent=2))
