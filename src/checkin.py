import logging
import sys
try:
    from systemd.journal import JournaldLogHandler
    SYSTEMD_AVAILABLE = True
except ImportError:
    SYSTEMD_AVAILABLE = False

def setup_logging(verbosity="INFO"):
    """
    Set up logging to systemd-journald if available, else stderr. Verbosity is one of the standard levels.
    """
    level = getattr(logging, verbosity.upper(), logging.INFO)
    logger = logging.getLogger()
    logger.setLevel(level)
    # Remove all handlers
    for h in logger.handlers[:]:
        logger.removeHandler(h)
    if SYSTEMD_AVAILABLE:
        handler = JournaldLogHandler()
    else:
        handler = logging.StreamHandler(sys.stderr)
    formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)

import socket
def get_local_ip():
    """
    Get the local IP address of the machine.
    """
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "Unknown"

def print_test_ticket(printer_uuid, local_ip, external_ip, last_checkin_date, last_checkin_data):
    """
    import os
    import uuid
    import socket
    import subprocess
    import requests
    import json
    from src.env_info import gather_env_info

    Print a test ticket with basic printer and network info.
    """
    ticket = f"""
==================== TEST TICKET ====================
Printer UUID:    {printer_uuid}
Local IP:        {local_ip}
External IP:     {external_ip}
Last Check-in:   {last_checkin_date}
Last Check-in Data:
{json.dumps(last_checkin_data, indent=2)}
====================================================
"""
    print(ticket)
import subprocess

GITHUB_REPO = "mccannical/ticket-printer"

def get_latest_github_release():
    """
    Query the GitHub API for the latest release tag.
    Returns the tag name as a string, or None on failure.
    """
    api_url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
    headers = {"Accept": "application/vnd.github.v3+json", "User-Agent": USER_AGENT}
    try:
        resp = requests.get(api_url, headers=headers, timeout=5)
        resp.raise_for_status()
        data = resp.json()
        return data.get("tag_name")
    except Exception as e:
        print(f"Failed to fetch latest GitHub release: {e}")
        return None

def get_current_git_tag():
    """
    Returns the current git tag or commit hash, or None if not available.
    """
    try:
        tag = subprocess.check_output(["git", "describe", "--tags", "--abbrev=0"]).decode().strip()
        return tag
    except Exception:
        try:
            commit = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()
            return commit
        except Exception:
            return None

def upgrade_if_new_release():
    """
    Checks for a new release on GitHub and upgrades if available.
    """
    latest_tag = get_latest_github_release()
    current_tag = get_current_git_tag()
    print(f"Current version: {current_tag}, Latest release: {latest_tag}")
    if latest_tag and current_tag and latest_tag != current_tag:
        print(f"Upgrading to latest release: {latest_tag}")
        try:
            subprocess.check_call(["git", "fetch", "--tags"])
            subprocess.check_call(["git", "checkout", latest_tag])
            subprocess.check_call([".venv/bin/uv", "pip", "install", "-r", "requirements.txt"])
            print("Upgrade complete. Please restart the service if needed.")
        except Exception as e:
            print(f"Upgrade failed: {e}")
    else:
        print("Already at latest version or unable to determine version.")
import requests
import json
from src.env_info import gather_env_info

BACKEND_URL = "https://checkoff.mccannical.com/printer_checkin"  # Update as needed
USER_AGENT = "TicketPrinter/1.0"

# This should be unique per device in production
import os
import uuid

def get_printer_uuid():
    """
    Generate or retrieve a persistent UUID1 for this printer.
    The UUID is stored in config/printer_uuid.txt and reused on subsequent runs.
    """
    config_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'config')
    uuid_file = os.path.join(config_dir, 'printer_uuid.txt')
    if not os.path.exists(config_dir):
        os.makedirs(config_dir)
    if os.path.exists(uuid_file):
        with open(uuid_file, 'r') as f:
            value = f.read().strip()
            if value:
                return value
    # Generate and store new UUID1
    new_uuid = str(uuid.uuid1())
    with open(uuid_file, 'w') as f:
        f.write(new_uuid)
    return new_uuid


def build_checkin_payload(env_info, printer_uuid):
    import time
    # Manually build payload for known backend schema
    return {
        "printer_uuid": printer_uuid,
        "external_ip": env_info.get("external_ip"),
        "status": env_info.get("printer_status"),
        "last_checkin": int(time.time()),
    }

def main():
    import os
    verbosity = os.environ.get("TICKET_PRINTER_VERBOSITY", "INFO")
    setup_logging(verbosity)
    logger = logging.getLogger(__name__)

    # Check for updates before check-in
    latest_tag = get_latest_github_release()
    current_tag = get_current_git_tag()
    if latest_tag and current_tag and latest_tag != current_tag:
        logger.warning(f"A new release is available: {latest_tag}. You are on {current_tag}.")
        logger.info("To upgrade, run:")
        logger.info(f"  git fetch --tags && git checkout {latest_tag} && .venv/bin/uv pip install -r requirements.txt")
    elif latest_tag and current_tag:
        logger.info(f"You are running the latest release: {current_tag}.")
    else:
        logger.warning("Could not determine update status.")

    # Print test ticket on startup
    printer_uuid = get_printer_uuid()
    local_ip = get_local_ip()
    env_info = gather_env_info()
    external_ip = env_info.get("external_ip", "Unknown")
    last_checkin_date = env_info.get("last_checkin", "Unknown")
    logger.info("Printing test ticket on startup:")
    print_test_ticket(printer_uuid, local_ip, external_ip, last_checkin_date, env_info)
    env_info = gather_env_info()
    printer_uuid = get_printer_uuid()
    payload = build_checkin_payload(env_info, printer_uuid)
    logger.info("Check-in payload:")
    logger.info(json.dumps(payload, indent=2))
    try:
        response = requests.post(BACKEND_URL, json=payload, timeout=5)
        logger.info(f"Check-in response: {response.status_code} {response.text}")
    except Exception as e:
        logger.error(f"Check-in failed: {e}")

if __name__ == "__main__":
    main()
