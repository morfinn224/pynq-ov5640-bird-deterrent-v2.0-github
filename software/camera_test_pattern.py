from pathlib import Path
import argparse
import time

from pynq import MMIO, Overlay


ROOT = Path(__file__).resolve().parent
BIT_PATH = ROOT / "pynq_frame_diff_bd_wrapper.bit"
CTRL_BASE = 0x40002000
CTRL_RANGE = 0x1000
REG_VERSION = 0x14
REG_CAMERA_STATUS = 0x1C
REG_TEST_PATTERN = 0x2C
EXPECTED_VERSION = 0x00020000


def main() -> None:
    parser = argparse.ArgumentParser(
        description="切换 OV5640 测试彩条；默认只连接现有 Overlay，不重新下载 BIT。"
    )
    parser.add_argument("mode", choices=("on", "off", "status"))
    parser.add_argument(
        "--reload",
        action="store_true",
        help="先重新加载 BIT；重新加载后默认关闭彩条（实景模式）",
    )
    args = parser.parse_args()

    if args.reload:
        if not BIT_PATH.exists() or not BIT_PATH.with_suffix(".hwh").exists():
            raise FileNotFoundError("BIT/HWH 缺失或主文件名不一致")
        Overlay(str(BIT_PATH), download=True, ignore_version=True)

    ctrl = MMIO(CTRL_BASE, CTRL_RANGE)
    version = ctrl.read(REG_VERSION)
    if version != EXPECTED_VERSION:
        raise RuntimeError(
            f"版本不匹配：期望 0x{EXPECTED_VERSION:08X}，实际 0x{version:08X}；"
            "如尚未加载新 Overlay，请加 --reload"
        )

    if args.mode != "status":
        requested = 1 if args.mode == "on" else 0
        ctrl.write(REG_TEST_PATTERN, requested)
        deadline = time.monotonic() + 1.0
        while True:
            value = ctrl.read(REG_TEST_PATTERN)
            active = (value >> 8) & 1
            busy = (value >> 9) & 1
            if not busy and active == requested:
                break
            if ctrl.read(REG_CAMERA_STATUS) & 0x2:
                raise RuntimeError("SCCB 写入失败，CAMERA_STATUS 的 error 位已置位")
            if time.monotonic() >= deadline:
                raise TimeoutError(f"等待测试图切换超时，TEST_PATTERN=0x{value:08X}")
            time.sleep(0.01)

    value = ctrl.read(REG_TEST_PATTERN)
    print(f"VERSION=0x{version:08X}")
    print(
        f"TEST_PATTERN=0x{value:08X} "
        f"requested={value & 1} active={(value >> 8) & 1} busy={(value >> 9) & 1}"
    )
    print("模式：测试彩条" if ((value >> 8) & 1) else "模式：实景")


if __name__ == "__main__":
    main()
