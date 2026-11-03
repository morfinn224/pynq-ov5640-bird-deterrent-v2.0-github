from pathlib import Path
import argparse
import time

import numpy as np
from pynq import MMIO, Overlay, allocate


ROOT = Path(__file__).resolve().parent
BIT_PATH = ROOT / "pynq_frame_diff_bd_wrapper.bit"
VDMA_BASE = 0x43000000
VDMA_RANGE = 0x10000

S2MM_DMACR = 0x30
S2MM_DMASR = 0x34
PARK_PTR = 0x28
S2MM_VSIZE = 0xA0
S2MM_HSIZE = 0xA4
S2MM_STRIDE = 0xA8
S2MM_START_ADDRESS_1 = 0xAC
S2MM_START_ADDRESS_2 = 0xB0

# Sticky S2MM line/frame synchronization errors.  A live camera is already
# streaming when software starts the VDMA, so the first partial frame can set
# these bits.  Clear that startup condition and accept only later clean frames.
S2MM_SYNC_ERROR_MASK = 0x0000C990
S2MM_FATAL_ERROR_MASK = 0x00000060
S2MM_FRAME_IRQ = 0x00001000

WIDTH = 320
HEIGHT = 240
BYTES_PER_PIXEL = 2
LINE_BYTES = WIDTH * BYTES_PER_PIXEL


def rgb565_to_rgb888(frame: np.ndarray) -> np.ndarray:
    value = frame.astype(np.uint16)
    red = ((value >> 11) & 0x1F).astype(np.uint8)
    green = ((value >> 5) & 0x3F).astype(np.uint8)
    blue = (value & 0x1F).astype(np.uint8)
    return np.dstack(
        ((red << 3) | (red >> 2), (green << 2) | (green >> 4), (blue << 3) | (blue >> 2))
    )


def wait_reset_done(vdma: MMIO) -> None:
    vdma.write(S2MM_DMACR, 0x4)
    deadline = time.monotonic() + 1.0
    while vdma.read(S2MM_DMACR) & 0x4:
        if time.monotonic() >= deadline:
            raise TimeoutError("VDMA S2MM reset 超时")
        time.sleep(0.001)


def main() -> None:
    parser = argparse.ArgumentParser(description="采集一帧 OV5640 RGB565 图像")
    parser.add_argument(
        "--no-reload",
        action="store_true",
        help="不重新加载 BIT，用于保留已经打开的测试彩条模式",
    )
    args = parser.parse_args()

    if not BIT_PATH.exists() or not BIT_PATH.with_suffix(".hwh").exists():
        raise FileNotFoundError("BIT/HWH 缺失或主文件名不一致")

    if args.no_reload:
        print("保留当前 Overlay 和摄像头模式，不重新加载 BIT")
    else:
        print(f"加载 Overlay: {BIT_PATH}")
        Overlay(str(BIT_PATH), download=True, ignore_version=True)
    vdma = MMIO(VDMA_BASE, VDMA_RANGE)
    buffers = [
        allocate(shape=(HEIGHT, WIDTH), dtype=np.uint16),
        allocate(shape=(HEIGHT, WIDTH), dtype=np.uint16),
    ]

    try:
        for buffer in buffers:
            buffer[:] = 0
            buffer.flush()

        wait_reset_done(vdma)
        vdma.write(S2MM_START_ADDRESS_1, buffers[0].physical_address)
        vdma.write(S2MM_START_ADDRESS_2, buffers[1].physical_address)
        vdma.write(S2MM_STRIDE, LINE_BYTES)
        vdma.write(S2MM_HSIZE, LINE_BYTES)
        # RS + circular park + IOC interrupt enable; VSIZE starts reception.
        vdma.write(S2MM_DMACR, 0x00001003)
        vdma.write(S2MM_VSIZE, HEIGHT)

        deadline = time.monotonic() + 5.0
        clean_frames = 0
        while True:
            status = vdma.read(S2MM_DMASR)
            if status & S2MM_FATAL_ERROR_MASK:
                raise RuntimeError(f"VDMA S2MM 报错，DMASR=0x{status:08X}")

            sync_errors = status & S2MM_SYNC_ERROR_MASK
            if sync_errors:
                # PARK_PTR is frozen while line/frame errors are sticky.  Clear
                # them and discard any simultaneous IOC indication so buffer
                # selection is based only on a later clean frame.
                vdma.write(S2MM_DMASR, sync_errors | (status & S2MM_FRAME_IRQ))
                clean_frames = 0
            elif status & S2MM_FRAME_IRQ:
                vdma.write(S2MM_DMASR, S2MM_FRAME_IRQ)
                clean_frames += 1
                if clean_frames >= 2:
                    break

            if time.monotonic() >= deadline:
                raise TimeoutError(f"等待完整帧超时，DMASR=0x{status:08X}")
            time.sleep(0.005)

        # With all sticky errors cleared, PARK_PTR once again tracks the frame
        # store currently being written.  The other store is the latest fully
        # completed frame.  Stop the channel before copying that buffer.
        status = vdma.read(S2MM_DMASR)
        current_write = (vdma.read(PARK_PTR) >> 24) & 0x1F
        completed = (current_write ^ 1) & 0x1
        vdma.write(S2MM_DMACR, 0x0)
        buffers[completed].invalidate()
        frame = np.array(buffers[completed], copy=True)

        raw_path = ROOT / "capture_rgb565.bin"
        frame.tofile(raw_path)
        print(f"已保存 RGB565 原始帧: {raw_path}")

        raw_bytes = frame.view(np.uint8).reshape(-1)
        byte_max = int(raw_bytes.max())
        bit6_ratio = float(np.count_nonzero(raw_bytes & 0x40)) / raw_bytes.size
        bit7_ratio = float(np.count_nonzero(raw_bytes & 0x80)) / raw_bytes.size
        print(f"RAW_BYTE_MAX     = 0x{byte_max:02X}")
        print(f"RAW_BIT6_RATIO   = {bit6_ratio:.6f}")
        print(f"RAW_BIT7_RATIO   = {bit7_ratio:.6f}")
        if byte_max <= 0x3F or bit6_ratio == 0.0 or bit7_ratio == 0.0:
            print("FAIL：D6/D7 数据验收未通过；请勿继续批量采集。")
        else:
            print("PASS：原始字节 D6/D7 数据验收通过。")

        try:
            from PIL import Image

            png_path = ROOT / "capture.png"
            Image.fromarray(rgb565_to_rgb888(frame), "RGB").save(png_path)
            print(f"已保存 PNG: {png_path}")
        except ImportError:
            print("未安装 Pillow，已跳过 PNG；原始 RGB565 文件已保存。")

        print(f"PASS：VDMA 已接收完整帧，DMASR=0x{status:08X}，buffer={completed}")
    finally:
        vdma.write(S2MM_DMACR, 0x0)
        for buffer in buffers:
            buffer.freebuffer()


if __name__ == "__main__":
    main()
