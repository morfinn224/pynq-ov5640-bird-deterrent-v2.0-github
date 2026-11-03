#!/usr/bin/env python3
"""PYNQ-Z2 onboard LEDs plus external-board control AXI GPIO self-test."""

import time
from pathlib import Path

from pynq import MMIO, Overlay

GPIO_BASE = 0x41200000
GPIO_RANGE = 0x1000
ONBOARD_DATA = 0x00
ONBOARD_TRI = 0x04
EXTERNAL_DATA = 0x08
EXTERNAL_TRI = 0x0C

STATES = (
    (0b000, 0b0000, "RESET/OFF: SD low"),
    (0b001, 0b0001, "BLUE: monitor/cooldown"),
    (0b010, 0b0010, "RED: bird/recheck"),
    (0b100, 0b1100, "YELLOW+SD: playback"),
    (0b000, 0b0000, "RESET/OFF: SD low"),
)


def main():
    bit_path = Path(__file__).resolve().with_name("pynq_frame_diff_bd_wrapper.bit")
    hwh_path = bit_path.with_suffix(".hwh")
    if not bit_path.exists() or not hwh_path.exists():
        raise FileNotFoundError("BIT/HWH must be beside led_gpio_selftest.py")

    print(f"Loading overlay: {bit_path}")
    Overlay(str(bit_path), download=True, ignore_version=True)

    gpio = MMIO(GPIO_BASE, GPIO_RANGE)
    gpio.write(ONBOARD_TRI, 0x00000000)
    gpio.write(EXTERNAL_TRI, 0x00000000)

    for onboard, external, label in STATES:
        gpio.write(EXTERNAL_DATA, external)
        gpio.write(ONBOARD_DATA, onboard)
        onboard_rb = gpio.read(ONBOARD_DATA) & 0x7
        external_rb = gpio.read(EXTERNAL_DATA) & 0xF
        print(
            f"onboard={onboard:03b}/{onboard_rb:03b} "
            f"external={external:04b}/{external_rb:04b} {label}"
        )
        if onboard_rb != onboard or external_rb != external:
            raise RuntimeError(
                "AXI GPIO readback mismatch: "
                f"onboard {onboard:#x}/{onboard_rb:#x}, "
                f"external {external:#x}/{external_rb:#x}"
            )
        time.sleep(1.0)

    print("PASS: onboard LEDs and external BLUE/RED/YELLOW/SD sequence")


if __name__ == "__main__":
    main()
