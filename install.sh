#!/bin/bash
set -e

# --- CONFIG ---
REPO="mccannical/ticket-printer"
INSTALL_DIR="$HOME/ticket-printer"
BRANCH_OR_TAG="main"  # Set to desired branch; script can optionally pin to latest tag unless FORCE_MAIN=1
PYTHON_BIN="python3"
VENV_DIR=".venv"
CRON_MARKER="# ticket-printer managed"

# --- FUNCTIONS ---
function install_or_update_repo() {
	if [ ! -d "$INSTALL_DIR/.git" ]; then
		echo "[INFO] Cloning repo..."
		git clone --branch "$BRANCH_OR_TAG" "https://github.com/$REPO.git" "$INSTALL_DIR"
	else
		echo "[INFO] Pulling latest code..."
		cd "$INSTALL_DIR"
		git fetch --tags
		git checkout "$BRANCH_OR_TAG"
		git pull
		# If currently detached (possible from earlier runs), ensure we are on main before proceeding
		if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
			echo "[WARN] Detached HEAD detected; checking out $BRANCH_OR_TAG"
			git checkout "$BRANCH_OR_TAG"
		fi
		cd -
	fi
}

function setup_venv() {
	cd "$INSTALL_DIR"
	if [ ! -d "$VENV_DIR" ]; then
		$PYTHON_BIN -m venv "$VENV_DIR"
	fi
	source "$VENV_DIR/bin/activate"
	pip install --upgrade pip
	pip install -r requirements.txt
	deactivate
	cd -
}

function check_for_update_and_print() {
	cd "$INSTALL_DIR"
	source "$VENV_DIR/bin/activate"

	if [ "${FORCE_MAIN:-0}" = "1" ]; then
		echo "[INFO] FORCE_MAIN=1 set; skipping tag switch. Staying on $BRANCH_OR_TAG."
		deactivate
		cd -
		return 0
	fi

	# Determine highest semantic version tag locally (fetch first)
	git fetch --tags >/dev/null 2>&1 || true
	LATEST_TAG=$(git tag -l 'v*' --sort=-v:refname | head -n1)
	CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo "unknown")

	CURR_VER=${CURRENT_TAG#v}
	LATEST_VER=${LATEST_TAG#v}

	# Helper: is semantic version
	if [[ $CURR_VER =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ $LATEST_VER =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		# Compare versions; if latest > current then upgrade
		HIGHEST=$(printf '%s\n%s' "$CURR_VER" "$LATEST_VER" | sort -V | tail -n1)
		if [ "$HIGHEST" = "$LATEST_VER" ] && [ "$CURR_VER" != "$LATEST_VER" ]; then
			echo "[INFO] Newer tag available: v$LATEST_VER (current v$CURR_VER). Upgrading..."
			git checkout "v$LATEST_VER"
			pip install -r requirements.txt
			PYTHONPATH="$INSTALL_DIR" $PYTHON_BIN -c "from src.checkin import print_test_ticket, get_printer_uuid, get_local_ip; from src.env_info import gather_env_info; import json; printer_uuid=get_printer_uuid(); local_ip=get_local_ip(); env_info=gather_env_info(); external_ip=env_info.get('external_ip','Unknown'); last_checkin=env_info.get('last_checkin','Unknown'); print_test_ticket(printer_uuid, local_ip, external_ip, last_checkin, env_info)"
		else
			echo "[INFO] Current version ($CURRENT_TAG) is up-to-date; no upgrade performed."
		fi
	else
		# If current is not semver (e.g., on main commit), upgrade only if we have a tag and not already on it
		if [ -n "$LATEST_TAG" ] && [ "$CURRENT_TAG" != "$LATEST_TAG" ]; then
			echo "[INFO] Switching to latest tag $LATEST_TAG from $CURRENT_TAG..."
			git checkout "$LATEST_TAG"
			pip install -r requirements.txt
			PYTHONPATH="$INSTALL_DIR" $PYTHON_BIN -c "from src.checkin import print_test_ticket, get_printer_uuid, get_local_ip; from src.env_info import gather_env_info; import json; printer_uuid=get_printer_uuid(); local_ip=get_local_ip(); env_info=gather_env_info(); external_ip=env_info.get('external_ip','Unknown'); last_checkin=env_info.get('last_checkin','Unknown'); print_test_ticket(printer_uuid, local_ip, external_ip, last_checkin, env_info)"
		else
			echo "[INFO] No semantic version tags found or already on latest commit."
		fi
	fi

	deactivate
	cd -
}

function print_test_ticket_on_boot() {
	cd "$INSTALL_DIR"
	source "$VENV_DIR/bin/activate"
	PYTHONPATH="$INSTALL_DIR" $PYTHON_BIN -c "from src.checkin import print_test_ticket, get_printer_uuid, get_local_ip; from src.env_info import gather_env_info; import json; printer_uuid=get_printer_uuid(); local_ip=get_local_ip(); env_info=gather_env_info(); external_ip=env_info.get('external_ip','Unknown'); last_checkin=env_info.get('last_checkin','Unknown'); print_test_ticket(printer_uuid, local_ip, external_ip, last_checkin, env_info)"
	deactivate
	cd -
}

function print_chores_message() {
	cd "$INSTALL_DIR"
	source "$VENV_DIR/bin/activate"
	PYTHONPATH="$INSTALL_DIR" $PYTHON_BIN -c "print('chores today:')"
	deactivate
	cd -
}

# --- MAIN LOGIC ---
install_or_update_repo
setup_venv
check_for_update_and_print

# --- CRON SETUP ---
# Remove old jobs
crontab -l 2>/dev/null | grep -v "$CRON_MARKER" >/tmp/cron.tmp || true
# Add hourly self-update
(echo "0 * * * * bash $INSTALL_DIR/install.sh $CRON_MARKER") >>/tmp/cron.tmp
# Add boot job
(echo "@reboot bash $INSTALL_DIR/install.sh boot $CRON_MARKER") >>/tmp/cron.tmp
# Add daily 6am job
(echo "0 6 * * * bash $INSTALL_DIR/install.sh chores $CRON_MARKER") >>/tmp/cron.tmp
crontab /tmp/cron.tmp
rm /tmp/cron.tmp

# --- HANDLE SPECIAL MODES ---
if [ "$1" = "boot" ]; then
	print_test_ticket_on_boot
	exit 0
fi
if [ "$1" = "chores" ]; then
	print_chores_message
	exit 0
fi

# --- NORMAL RUN ---
cd "$INSTALL_DIR"
source "$VENV_DIR/bin/activate"
PYTHONPATH="$INSTALL_DIR" $PYTHON_BIN -m src.main
