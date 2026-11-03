from dataclasses import dataclass


@dataclass(frozen=True)
class ControllerConfig:
    monitor_threshold: float = 0.80
    recheck_threshold: float = 0.60
    detect_frames: int = 3
    leave_frames: int = 5
    persist_frames: int = 3
    recheck_delay_s: float = 2.0
    cooldown_s: float = 10.0
    max_attempts: int = 3

    def validate(self) -> None:
        for name in ("monitor_threshold", "recheck_threshold"):
            if not 0.0 <= getattr(self, name) <= 1.0:
                raise ValueError(f"{name} must be in [0, 1]")
        if self.recheck_threshold > self.monitor_threshold:
            raise ValueError("recheck_threshold must not exceed monitor_threshold")
        for name in ("detect_frames", "leave_frames", "persist_frames", "max_attempts"):
            if getattr(self, name) < 1:
                raise ValueError(f"{name} must be >= 1")
        if self.recheck_delay_s < 0 or self.cooldown_s < 0:
            raise ValueError("delays must be >= 0")

