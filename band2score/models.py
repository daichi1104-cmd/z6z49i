"""パイプライン全体で使うデータ型と楽器ごとの設定。"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class NoteEvent:
    """秒単位の音符。drums のときは pitch に GM ドラム番号が入る。"""

    start: float
    end: float
    pitch: int
    velocity: int = 90


@dataclass
class StemSettings:
    """パートごとの採譜設定。"""

    name: str  # 楽譜に表示するパート名
    min_freq: float | None = None
    max_freq: float | None = None
    monophonic: bool = False  # 単音楽器（ボーカル・ベース）なら True
    clef: str = "treble"  # treble / bass / treble8vb / percussion
    onset_threshold: float = 0.5
    frame_threshold: float = 0.3
    gm_program: int = 0  # MIDI 書き出し時の音色


# Demucs のステム名 → 採譜設定
STEM_SETTINGS: dict[str, StemSettings] = {
    "vocals": StemSettings(
        name="Vocals", min_freq=80, max_freq=1100, monophonic=True,
        clef="treble", onset_threshold=0.6, gm_program=52,
    ),
    "guitar": StemSettings(
        name="Guitar", min_freq=75, max_freq=1400, clef="treble8vb",
        onset_threshold=0.55, gm_program=29,
    ),
    "bass": StemSettings(
        name="Bass", min_freq=30, max_freq=400, monophonic=True,
        clef="bass", onset_threshold=0.5, gm_program=33,
    ),
    "piano": StemSettings(
        name="Piano", min_freq=27, max_freq=4200, clef="treble",
        onset_threshold=0.5, gm_program=0,
    ),
    "other": StemSettings(
        name="Other", min_freq=60, max_freq=3000, clef="treble",
        onset_threshold=0.6, gm_program=48,
    ),
    "drums": StemSettings(name="Drums", clef="percussion"),
}

# 楽譜に並べる順番（上から）
PART_ORDER = ["vocals", "guitar", "piano", "other", "bass", "drums"]


@dataclass
class Transcription:
    """1曲分の採譜結果。"""

    tempo: float
    beat_offset: float  # 最初の拍の位置（秒）。これを 1小節目の頭にする
    parts: dict[str, list[NoteEvent]] = field(default_factory=dict)
