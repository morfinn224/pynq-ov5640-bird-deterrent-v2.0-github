from __future__ import annotations

import time
from pathlib import Path

import numpy as np

WIDTH = 320
HEIGHT = 240
LINE_BYTES = WIDTH * 2
VDMA_BASE = 0x43000000
VDMA_RANGE = 0x10000
CTRL_BASE = 0x40002000
CTRL_RANGE = 0x1000
EXPECTED_VERSION = 0x00020000
EXPECTED_CAMERA_ID = 0x5640
PARK_PTR = 0x28
S2MM_DMACR = 0x30
S2MM_DMASR = 0x34
S2MM_VSIZE = 0xA0
S2MM_HSIZE = 0xA4
S2MM_STRIDE = 0xA8
S2MM_START_ADDRESS_1 = 0xAC
S2MM_START_ADDRESS_2 = 0xB0
S2MM_SYNC_ERROR_MASK = 0x0000C990
S2MM_FATAL_ERROR_MASK = 0x00000060
S2MM_FRAME_IRQ = 0x00001000


def rgb565_to_rgb888(frame: np.ndarray) -> np.ndarray:
    value = frame.astype(np.uint16, copy=False)
    red = ((value >> 11) & 0x1F).astype(np.uint8)
    green = ((value >> 5) & 0x3F).astype(np.uint8)
    blue = (value & 0x1F).astype(np.uint8)
    return np.dstack(((red << 3) | (red >> 2), (green << 2) | (green >> 4), (blue << 3) | (blue >> 2)))


class PynqRgb565Camera:
    def __init__(self, bit_path: str | Path):
        try:
            from pynq import MMIO, Overlay, allocate
        except ImportError as exc:
            raise RuntimeError("PynqRgb565Camera must run in the PYNQ environment") from exc
        self.bit_path = Path(bit_path).resolve()
        if not self.bit_path.is_file() or not self.bit_path.with_suffix(".hwh").is_file():
            raise FileNotFoundError("Matching BIT/HWH files are required")
        self.overlay = Overlay(str(self.bit_path), download=True, ignore_version=True)
        self.ctrl = MMIO(CTRL_BASE, CTRL_RANGE)
        self.vdma = MMIO(VDMA_BASE, VDMA_RANGE)
        self._check_camera_ready()
        self.buffers = [
            allocate(shape=(HEIGHT, WIDTH), dtype=np.uint16),
            allocate(shape=(HEIGHT, WIDTH), dtype=np.uint16),
        ]

    def _check_camera_ready(self) -> None:
        version = self.ctrl.read(0x14)
        if version != EXPECTED_VERSION:
            raise RuntimeError(f"Overlay version mismatch: 0x{version:08X}")
        deadline = time.monotonic() + 5.0
        while True:
            status = self.ctrl.read(0x1C)
            if status & 0x2:
                raise RuntimeError(f"OV5640 initialization error: 0x{status:08X}")
            if (status & 0x5) == 0x5:
                break
            if time.monotonic() >= deadline:
                raise TimeoutError(f"OV5640 initialization timeout: 0x{status:08X}")
            time.sleep(0.05)
        chip_id = self.ctrl.read(0x20) & 0xFFFF
        if chip_id != EXPECTED_CAMERA_ID:
            raise RuntimeError(f"OV5640 ID mismatch: 0x{chip_id:04X}")
        test_pattern = self.ctrl.read(0x2C)
        if test_pattern & 0x301:
            raise RuntimeError(
                f"Camera is not in real-scene mode: TEST_PATTERN=0x{test_pattern:08X}"
            )

    def _wait_reset_done(self) -> None:
        self.vdma.write(S2MM_DMACR, 0x4)
        deadline = time.monotonic() + 1.0
        while self.vdma.read(S2MM_DMACR) & 0x4:
            if time.monotonic() >= deadline:
                raise TimeoutError("VDMA S2MM reset timeout")
            time.sleep(0.001)

    def capture_rgb(self, timeout_s: float = 5.0) -> np.ndarray:
        for buffer in self.buffers:
            buffer[:] = 0
            buffer.flush()
        self._wait_reset_done()
        self.vdma.write(S2MM_START_ADDRESS_1, self.buffers[0].physical_address)
        self.vdma.write(S2MM_START_ADDRESS_2, self.buffers[1].physical_address)
        self.vdma.write(S2MM_STRIDE, LINE_BYTES)
        self.vdma.write(S2MM_HSIZE, LINE_BYTES)
        self.vdma.write(S2MM_DMACR, 0x00001003)
        self.vdma.write(S2MM_VSIZE, HEIGHT)
        deadline = time.monotonic() + timeout_s
        clean_frames = 0
        try:
            while clean_frames < 2:
                status = self.vdma.read(S2MM_DMASR)
                if status & S2MM_FATAL_ERROR_MASK:
                    raise RuntimeError(f"VDMA S2MM error: 0x{status:08X}")
                sync_errors = status & S2MM_SYNC_ERROR_MASK
                if sync_errors:
                    self.vdma.write(S2MM_DMASR, sync_errors | (status & S2MM_FRAME_IRQ))
                    clean_frames = 0
                elif status & S2MM_FRAME_IRQ:
                    self.vdma.write(S2MM_DMASR, S2MM_FRAME_IRQ)
                    clean_frames += 1
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"Complete-frame timeout: 0x{status:08X}")
                time.sleep(0.005)
            current_write = (self.vdma.read(PARK_PTR) >> 24) & 0x1F
            completed = (current_write ^ 1) & 0x1
            self.vdma.write(S2MM_DMACR, 0)
            self.buffers[completed].invalidate()
            return rgb565_to_rgb888(np.array(self.buffers[completed], copy=True))
        finally:
            self.vdma.write(S2MM_DMACR, 0)

    def close(self) -> None:
        self.vdma.write(S2MM_DMACR, 0)
        for buffer in self.buffers:
            buffer.freebuffer()

    def __enter__(self) -> "PynqRgb565Camera":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
