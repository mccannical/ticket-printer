import os
import uuid
from src import checkin

def test_printer_uuid_persistence(tmp_path, monkeypatch):
    # Use a temp config dir
    config_dir = tmp_path / "config"
    monkeypatch.setattr(checkin, "os", os)
    monkeypatch.setattr(checkin, "__file__", str(tmp_path / "src" / "checkin.py"))
    # First call should create a new UUID
    uuid1 = checkin.get_printer_uuid()
    assert uuid1
    # Second call should return the same UUID
    uuid2 = checkin.get_printer_uuid()
    assert uuid1 == uuid2
    # Should be a valid UUID1
    assert uuid.UUID(uuid1).version == 1

def test_checkin_payload_structure():
    env_info = {"external_ip": "1.2.3.4", "printer_status": "OK"}
    printer_uuid = str(uuid.uuid1())
    payload = checkin.build_checkin_payload(env_info, printer_uuid)
    assert payload["printer_uuid"] == printer_uuid
    assert payload["external_ip"] == "1.2.3.4"
    assert payload["status"] == "OK"
    assert isinstance(payload["last_checkin"], int)
