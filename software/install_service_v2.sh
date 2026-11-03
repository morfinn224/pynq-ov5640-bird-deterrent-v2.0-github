#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
chmod +x model_v2_armv7_no_xnnpack.eim run_integrated_v2.sh
mkdir -p logs
sudo install -m 0644 bird-deterrent-v2.service /etc/systemd/system/bird-deterrent.service
sudo systemctl daemon-reload
echo "Service installed but intentionally not enabled."
echo "After all hardware tests pass, enable with:"
echo "  sudo systemctl enable --now bird-deterrent.service"
