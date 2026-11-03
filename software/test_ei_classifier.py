import sys
import types
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from ei_classifier import EdgeImpulseBirdClassifier


class FakeRunner:
    last_instance = None

    def __init__(self, model_path):
        self.model_path = model_path
        self.stopped = False
        FakeRunner.last_instance = self

    def init(self):
        return {"project": "test"}

    def get_features_from_image_auto_studio_settings(self, frame):
        return [1.0, 2.0], None

    def classify(self, features):
        return {
            "result": {
                "classification": {
                    "bird": 0.65,
                    "no_bird": 0.70,
                }
            }
        }

    def stop(self):
        self.stopped = True


def fake_edge_impulse_modules():
    package = types.ModuleType("edge_impulse_linux")
    image = types.ModuleType("edge_impulse_linux.image")
    image.ImageImpulseRunner = FakeRunner
    package.image = image
    return {
        "edge_impulse_linux": package,
        "edge_impulse_linux.image": image,
    }


class ClassifierTests(unittest.TestCase):
    def test_returns_raw_scores_without_final_label_comparison(self):
        with TemporaryDirectory() as tmp, patch.dict(
            sys.modules, fake_edge_impulse_modules()
        ):
            model = Path(tmp) / "model.eim"
            model.write_bytes(b"test")
            classifier = EdgeImpulseBirdClassifier(model)
            bird, no_bird, scores = classifier.classify_rgb(object())
            self.assertEqual((bird, no_bird), (0.65, 0.70))
            self.assertEqual(scores["bird"], 0.65)
            classifier.close()
            self.assertTrue(FakeRunner.last_instance.stopped)

    def test_missing_required_label_is_rejected(self):
        class MissingLabelRunner(FakeRunner):
            def classify(self, features):
                return {"result": {"classification": {"bird": 0.9}}}

        modules = fake_edge_impulse_modules()
        modules["edge_impulse_linux.image"].ImageImpulseRunner = MissingLabelRunner
        with TemporaryDirectory() as tmp, patch.dict(sys.modules, modules):
            model = Path(tmp) / "model.eim"
            model.write_bytes(b"test")
            classifier = EdgeImpulseBirdClassifier(model)
            with self.assertRaisesRegex(RuntimeError, "no_bird"):
                classifier.classify_rgb(object())


if __name__ == "__main__":
    unittest.main(verbosity=2)
