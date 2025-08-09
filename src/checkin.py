import json

import requests
from env_info import gather_env_info

BACKEND_URL = "https://ticket-backend-450362392516.us-central1.run.app/printer_checkin"  # Update as needed

# This should be unique per device in production
PRINTER_UUID = "002655c8-5337-42b7-a56d-e61e17799cf2"
USER_AGENT = "TicketPrinter/1.0"
USER_UUID = "00959d74-451f-4a54-8bd9-6ca12be2889c"

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
    env_info = gather_env_info()
    payload = build_checkin_payload(env_info, PRINTER_UUID)
    print("Check-in payload:")
    print(json.dumps(payload, indent=2))
    try:
        response = requests.post(BACKEND_URL, json=payload, timeout=5)
        print(f"Check-in response: {response.status_code} {response.text}")
    except Exception as e:
        print(f"Check-in failed: {e}")

if __name__ == "__main__":
    main()
