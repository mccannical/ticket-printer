#!/bin/bash
set -e
umask 027

# Detect being executed via sudo with process substitution which loses /dev/fd handle
if [[ "$0" =~ ^/dev/fd/ && -n "${SUDO_USER:-}" ]]; then
	echo "[WARN] Script appears to be run via process substitution with sudo (e.g. sudo bash <(curl ...)). This can fail on some systems." >&2
	echo "[HINT] Prefer: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sudo PRINTER_USER=printer bash" >&2
	sleep 1
fi

# --- CONFIG ---
REPO="mccannical/ticket-printer"
# Allow override via env; default system-wide path
INSTALL_DIR="${INSTALL_DIR:-/opt/ticket-printer}"
PYTHON_BIN="python3"
VENV_DIR=".venv"
CRON_MARKER="# ticket-printer managed"
PRINTER_USER="${PRINTER_USER:-printer}"  # Optional system user expected to run the service

# --- Early permission sanity check ---
PARENT_DIR="$(dirname "$INSTALL_DIR")"
if [ ! -d "$PARENT_DIR" ]; then
	if ! mkdir -p "$PARENT_DIR" 2>/dev/null; then
		echo "[ERROR] Cannot create parent directory $PARENT_DIR. Run with sudo or choose a writable INSTALL_DIR (e.g. \"$HOME/ticket-printer\")." >&2
		exit 1
	fi
fi
if [ ! -w "$PARENT_DIR" ]; then
	if [ "$(id -u)" -ne 0 ]; then
		case "$INSTALL_DIR" in
			/opt/*|/usr/*)
				echo "[ERROR] No write permission for $PARENT_DIR. Re-run with: sudo INSTALL_DIR=$INSTALL_DIR bash <(curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh)" >&2
				exit 1
				;;
			*)
				echo "[ERROR] No write permission for $PARENT_DIR. Pick a different INSTALL_DIR within your home directory." >&2
				exit 1
				;;
		esac
	fi
fi

# Release selection strategy:
# CHANNEL=stable (default) -> track latest GitHub release tag (vX.Y.Z)
# CHANNEL=main            -> track main branch (development)
# VERSION=<tag>           -> pin to specific tag (overrides CHANNEL)
# Legacy FORCE_MAIN=1 maps to CHANNEL=main

CHANNEL_ENV=${CHANNEL:-}
if [ "${FORCE_MAIN:-0}" = "1" ] && [ -z "$CHANNEL_ENV" ]; then
	CHANNEL_ENV="main"
fi
CHANNEL=${CHANNEL_ENV:-stable}
VERSION=${VERSION:-}

CONFIG_FILE="$INSTALL_DIR/.install_env"

# Load persisted config if exists (unless overriding with explicit env vars this run)
if [ -f "$CONFIG_FILE" ]; then
	# shellcheck disable=SC1090
	. "$CONFIG_FILE"
	# Allow explicit env overrides to win
	[ -n "$CHANNEL_ENV" ] && CHANNEL="$CHANNEL_ENV"
	[ -n "$VERSION" ] && VERSION="$VERSION"
fi

# Persist config (idempotent; updates if changed)
mkdir -p "$INSTALL_DIR" 2>/dev/null || true
cat >"$CONFIG_FILE.tmp" <<EOF
CHANNEL=$CHANNEL
VERSION=$VERSION
EOF
if ! cmp -s "$CONFIG_FILE.tmp" "$CONFIG_FILE" 2>/dev/null; then
	mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
else
	rm "$CONFIG_FILE.tmp"
fi

echo "[INFO] Channel=$CHANNEL Version=${VERSION:-<auto>}"

# --- FUNCTIONS ---
function get_latest_release_tag() {
	# Returns latest release tag via GitHub API or empty string
	local latest
	latest=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep -m1 '"tag_name"' | cut -d '"' -f4 || true)
	printf '%s' "$latest"
}

function _current_version() {
	git describe --tags --abbrev=0 2>/dev/null || echo "main"
}

function print_changelog_updates() {
	# Args: previous_version current_version
	# Prints CHANGELOG sections newer than previous_version (or latest section if previous empty)
	[ "${SKIP_CHANGELOG:-0}" = "1" ] && return 0
	local prev="$1" curr="$2" file="$INSTALL_DIR/CHANGELOG.md"
	[ ! -f "$file" ] && return 0
	echo "==================== CHANGELOG (${prev:-new install} -> ${curr}) ===================="
	if [ -z "$prev" ] || [ "$prev" = "main" ]; then
		awk '/^### v/{if(++c>1) exit} {print}' "$file"
	elif [ "$prev" != "$curr" ]; then
		awk -v prev="$prev" 'BEGIN{p=1} /^### v/{ if($2==prev){exit} } { if(p) print }' "$file"
	else
		# Same version; maybe first install pinned to existing version
		awk '/^### v/{if(++c>1) exit} {print}' "$file"
	fi
	echo "================================================================================"
}

function validate_origin() {
	local origin
	origin=$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || echo "")
	if [ -n "$origin" ]; then
		case "$origin" in
			*"github.com/${REPO}.git"|*"github.com/${REPO}") ;; # ok
			*)
				echo "[ERROR] Remote origin mismatch ($origin) expected https://github.com/${REPO}. Possible tampering." >&2
				exit 1
				;;
		esac
	fi
}

function tighten_permissions() {
	if [ -d "$INSTALL_DIR" ]; then
		chmod 750 "$INSTALL_DIR" 2>/dev/null || true
		find "$INSTALL_DIR" -maxdepth 1 -type f -name '*.sh' -exec chmod 750 {} + 2>/dev/null || true
	fi
}

function install_or_update_repo() {
	if [ ! -d "$INSTALL_DIR/.git" ]; then
		# Directory exists but is not a git repo
		if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
			if [ "${FORCE_REPLACE:-0}" = "1" ]; then
				echo "[WARN] Removing existing non-git directory $INSTALL_DIR (FORCE_REPLACE=1)"
				rm -rf "$INSTALL_DIR"
			else
				echo "[ERROR] $INSTALL_DIR exists and is not empty. Set FORCE_REPLACE=1 to overwrite, or set INSTALL_DIR to a different path." >&2
				echo "[HINT] If you tried 'FORCE_REPLACE=1 curl ... | bash' the variable only applied to curl. Instead use: export FORCE_REPLACE=1; curl ... | bash  OR  curl ... | FORCE_REPLACE=1 bash" >&2
				exit 1
			fi
		fi
		echo "[INFO] Cloning repo (initial install) into $INSTALL_DIR..."
		mkdir -p "$INSTALL_DIR"
		git clone "https://github.com/$REPO.git" "$INSTALL_DIR"
		cd "$INSTALL_DIR" || exit 1
		git fetch --tags --quiet || true
		if [ -n "$VERSION" ]; then
			if git rev-parse "$VERSION" >/dev/null 2>&1; then
				echo "[INFO] Checking out specified version $VERSION"
				git checkout "$VERSION"
			else
				echo "[ERROR] Specified VERSION $VERSION not found; staying on main" >&2
			fi
		elif [ "$CHANNEL" = "stable" ]; then
			LATEST_TAG=$(get_latest_release_tag)
			if [ -n "$LATEST_TAG" ] && git rev-parse "$LATEST_TAG" >/dev/null 2>&1; then
				echo "[INFO] Checking out latest release $LATEST_TAG"
				git checkout "$LATEST_TAG"
			else
				echo "[WARN] Could not resolve latest release tag; staying on main"
			fi
		else
			echo "[INFO] Staying on main branch (channel=main)"
		fi
		validate_origin
		tighten_permissions
		cd - >/dev/null || true
	else
		echo "[INFO] Updating existing repo at $INSTALL_DIR..."
		cd "$INSTALL_DIR" || exit 1
		git fetch --tags --quiet || true
		if [ -n "$VERSION" ]; then
			if git rev-parse "$VERSION" >/dev/null 2>&1; then
				git checkout "$VERSION" 2>/dev/null || true
			else
				echo "[ERROR] Desired VERSION $VERSION not found; leaving current HEAD" >&2
			fi
		elif [ "$CHANNEL" = "main" ]; then
			git checkout main 2>/dev/null || true
			git pull --ff-only || git pull || true
		fi
		validate_origin
		tighten_permissions
		cd - >/dev/null || true
	fi
}

function ensure_printer_user_access() {
	# If a PRINTER_USER exists on the system and we have privileges, ensure it owns the install dir.
	if id -u "$PRINTER_USER" >/dev/null 2>&1; then
		if [ "$(id -u)" -eq 0 ]; then
			# Only chown if not already owned by target user to avoid unnecessary churn
			current_owner=$(stat -c '%U' "$INSTALL_DIR" 2>/dev/null || stat -f '%Su' "$INSTALL_DIR" 2>/dev/null || echo "")
			if [ "$current_owner" != "$PRINTER_USER" ]; then
				echo "[INFO] Setting ownership of $INSTALL_DIR to $PRINTER_USER (recursive)"
				chown -R "$PRINTER_USER":"$PRINTER_USER" "$INSTALL_DIR" || echo "[WARN] Failed to chown $INSTALL_DIR" >&2
			fi
		else
			# Not root; check write access for printer user by group membership suggestion
			if [ ! -w "$INSTALL_DIR" ]; then
				echo "[WARN] Not root; cannot adjust ownership. To allow user '$PRINTER_USER' access, run: sudo chown -R $PRINTER_USER:$PRINTER_USER $INSTALL_DIR" >&2
			fi
		fi
	else
		echo "[INFO] PRINTER_USER '$PRINTER_USER' not present; skipping ownership adjustment (set PRINTER_USER= or create user to enable)."
	fi
}

function setup_venv() {
	cd "$INSTALL_DIR"
	if [ ! -d "$VENV_DIR" ]; then
		$PYTHON_BIN -m venv "$VENV_DIR"
	fi
	source "$VENV_DIR/bin/activate"
	pip install --upgrade pip
	if [ -f requirements.runtime.txt ]; then
		pip install -r requirements.runtime.txt
	else
		pip install -r requirements.txt
	fi
	deactivate
	cd -
}

function check_for_update_and_print() {
	cd "$INSTALL_DIR"
	source "$VENV_DIR/bin/activate"

	if [ -n "$VERSION" ]; then
		# Pin to explicit version; nothing to auto-update unless version changed externally
		TARGET="$VERSION"
		if git rev-parse "$TARGET" >/dev/null 2>&1; then
			if ! git describe --tags --exact-match >/dev/null 2>&1 || [ "$(git describe --tags --exact-match 2>/dev/null)" != "$TARGET" ]; then
				echo "[INFO] Switching to pinned version $TARGET"
				git checkout "$TARGET" || echo "[ERROR] Could not checkout $TARGET" >&2
			fi
		else
			echo "[ERROR] VERSION $TARGET not found; skipping switch" >&2
		fi
	elif [ "$CHANNEL" = "stable" ]; then
		REMOTE_LATEST=$(get_latest_release_tag)
		LOCAL_CURRENT=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
		if [ -n "$REMOTE_LATEST" ] && [ "$REMOTE_LATEST" != "$LOCAL_CURRENT" ]; then
			echo "[INFO] Upgrading from $LOCAL_CURRENT to $REMOTE_LATEST"
			git fetch --tags --quiet || true
			git checkout "$REMOTE_LATEST" || echo "[ERROR] Failed to checkout $REMOTE_LATEST" >&2
		else
			echo "[INFO] Already on latest stable ($LOCAL_CURRENT)"
		fi
	else
		# main channel
		git checkout main 2>/dev/null || true
		git pull --ff-only || git pull || true
	fi

	# Always (re)install dependencies after potential switch
	if [ -f requirements.runtime.txt ]; then
		pip install -r requirements.runtime.txt >/dev/null 2>&1 || pip install -r requirements.runtime.txt
	else
		pip install -r requirements.txt >/dev/null 2>&1 || pip install -r requirements.txt
	fi
	PYTHONPATH="$INSTALL_DIR" $PYTHON_BIN -c "from src.checkin import print_test_ticket, get_printer_uuid, get_local_ip; from src.env_info import gather_env_info; import json; printer_uuid=get_printer_uuid(); local_ip=get_local_ip(); env_info=gather_env_info(); external_ip=env_info.get('external_ip','Unknown'); last_checkin=env_info.get('last_checkin','Unknown'); print_test_ticket(printer_uuid, local_ip, external_ip, last_checkin, env_info)"

	deactivate
	cd - >/dev/null
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
PRE_VERSION=""
if [ -d "$INSTALL_DIR/.git" ]; then
	PRE_VERSION=$(cd "$INSTALL_DIR" && _current_version)
fi
install_or_update_repo
ensure_printer_user_access
setup_venv
tighten_permissions
POST_VERSION=$(cd "$INSTALL_DIR" && _current_version)
if [ "$PRE_VERSION" != "$POST_VERSION" ]; then
	print_changelog_updates "$PRE_VERSION" "$POST_VERSION" || true
fi
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
