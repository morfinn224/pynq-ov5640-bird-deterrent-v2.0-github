from __future__ import annotations

import time
import wave
from pathlib import Path

import numpy as np

from controller import Led


class ConsoleLedDriver:
    def __init__(self):
        self.current: Led | None = None

    def set(self, led: Led) -> None:
        if led != self.current:
            print(f"LED={led.value}")
            self.current = led

    def off(self) -> None:
        self.current = None
        print("LED=off")


class PynqAxiGpioLedDriver:
    GPIO_BASE = 0x41200000
    GPIO_RANGE = 0x1000
    ONBOARD_DATA = 0x00
    ONBOARD_TRI = 0x04
    EXTERNAL_DATA = 0x08
    EXTERNAL_TRI = 0x0C
    ONBOARD_VALUES = {Led.BLUE: 0x1, Led.RED: 0x2, Led.YELLOW: 0x4}
    # external_ctl[3:0] = AMP_SD, YELLOW_CTL, RED_CTL, BLUE_CTL.
    # Playback enables YELLOW_CTL and AMP_SD with one atomic channel write.
    EXTERNAL_VALUES = {Led.BLUE: 0x1, Led.RED: 0x2, Led.YELLOW: 0xC}

    def __init__(self):
        try:
            from pynq import MMIO
        except ImportError as exc:
            raise RuntimeError("PynqAxiGpioLedDriver must run on PYNQ") from exc
        self.gpio = MMIO(self.GPIO_BASE, self.GPIO_RANGE)
        self.gpio.write(self.ONBOARD_TRI, 0x00000000)
        self.gpio.write(self.EXTERNAL_TRI, 0x00000000)
        self.current: Led | None = None
        self.off()

    def _write(self, onboard_value: int, external_value: int) -> None:
        self.gpio.write(self.EXTERNAL_DATA, external_value)
        self.gpio.write(self.ONBOARD_DATA, onboard_value)
        onboard_readback = self.gpio.read(self.ONBOARD_DATA) & 0x7
        external_readback = self.gpio.read(self.EXTERNAL_DATA) & 0xF
        if onboard_readback != onboard_value or external_readback != external_value:
            raise RuntimeError(
                "AXI GPIO mismatch: "
                f"onboard wrote/read=0x{onboard_value:X}/0x{onboard_readback:X}, "
                f"external wrote/read=0x{external_value:X}/0x{external_readback:X}"
            )

    def set(self, led: Led) -> None:
        if led != self.current:
            onboard_value = self.ONBOARD_VALUES[led]
            external_value = self.EXTERNAL_VALUES[led]
            self._write(onboard_value, external_value)
            self.current = led
            print(
                f"LED={led.value} onboard=0x{onboard_value:X} "
                f"external=0x{external_value:X}"
            )

    def off(self) -> None:
        self._write(0x0, 0x0)
        self.current = None


class Mcp4725AudioPlayer:
    def __init__(
        self,
        overlay,
        address: int = 0x60,
        volume: float = 0.05,
        chunk_samples: int = 128,
    ):
        if not 0 <= address <= 0x7F:
            raise ValueError("MCP4725 address must be a 7-bit I2C address")
        if not 0.0 < volume <= 1.0:
            raise ValueError("volume must be in (0, 1]")
        if chunk_samples < 1:
            raise ValueError("chunk_samples must be positive")
        try:
            self.iic = overlay.axi_iic_audio_0
        except AttributeError as exc:
            raise RuntimeError(
                "v2.0 Overlay with axi_iic_audio_0 is required"
            ) from exc
        self.address = address
        self.volume = volume
        self.chunk_samples = chunk_samples
        self.sample_rate = self._calibrate_rate()
        self.set_code(2048)
        print(
            f"MCP4725 address=0x{address:02X} calibrated_rate="
            f"{self.sample_rate:.1f} samples/s volume={volume:.3f}"
        )

    @staticmethod
    def _encode_codes(codes: np.ndarray) -> bytearray:
        values = np.asarray(codes, dtype=np.uint16)
        payload = bytearray(values.size * 2)
        payload[0::2] = bytes(((values >> 8) & 0x0F).astype(np.uint8))
        payload[1::2] = bytes((values & 0xFF).astype(np.uint8))
        return payload

    def _send_payload(self, payload: bytearray) -> None:
        length = len(payload)
        # PYNQ 2.7's AxiIIC.send() passes its argument straight to CFFI even
        # though its docstring says bytes-like. Supply the required cdata
        # pointer explicitly while keeping the Python buffer alive.
        c_buffer = type(self.iic)._ffi.from_buffer("unsigned char[]", payload)
        sent = self.iic.send(self.address, c_buffer, length, 0)
        if hasattr(self.iic, "wait"):
            self.iic.wait()
        if sent is not None and int(sent) != len(payload):
            raise RuntimeError(
                f"MCP4725 short I2C transfer: {sent}/{len(payload)} bytes"
            )

    def _send_codes(self, codes: np.ndarray) -> None:
        values = np.asarray(codes, dtype=np.uint16)
        for start in range(0, values.size, self.chunk_samples):
            block = values[start:start + self.chunk_samples]
            self._send_payload(self._encode_codes(block))

    def _calibrate_rate(self) -> float:
        # SD is still low while this silent midscale transfer runs. Measuring
        # the real blocking-transfer rate keeps WAV pitch stable even when the
        # AXI-IIC clock or Python overhead differs between PYNQ images.
        count = 2048
        midpoint = np.full(count, 2048, dtype=np.uint16)
        started = time.monotonic()
        self._send_codes(midpoint)
        elapsed = time.monotonic() - started
        rate = count / max(elapsed, 1e-6)
        if not 500.0 <= rate <= 30000.0:
            raise RuntimeError(f"implausible MCP4725 sample rate: {rate:.1f}")
        return rate

    def set_code(self, code: int) -> None:
        if not 0 <= code <= 4095:
            raise ValueError("MCP4725 code must be in [0, 4095]")
        self._send_codes(np.array([code], dtype=np.uint16))

    @staticmethod
    def _read_wav(path: Path) -> tuple[np.ndarray, int]:
        with wave.open(str(path), "rb") as stream:
            channels = stream.getnchannels()
            sample_width = stream.getsampwidth()
            rate = stream.getframerate()
            frames = stream.readframes(stream.getnframes())
        if sample_width != 2:
            raise ValueError(f"WAV must be 16-bit PCM: {path}")
        samples = np.frombuffer(frames, dtype="<i2").astype(np.float32)
        if channels > 1:
            samples = samples.reshape(-1, channels).mean(axis=1)
        return samples, rate

    def _resample(self, samples: np.ndarray, source_rate: int) -> np.ndarray:
        if samples.size == 0:
            return np.zeros(0, dtype=np.float32)
        output_count = max(1, int(round(samples.size * self.sample_rate / source_rate)))
        source_x = np.arange(samples.size, dtype=np.float64)
        output_x = np.linspace(0, samples.size - 1, output_count)
        return np.interp(output_x, source_x, samples).astype(np.float32)

    def play(self, wav_path: str | Path) -> None:
        path = Path(wav_path)
        if not path.is_file():
            raise FileNotFoundError(path)
        samples, source_rate = self._read_wav(path)
        samples = self._resample(samples, source_rate)
        peak = max(float(np.max(np.abs(samples))), 1.0)
        normalized = samples / peak
        codes = np.clip(
            np.rint(2048.0 + normalized * (2047.0 * self.volume)),
            0,
            4095,
        ).astype(np.uint16)
        time.sleep(0.02)
        self._send_codes(codes)
        self.set_code(2048)
        time.sleep(0.02)

    def play_tone(self, frequency_hz: float = 440.0, duration_s: float = 1.0) -> None:
        count = max(1, int(round(self.sample_rate * duration_s)))
        phase = np.arange(count, dtype=np.float64) / self.sample_rate
        codes = np.clip(
            np.rint(
                2048.0
                + np.sin(2.0 * np.pi * frequency_hz * phase)
                * (2047.0 * self.volume)
            ),
            0,
            4095,
        ).astype(np.uint16)
        time.sleep(0.02)
        self._send_codes(codes)
        self.set_code(2048)
        time.sleep(0.02)
