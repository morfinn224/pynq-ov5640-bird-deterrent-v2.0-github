import unittest

from config import ControllerConfig
from controller import BirdDeterrentController, Led, Prediction, State


class ControllerTests(unittest.TestCase):
    def make_controller(self) -> BirdDeterrentController:
        return BirdDeterrentController(
            ControllerConfig(
                monitor_threshold=0.8,
                recheck_threshold=0.6,
                detect_frames=2,
                leave_frames=2,
                persist_frames=2,
                recheck_delay_s=0,
                cooldown_s=5,
                max_attempts=2,
            )
        )

    def test_bird_leaves_after_first_sound(self) -> None:
        c = self.make_controller()
        c.update(Prediction(0.9, 0.1), 0)
        d = c.update(Prediction(0.9, 0.1), 1)
        self.assertEqual((d.state, d.led, d.play_sound_index), (State.PLAYING, Led.YELLOW, 0))
        c.playback_finished(2)
        c.update(Prediction(0.59, 0.41), 3)
        d = c.update(Prediction(0.59, 0.41), 4)
        self.assertEqual((d.state, d.event), (State.COOLDOWN, "bird_left"))

    def test_persistent_bird_switches_sound_then_stops(self) -> None:
        c = self.make_controller()
        c.update(Prediction(0.9, 0.1), 0)
        c.update(Prediction(0.9, 0.1), 1)
        c.playback_finished(2)
        # 0.65 is below the monitoring threshold but above the recheck threshold.
        c.update(Prediction(0.65, 0.35), 3)
        d = c.update(Prediction(0.65, 0.35), 4)
        self.assertEqual(d.play_sound_index, 1)
        c.playback_finished(5)
        c.update(Prediction(0.65, 0.35), 6)
        d = c.update(Prediction(0.65, 0.35), 7)
        self.assertEqual((d.state, d.event), (State.COOLDOWN, "max_attempts_reached"))

    def test_score_below_monitor_threshold_does_not_trigger(self) -> None:
        c = self.make_controller()
        for t in range(5):
            d = c.update(Prediction(0.79, 0.21), t)
        self.assertEqual(d.state, State.MONITORING)

    def test_monitor_threshold_boundary_triggers(self) -> None:
        c = self.make_controller()
        c.update(Prediction(0.80, 0.20), 0)
        d = c.update(Prediction(0.80, 0.20), 1)
        self.assertEqual((d.state, d.play_sound_index), (State.PLAYING, 0))

    def test_threshold_validation(self) -> None:
        with self.assertRaises(ValueError):
            ControllerConfig(monitor_threshold=0.5, recheck_threshold=0.6).validate()


if __name__ == "__main__":
    unittest.main(verbosity=2)

