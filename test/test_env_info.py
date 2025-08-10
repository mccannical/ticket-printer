from src.checkin import get_local_ip
from src.env_info import get_printer_status


def test_get_printer_status_runs():
    status = get_printer_status()
    assert isinstance(status, str)
    lowered = status.lower()
    assert any(k in lowered for k in ["printer", "error", "no default"])  # broad match


def test_get_local_ip_best_effort():
    ip = get_local_ip()
    assert isinstance(ip, str)
    assert len(ip) > 0
