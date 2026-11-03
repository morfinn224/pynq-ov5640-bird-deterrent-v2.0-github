#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

exec sudo -E /usr/local/share/pynq-venv/bin/python3 \
  run_pynq_integrated_loop.py \
  model_v2_armv7_no_xnnpack.eim \
  sounds/warning_1_sweep.wav \
  sounds/warning_2_alternating.wav \
  sounds/warning_3_irregular.wav \
  --monitor-threshold 0.80 \
  --recheck-threshold 0.60 \
  --dac-address 0x60 \
  --audio-volume 0.05 \
  "$@"
