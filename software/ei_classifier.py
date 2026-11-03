from __future__ import annotations

import os
import stat
from pathlib import Path
from typing import Any


class EdgeImpulseBirdClassifier:
    def __init__(self, model_path: str | Path):
        try:
            from edge_impulse_linux.image import ImageImpulseRunner
        except ImportError as exc:
            raise RuntimeError(
                "Install the offline Edge Impulse Linux Python SDK on PYNQ first"
            ) from exc
        self.model_path = Path(model_path).expanduser().resolve()
        if not self.model_path.is_file():
            raise FileNotFoundError(self.model_path)
        if os.name == "posix" and not os.access(self.model_path, os.X_OK):
            self.model_path.chmod(self.model_path.stat().st_mode | stat.S_IXUSR)
        self.runner = ImageImpulseRunner(str(self.model_path))
        self.model_info = self.runner.init()

    def classify_rgb(self, frame_rgb: Any) -> tuple[float, float, dict[str, float]]:
        features, _ = self.runner.get_features_from_image_auto_studio_settings(frame_rgb)
        result = self.runner.classify(features)
        scores = {
            str(k): float(v)
            for k, v in result["result"]["classification"].items()
        }
        missing = {"bird", "no_bird"}.difference(scores)
        if missing:
            raise RuntimeError(
                "Model classification output is missing labels: "
                + ", ".join(sorted(missing))
            )
        bird_score = scores["bird"]
        no_bird_score = scores["no_bird"]
        return bird_score, no_bird_score, scores

    def classify_bgr(self, frame_bgr: Any) -> tuple[float, float, dict[str, float]]:
        return self.classify_rgb(frame_bgr[:, :, ::-1])

    def close(self) -> None:
        self.runner.stop()

    def __enter__(self) -> "EdgeImpulseBirdClassifier":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
