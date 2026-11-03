import sys
import types
import unittest
from unittest.mock import patch

from controller import Led
from hardware_adapters import PynqAxiGpioLedDriver


class FakeMMIO:
    instances = []

    def __init__(self, base, length):
        self.base = base
        self.length = length
        self.registers = {}
        self.writes = []
        self.__class__.instances.append(self)

    def write(self, offset, value):
        self.registers[offset] = value
        self.writes.append((offset, value))

    def read(self, offset):
        return self.registers.get(offset, 0)


class ExternalGpioTests(unittest.TestCase):
    def setUp(self):
        FakeMMIO.instances.clear()

    def test_led_and_amp_sd_mapping(self):
        fake_pynq = types.SimpleNamespace(MMIO=FakeMMIO)
        with patch.dict(sys.modules, {"pynq": fake_pynq}):
            driver = PynqAxiGpioLedDriver()
            mmio = FakeMMIO.instances[-1]

            self.assertEqual(mmio.registers[0x00], 0x0)
            self.assertEqual(mmio.registers[0x08], 0x0)

            driver.set(Led.BLUE)
            self.assertEqual(mmio.registers[0x00], 0x1)
            self.assertEqual(mmio.registers[0x08], 0x1)

            driver.set(Led.RED)
            self.assertEqual(mmio.registers[0x00], 0x2)
            self.assertEqual(mmio.registers[0x08], 0x2)

            driver.set(Led.YELLOW)
            self.assertEqual(mmio.registers[0x00], 0x4)
            self.assertEqual(mmio.registers[0x08], 0xC)

            driver.off()
            self.assertEqual(mmio.registers[0x00], 0x0)
            self.assertEqual(mmio.registers[0x08], 0x0)


if __name__ == "__main__":
    unittest.main()
