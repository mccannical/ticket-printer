import requests
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



import subprocess

def get_printer_status():
    """
    Gather information about locally attached printers using lpstat.
    Returns a string with printer info or error message.
    """
    try:
        # Get default printer
        default = subprocess.check_output(["lpstat", "-d"]).decode().strip()
    except Exception:
        default = "No default printer found"
    try:
        # Get all printers and their status
        printers = subprocess.check_output(["lpstat", "-p"]).decode().strip()
    except Exception as e:
        printers = f"Error: {e}"
    return f"{default}\n{printers}"


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
