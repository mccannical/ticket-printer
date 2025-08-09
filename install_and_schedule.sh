#!/bin/bash
set -e

# Usage instructions for curl | bash
usage() {
  echo "\nUsage:"
  echo "  curl -fsSL <RAW_SCRIPT_URL> | bash -s -- <GITHUB_REPO_URL> <BRANCH_OR_TAG> <INSTALL_DIR>"
  echo "\nExample:"
  echo "  curl -fsSL https://raw.githubusercontent.com/mccannical/ticket-printer/main/install_and_schedule.sh | bash -s -- https://github.com/mccannical/ticket-printer.git main ~/ticket-printer"
  exit 1
}

# Parse arguments
if [ "$#" -ne 3 ]; then
  usage
fi

REPO_URL="$1"
BRANCH_OR_TAG="$2"
INSTALL_DIR="$3"

# Install git if not present
if ! command -v git &> /dev/null; then
  echo "[INFO] Installing git..."
  sudo apt-get update && sudo apt-get install -y git uv ruff python3-pip

fi

# Install python3-venv and pip if not present
if ! python3 -m venv --help &> /dev/null; then
  echo "[INFO] Installing python3-venv..."
  sudo apt-get update && sudo apt-get install -y python3-venv
fi
if ! command -v pip &> /dev/null; then
  echo "[INFO] Installing pip..."
  sudo apt-get update && sudo apt-get install -y python3-pip
fi

# Clone or update the repo
if [ ! -d "$INSTALL_DIR" ]; then
  echo "[INFO] Cloning repository..."
  git clone --branch "$BRANCH_OR_TAG" "$REPO_URL" "$INSTALL_DIR"
else
  echo "[INFO] Updating repository..."
  cd "$INSTALL_DIR"
  git fetch
  git checkout "$BRANCH_OR_TAG"
  git pull
  cd -
fi

cd "$INSTALL_DIR"

# Create venv if not present
if [ ! -d ".venv" ]; then
  echo "[INFO] Creating virtual environment..."
  python3 -m venv .venv
fi

# Install uv in the venv
. .venv/bin/activate
uv pip install -r requirements.txt
deactivate

# Create cronjob to run every 15 minutes using venv's python and uv
CRON_CMD="cd $INSTALL_DIR && . .venv/bin/activate && uv python src/main.py >> checkin.log 2>&1"
CRON_JOB="*/15 * * * * $CRON_CMD"
# Remove any existing job for this app
(crontab -l 2>/dev/null | grep -v "$CRON_CMD" || true; echo "$CRON_JOB") | crontab -

echo "[INFO] Installation complete. Check-in will run every 15 minutes via cron using the venv."
