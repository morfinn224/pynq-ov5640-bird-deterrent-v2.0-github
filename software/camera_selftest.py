from pathlib import Path
import time

from pynq import MMIO, Overlay


OVERLAY_NAME = "pynq_frame_diff_bd_wrapper.bit"
CTRL_BASE = 0x40002000
CTRL_RANGE = 0x1000

REG_FRAME_LENGTH = 0x0C
REG_THRESHOLD = 0x10
REG_VERSION = 0x14
REG_CAMERA_STATUS = 0x1C
REG_CAMERA_ID = 0x20
REG_CAMERA_FRAME_COUNTER = 0x24
REG_FRAME_BYTES = 0x28
REG_TEST_PATTERN = 0x2C

EXPECTED_VERSION = 0x00020000
EXPECTED_CAMERA_ID = 0x5640
EXPECTED_FRAME_BYTES = 320 * 240 * 2


def main() -> None:
    root = Path(__file__).resolve().parent
    bit_path = root / OVERLAY_NAME
    hwh_path = bit_path.with_suffix(".hwh")
    if not bit_path.exists() or not hwh_path.exists():
        raise FileNotFoundError("BIT/HWH 必须与脚本同目录且主文件名一致")

    print(f"加载 Overlay: {bit_path}")
    Overlay(str(bit_path), download=True, ignore_version=True)
    ctrl = MMIO(CTRL_BASE, CTRL_RANGE)

    version = ctrl.read(REG_VERSION)
    frame_length = ctrl.read(REG_FRAME_LENGTH)
    threshold = ctrl.read(REG_THRESHOLD)
    frame_bytes = ctrl.read(REG_FRAME_BYTES)
    test_pattern = ctrl.read(REG_TEST_PATTERN)
    print(f"VERSION          = 0x{version:08X}")
    print(f"FRAME_LENGTH     = {frame_length}")
    print(f"PIXEL_THRESHOLD  = {threshold}")
    print(f"CAMERA_FRAME_BYTES = {frame_bytes}")
    print(f"TEST_PATTERN      = requested={test_pattern & 1}, "
          f"active={(test_pattern >> 8) & 1}, busy={(test_pattern >> 9) & 1}")

    if version != EXPECTED_VERSION:
        raise RuntimeError(
            f"版本不匹配：期望 0x{EXPECTED_VERSION:08X}，实际 0x{version:08X}"
        )
    if frame_bytes != EXPECTED_FRAME_BYTES:
        raise RuntimeError(
            f"帧字节数不匹配：期望 {EXPECTED_FRAME_BYTES}，实际 {frame_bytes}"
        )

    deadline = time.monotonic() + 5.0
    while True:
        status = ctrl.read(REG_CAMERA_STATUS)
        init_done = bool(status & 0x1)
        init_error = bool(status & 0x2)
        chip_id_valid = bool(status & 0x4)
        if init_error:
            raise RuntimeError(f"OV5640 SCCB 初始化失败，CAMERA_STATUS=0x{status:08X}")
        if init_done and chip_id_valid:
            break
        if time.monotonic() >= deadline:
            raise TimeoutError(f"等待摄像头初始化超时，CAMERA_STATUS=0x{status:08X}")
        time.sleep(0.05)

    chip_id = ctrl.read(REG_CAMERA_ID) & 0xFFFF
    frame0 = ctrl.read(REG_CAMERA_FRAME_COUNTER)
    time.sleep(1.0)
    frame1 = ctrl.read(REG_CAMERA_FRAME_COUNTER)
    print(f"CAMERA_STATUS    = 0x{status:08X}")
    print(f"CAMERA_ID        = 0x{chip_id:04X}")
    print(f"FRAME_COUNTER    = {frame0} -> {frame1}")

    test_pattern = ctrl.read(REG_TEST_PATTERN)
    if test_pattern & 0x301:
        raise RuntimeError(
            f"默认实景模式异常：TEST_PATTERN 寄存器为 0x{test_pattern:08X}"
        )

    if chip_id != EXPECTED_CAMERA_ID:
        raise RuntimeError(
            f"摄像头 ID 错误：期望 0x{EXPECTED_CAMERA_ID:04X}，实际 0x{chip_id:04X}"
        )
    if frame1 == frame0:
        raise RuntimeError("帧计数器未增长：请检查 PCLK/VSYNC/HREF/D[7:0] 接线")

    print("\nPASS：Overlay、AXI 寄存器、OV5640 初始化、芯片 ID 和帧同步均正常。")


if __name__ == "__main__":
    main()
