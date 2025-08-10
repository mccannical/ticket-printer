"""Core check-in logic for ticket-printer service.

Responsibilities:
 - Persistent printer UUID management
 - Environment information gathering (delegated to env_info)
 - GitHub release awareness (log-only, no auto-upgrade)
 - Payload construction & schema validation
 - Resilient HTTP POST with retries
 - Test ticket printing at startup
"""

from __future__ import annotations

import json
import logging
import os
import socket
import sys
import time
import uuid
import stat
from typing import Any, Dict, Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

try:  # Optional journald integration
    from systemd.journal import JournaldLogHandler  # type: ignore

    SYSTEMD_AVAILABLE = True
except ImportError:  # pragma: no cover - systemd rarely available in test
    SYSTEMD_AVAILABLE = False

try:
    from src.env_info import gather_env_info
except ImportError:  # Fallback if executed from inside src without package context
    try:  # pragma: no cover - legacy/edge runtime path
        from env_info import gather_env_info  # type: ignore
    except ImportError:  # Re-raise original
        raise
from src.schema_utils import validate_schema

GITHUB_REPO = "mccannical/ticket-printer"
BACKEND_URL = "https://checkoff.mccannical.com/printer_checkin"  # Update as needed
DEFAULT_TIMEOUT = 5


def _compute_version() -> str:
    """Return current version string derived from git tag or env override.

    Precedence:
      1. Env var TICKET_PRINTER_VERSION (allows packaging systems to inject)
      2. Closest git tag (describe --tags --abbrev=0) with leading 'v' stripped
      3. Commit hash (first 7) prefixed with 'git-'
      4. Literal 'unknown'
    """
    override = os.environ.get("TICKET_PRINTER_VERSION")
    if override:
        return override.lstrip("v")
    try:
        import subprocess

        tag = subprocess.check_output([
            "git",
            "describe",
            "--tags",
            "--abbrev=0",
        ]).decode().strip()
        if tag:
            return tag.lstrip("v")
    except Exception:  # pragma: no cover - git not always present
        try:
            import subprocess

            commit = (
                subprocess.check_output(["git", "rev-parse", "--short", "HEAD"]).decode().strip()
            )
            if commit:
                return f"git-{commit}"
        except Exception:
            pass
    return "unknown"


VERSION = _compute_version()
USER_AGENT = f"TicketPrinter/{VERSION}"

# JSON Schema for outbound payload
PAYLOAD_SCHEMA = {
    "type": "object",
    "properties": {
        "printer_uuid": {"type": "string"},
        "external_ip": {"type": "string"},
        "status": {"type": "string"},
        "last_checkin": {"type": "integer"},
    },
    "required": ["printer_uuid", "external_ip", "status", "last_checkin"],
}


def setup_logging(verbosity: str = "INFO") -> None:
    """Configure root logger for service (journald if available else stderr)."""
    level = getattr(logging, verbosity.upper(), logging.INFO)
    logger = logging.getLogger()
    logger.setLevel(level)
    for h in logger.handlers[:]:  # Clear existing
        logger.removeHandler(h)
    if SYSTEMD_AVAILABLE:  # pragma: no cover
        handler = JournaldLogHandler()
    else:
        handler = logging.StreamHandler(sys.stderr)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)


def _build_retrying_session() -> requests.Session:
    retry = Retry(
        total=3,
        backoff_factor=0.5,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET", "POST"),
    )
    adapter = HTTPAdapter(max_retries=retry)
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


SESSION = _build_retrying_session()


def get_local_ip() -> str:
    """Return best-effort local IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:  # pragma: no cover - environment dependent
        return "Unknown"


def print_test_ticket(
    printer_uuid: str,
    local_ip: str,
    external_ip: str,
    last_checkin_date: str,
    last_checkin_data: Dict[str, Any],
) -> None:
    """Print a multi-line diagnostic ticket for operator visibility."""
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


def get_latest_github_release() -> Optional[str]:
    """Return latest release tag from GitHub or None on error."""
    api_url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
    try:
        resp = SESSION.get(api_url, timeout=DEFAULT_TIMEOUT)
        resp.raise_for_status()
        return resp.json().get("tag_name")
    except Exception:
        logging.getLogger(__name__).debug("Failed to fetch latest release", exc_info=True)
        return None


def get_current_git_tag() -> Optional[str]:
    """Return current git tag or commit hash, else None."""
    import subprocess  # Local import to avoid cost when frozen

    try:
        return subprocess.check_output(["git", "describe", "--tags", "--abbrev=0"]).decode().strip()
    except Exception:
        try:
            return subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()
        except Exception:
            return None


def get_printer_uuid() -> str:
    """Return persistent UUID1 (create on first run) stored with restrictive permissions.

    Config directory can be overridden with env var TICKET_PRINTER_CONFIG_DIR.
    Directory permission: 700, file permission: 600 (best effort on non-Windows).
    """
    base_dir = os.environ.get(
        "TICKET_PRINTER_CONFIG_DIR",
        os.path.join(os.path.dirname(os.path.dirname(__file__)), "config"),
    )
    uuid_file = os.path.join(base_dir, "printer_uuid.txt")
    try:
        if not os.path.exists(base_dir):
            os.makedirs(base_dir, exist_ok=True)
            try:
                os.chmod(base_dir, 0o700)
            except Exception:  # pragma: no cover - permission errors ignored
                pass
        else:
            # Tighten existing dir if too open (> 755)
            try:
                mode = stat.S_IMODE(os.stat(base_dir).st_mode)
                if mode & 0o077:
                    os.chmod(base_dir, 0o700)
            except Exception:
                pass
    except Exception:
        logging.getLogger(__name__).warning("Failed to ensure config directory at %s", base_dir)

    if os.path.exists(uuid_file):
        try:
            with open(uuid_file, "r", encoding="utf-8") as f:
                existing = f.read().strip()
                if existing:
                    return existing
        except Exception:  # pragma: no cover
            pass

    new_uuid = str(uuid.uuid1())
    try:
        with open(uuid_file, "w", encoding="utf-8") as f:
            f.write(new_uuid)
        try:
            os.chmod(uuid_file, 0o600)
        except Exception:  # pragma: no cover
            pass
    except Exception:  # pragma: no cover
        logging.getLogger(__name__).warning(
            "Failed to persist UUID at %s; using ephemeral value", uuid_file
        )
    return new_uuid


def build_checkin_payload(env_info: Dict[str, Any], printer_uuid: str) -> Dict[str, Any]:
    """Assemble outbound payload respecting backend contract."""
    return {
        "printer_uuid": printer_uuid,
        "external_ip": env_info.get("external_ip"),
        "status": env_info.get("printer_status"),
        "last_checkin": int(time.time()),
    }


def validate_payload(payload: Dict[str, Any]) -> None:
    """Validate payload against JSON schema (raises on failure)."""
    validate_schema(payload, PAYLOAD_SCHEMA)


def post_payload(payload: Dict[str, Any], logger: logging.Logger) -> None:
    try:
        resp = SESSION.post(BACKEND_URL, json=payload, timeout=DEFAULT_TIMEOUT)
        logger.info("Check-in response: %s %s", resp.status_code, resp.text[:300])
    except Exception as e:  # pragma: no cover - network variability
        logger.error("Check-in failed: %s", e)


def main() -> None:
    verbosity = os.environ.get("TICKET_PRINTER_VERBOSITY", "INFO")
    setup_logging(verbosity)
    logger = logging.getLogger(__name__)

    latest_tag = get_latest_github_release()
    current_tag = get_current_git_tag()
    if latest_tag and current_tag and latest_tag != current_tag:
        logger.warning(
            "New release: %s (current %s). Run fetch tags, checkout, install requirements",
            latest_tag,
            current_tag,
        )
    elif latest_tag and current_tag:
        logger.info("Running latest release: %s", current_tag)
    else:
        logger.info("Unable to determine update status (possibly not a git repo)")

    env_info = gather_env_info()
    printer_uuid = get_printer_uuid()
    local_ip = get_local_ip()
    external_ip = env_info.get("external_ip", "Unknown")
    last_checkin_date = env_info.get("last_checkin", "Unknown")
    logger.info("Printing startup test ticket")
    print_test_ticket(printer_uuid, local_ip, external_ip, last_checkin_date, env_info)

    payload = build_checkin_payload(env_info, printer_uuid)
    try:
        validate_payload(payload)
    except Exception as e:
        logger.error("Payload validation failed: %s", e)
        return
    logger.debug("Payload: %s", json.dumps(payload, indent=2))
    post_payload(payload, logger)


if __name__ == "__main__":  # pragma: no cover
    main()
