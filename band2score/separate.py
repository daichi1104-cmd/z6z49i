"""Demucs による音源分離（楽器ごとの音声に分ける）。"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import soundfile as sf

DEFAULT_MODEL = "htdemucs_6s"  # vocals / drums / bass / guitar / piano / other


def separate(audio_path: Path, out_dir: Path, model: str = DEFAULT_MODEL,
             device: str | None = None) -> dict[str, Path]:
    """音声を楽器ごとに分けて WAV で保存し、{ステム名: パス} を返す。"""
    import torch
    from demucs.api import Separator

    if device is None:
        device = "cuda" if torch.cuda.is_available() else "cpu"
    separator = Separator(model=model, device=device, progress=True)
    _, stems = separator.separate_audio_file(str(audio_path))

    out_dir.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    for name, tensor in stems.items():
        path = out_dir / f"{name}.wav"
        sf.write(path, tensor.cpu().numpy().T, separator.samplerate)
        paths[name] = path
    return paths


def is_silent(path: Path, threshold_db: float = -45.0) -> bool:
    """ステムがほぼ無音か（その楽器が曲に入っていないか）を判定する。"""
    audio, _ = sf.read(path, always_2d=True)
    mono = audio.mean(axis=1)
    if mono.size == 0:
        return True
    rms = float(np.sqrt(np.mean(mono ** 2)))
    return 20 * np.log10(rms + 1e-12) < threshold_db
