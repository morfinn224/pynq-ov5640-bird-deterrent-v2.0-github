from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional

from config import ControllerConfig


class State(str, Enum):
    MONITORING = "monitoring"
    PLAYING = "playing"
    RECHECKING = "rechecking"
    COOLDOWN = "cooldown"


class Led(str, Enum):
    BLUE = "blue"
    RED = "red"
    YELLOW = "yellow"


@dataclass(frozen=True)
class Prediction:
    bird_score: float
    no_bird_score: float = 0.0


@dataclass(frozen=True)
class Decision:
    state: State
    led: Led
    play_sound_index: Optional[int] = None
    event: Optional[str] = None


class BirdDeterrentController:
    """Pure state machine; camera, GPIO and audio are injected by the caller."""

    def __init__(self, config: ControllerConfig):
        config.validate()
        self.config = config
        self.state = State.MONITORING
        self.detect_count = 0
        self.leave_count = 0
        self.persist_count = 0
        self.attempts = 0
        self.recheck_after = 0.0
        self.cooldown_until = 0.0

    def active_threshold(self) -> float:
        """Return the raw bird-score threshold for the current state."""
        if self.state is State.RECHECKING:
            return self.config.recheck_threshold
        return self.config.monitor_threshold

    def _is_bird(self, p: Prediction) -> bool:
        # Deliberately use the raw bird probability only. Do not depend on the
        # Edge Impulse final bird/no_bird label or on which class scored higher.
        return p.bird_score >= self.active_threshold()

    def update(self, p: Prediction, now_s: float) -> Decision:
        if self.state is State.PLAYING:
            return Decision(self.state, Led.YELLOW)

        if self.state is State.COOLDOWN:
            if now_s < self.cooldown_until:
                return Decision(self.state, Led.BLUE)
            self.state = State.MONITORING
            self.detect_count = 0
            self.attempts = 0

        if self.state is State.MONITORING:
            self.detect_count = self.detect_count + 1 if self._is_bird(p) else 0
            if self.detect_count >= self.config.detect_frames:
                self.state = State.PLAYING
                self.attempts = 1
                return Decision(
                    self.state,
                    Led.YELLOW,
                    play_sound_index=0,
                    event="bird_confirmed",
                )
            return Decision(self.state, Led.BLUE)

        if now_s < self.recheck_after:
            return Decision(self.state, Led.RED)

        if self._is_bird(p):
            self.persist_count += 1
            self.leave_count = 0
            if self.persist_count >= self.config.persist_frames:
                if self.attempts < self.config.max_attempts:
                    sound_index = self.attempts
                    self.attempts += 1
                    self.persist_count = 0
                    self.state = State.PLAYING
                    return Decision(
                        self.state,
                        Led.YELLOW,
                        play_sound_index=sound_index,
                        event="bird_persisted_switch_sound",
                    )
                self._enter_cooldown(now_s)
                return Decision(self.state, Led.BLUE, event="max_attempts_reached")
        else:
            self.leave_count += 1
            self.persist_count = 0
            if self.leave_count >= self.config.leave_frames:
                self._enter_cooldown(now_s)
                return Decision(self.state, Led.BLUE, event="bird_left")

        return Decision(self.state, Led.RED)

    def playback_finished(self, now_s: float) -> Decision:
        if self.state is not State.PLAYING:
            raise RuntimeError("playback_finished called while not playing")
        self.state = State.RECHECKING
        self.leave_count = 0
        self.persist_count = 0
        self.recheck_after = now_s + self.config.recheck_delay_s
        return Decision(self.state, Led.RED, event="playback_finished")

    def _enter_cooldown(self, now_s: float) -> None:
        self.state = State.COOLDOWN
        self.cooldown_until = now_s + self.config.cooldown_s
        self.detect_count = 0
        self.leave_count = 0
        self.persist_count = 0

