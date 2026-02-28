#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi

source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

python3 app.py
