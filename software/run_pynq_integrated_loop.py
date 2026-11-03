from __future__ import annotations

import argparse
import csv
import json
import time
from datetime import datetime, timezone
from pathlib import Path

from config import ControllerConfig
from controller import BirdDeterrentController, Prediction
from ei_classifier import EdgeImpulseBirdClassifier
from hardware_adapters import Mcp4725AudioPlayer, PynqAxiGpioLedDriver
from pynq_rgb565_camera import PynqRgb565Camera


def main() -> None:
    parser = argparse.ArgumentParser(description="PYNQ OV5640 + Edge Impulse + MCP4725 audio + LED closed loop")
    parser.add_argument("model", type=Path)
    parser.add_argument("sounds", nargs="+", type=Path)
    parser.add_argument("--bit", type=Path, default=Path("pynq_frame_diff_bd_wrapper.bit"))
    parser.add_argument("--dac-address", type=lambda value: int(value, 0), default=0x60)
    parser.add_argument("--audio-volume", type=float, default=0.05)
    parser.add_argument("--monitor-threshold", type=float, default=0.80)
    parser.add_argument("--recheck-threshold", type=float, default=0.60)
    parser.add_argument("--max-frames", type=int, default=0, help="0 means run until Ctrl+C")
    parser.add_argument("--no-audio", action="store_true")
    parser.add_argument("--log", type=Path, default=Path("live_closed_loop.csv"))
    args = parser.parse_args()

    if not args.model.is_file():
        raise FileNotFoundError(args.model)
    for sound in args.sounds:
        if not sound.is_file():
            raise FileNotFoundError(sound)

    config = ControllerConfig(
        monitor_threshold=args.monitor_threshold,
        recheck_threshold=args.recheck_threshold,
        max_attempts=len(args.sounds),
    )
    controller = BirdDeterrentController(config)
    audio = None
    fields = [
        "timestamp_utc", "inference_index", "bird_score", "no_bird_score",
        "active_threshold", "bird_above_threshold", "scores_json", "state",
        "led", "event", "sound_index",
    ]

    camera = None
    leds = None
    classifier = None
    started = time.monotonic()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    try:
        camera = PynqRgb565Camera(args.bit)
        leds = PynqAxiGpioLedDriver()
        audio = Mcp4725AudioPlayer(
            camera.overlay,
            address=args.dac_address,
            volume=args.audio_volume,
        )
        classifier = EdgeImpulseBirdClassifier(args.model)
        leds.set(controller.update(Prediction(0.0, 1.0), time.monotonic()).led)

        with args.log.open("w", newline="", encoding="utf-8-sig") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader()
            index = 0
            while args.max_frames <= 0 or index < args.max_frames:
                frame_rgb = camera.capture_rgb()
                bird_score, no_bird_score, scores = classifier.classify_rgb(frame_rgb)
                now = time.monotonic()
                active_threshold = controller.active_threshold()
                bird_above_threshold = bird_score >= active_threshold
                decision = controller.update(
                    Prediction(bird_score, no_bird_score),
                    now,
                )
                leds.set(decision.led)
                sound_index = decision.play_sound_index
                writer.writerow({
                    "timestamp_utc": datetime.now(timezone.utc).isoformat(),
                    "inference_index": index,
                    "bird_score": f"{bird_score:.6f}",
                    "no_bird_score": f"{no_bird_score:.6f}",
                    "active_threshold": f"{active_threshold:.6f}",
                    "bird_above_threshold": str(bird_above_threshold).lower(),
                    "scores_json": json.dumps(scores, ensure_ascii=False, sort_keys=True),
                    "state": decision.state.value,
                    "led": decision.led.value,
                    "event": decision.event or "",
                    "sound_index": "" if sound_index is None else sound_index,
                })
                stream.flush()
                print(
                    f"#{index} bird={bird_score:.3f} no_bird={no_bird_score:.3f} "
                    f"threshold={active_threshold:.2f} state={decision.state.value} "
                    f"led={decision.led.value} event={decision.event or '-'}"
                )
                if sound_index is not None:
                    if not args.no_audio:
                        audio.play(args.sounds[sound_index])
                    follow_up = controller.playback_finished(time.monotonic())
                    leds.set(follow_up.led)
                index += 1
    except KeyboardInterrupt:
        print("Stopped by user")
    finally:
        if leds is not None:
            leds.off()
        if classifier is not None:
            classifier.close()
        if camera is not None:
            camera.close()
        print(f"log={args.log.resolve()} elapsed_s={time.monotonic()-started:.1f}")


if __name__ == "__main__":
    main()
