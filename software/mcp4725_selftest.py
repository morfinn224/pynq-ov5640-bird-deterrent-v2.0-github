from __future__ import annotations

import argparse
import time
from pathlib import Path

from pynq import Overlay

from controller import Led
from hardware_adapters import Mcp4725AudioPlayer, PynqAxiGpioLedDriver


def main() -> None:
    parser = argparse.ArgumentParser(description="MCP4725 + PAM8302A staged self-test")
    parser.add_argument("--bit", type=Path, default=Path("pynq_frame_diff_bd_wrapper.bit"))
    parser.add_argument("--address", type=lambda value: int(value, 0), default=0x60)
    parser.add_argument("--volume", type=float, default=0.02)
    parser.add_argument("--tone", action="store_true", help="enable SD and play a quiet 440 Hz tone")
    args = parser.parse_args()

    bit_path = args.bit.resolve()
    if not bit_path.is_file() or not bit_path.with_suffix(".hwh").is_file():
        raise FileNotFoundError("matching v2.0 BIT/HWH files are required")

    overlay = Overlay(str(bit_path), download=True, ignore_version=True)
    leds = PynqAxiGpioLedDriver()
    player = None
    try:
        player = Mcp4725AudioPlayer(
            overlay,
            address=args.address,
            volume=args.volume,
        )
        print("MCP4725_ACK_OK")
        for code in (1024, 2048, 3072, 2048):
            player.set_code(code)
            print(f"DAC_CODE={code}; measure H1-5 to GND now")
            time.sleep(3)
        if args.tone:
            print("QUIET_TONE_START volume=", args.volume)
            leds.set(Led.YELLOW)
            player.play_tone(440.0, 1.0)
            leds.off()
            print("QUIET_TONE_DONE")
        print("PASS: MCP4725 staged self-test")
    finally:
        if player is not None:
            try:
                player.set_code(2048)
            except Exception:
                pass
        leds.off()


if __name__ == "__main__":
    main()
