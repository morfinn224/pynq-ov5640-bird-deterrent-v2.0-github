# PYNQ-Z2 智能视觉驱鸟系统 v2.0

本仓库是智能视觉驱鸟系统的完整可复现工程，包含 PYNQ-Z2 板端程序、OV5640 摄像头 Overlay、Edge Impulse 推理接口、三色状态灯控制、MCP4725 音频输出、PAM8302A 功放接口以及自检和闭环测试代码。

## 主要功能

- OV5640 采集 320×240 RGB565 图像；
- 使用 Edge Impulse ARMv7 无 XNNPACK 模型输出原始 `bird` 概率；
- 监测阈值 0.80、播放后复查阈值 0.60；
- 连续 3 次确认有鸟、连续 5 次无鸟判定离开、连续 3 次仍有鸟切换声音；
- 最多依次播放三段驱离声音；
- 蓝灯表示监测/冷却，红灯表示发现鸟/复查，黄灯表示播放；
- AXI IIC 驱动 MCP4725，输出至 PAM8302A 和 8 Ω/1 W 喇叭；
- 支持 `systemd` 开机自启和脱离电脑独立运行。

## 目录结构

```text
software/   PYNQ 板端 Python、Shell、service、自检、模型和声音文件
fpga/       Vivado 工程入口、BD、RTL、XDC、TCL、IP 配置和发布文件
docs/       开源交付说明与 GitHub 提交指南
```

## 硬件环境

- PYNQ-Z2；
- OV5640（ATK-MC5640）；
- 外接控制板；
- MCP4725 DAC；
- PAM8302A 功放；
- 8 Ω/1 W 喇叭；
- 蓝、红、黄三路 LED；
- 12 V 电池及外接板电源模块。

## 快速开始

将 `software/` 复制到 PYNQ 后执行：

```bash
cd software
chmod +x model_v2_armv7_no_xnnpack.eim run_integrated_v2.sh install_service_v2.sh
sudo -E /usr/local/share/pynq-venv/bin/python3 camera_selftest.py
sudo -E /usr/local/share/pynq-venv/bin/python3 led_gpio_selftest.py
sudo -E /usr/local/share/pynq-venv/bin/python3 mcp4725_selftest.py --tone --volume 0.20
./run_integrated_v2.sh
```

安装开机自启：

```bash
sudo ./install_service_v2.sh
sudo systemctl enable --now bird-deterrent-v2.service
```

停止系统：

```bash
sudo systemctl stop bird-deterrent-v2.service
```

## FPGA 工程

工程面向 Vivado 2020.2。可直接打开 `fpga/bird_det_fpga.xpr`，也可参考 `fpga/build_mcp4725_v2_0.tcl` 重建工程。最终上板文件位于 `fpga/release/`。

主要接口：

| 功能 | PYNQ-Z2 PMODA/FPGA 引脚 |
|---|---|
| BLUE_CTL | 物理 1 / Y18 |
| RED_CTL | 物理 2 / Y19 |
| YELLOW_CTL | 物理 3 / Y16 |
| SD | 物理 4 / Y17 |
| MCP4725 SDA | 物理 9 / W18 |
| MCP4725 SCL | 物理 10 / W19 |

## 测试

```bash
cd software
/usr/local/share/pynq-venv/bin/python3 -m unittest \
  test_controller.py test_ei_classifier.py test_external_gpio.py
```

项目已完成摄像头、LED、MCP4725 音频、闭环逻辑、电池供电和开机自启的整机联调。模型精度和混淆矩阵应以最终独立测试报告为准。

## 许可证

源代码采用 MIT License。模型、声音和第三方组件仍受各自原始许可约束。
