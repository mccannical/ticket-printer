from src.env_info import get_printer_status

def test_get_printer_status_runs():
    status = get_printer_status()
    assert isinstance(status, str)
    assert "printer" in status.lower() or "error" in status.lower() or "no default" in status.lower()
