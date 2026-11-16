"""音声ファイル → 楽譜 の処理の流れ（コマンドとWebアプリの両方から使う）。"""

from __future__ import annotations

import logging
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from . import score as score_mod
from .chords import NO_CHORD, detect_chords
from .models import STEM_SETTINGS, Transcription
from .rhythm import estimate_downbeat, track_beats
from .separate import DEFAULT_MODEL, is_silent, separate
from .transcribe import KICK, SNARE, transcribe_drums, transcribe_pitched

log = logging.getLogger("band2score")

TOTAL_STEPS = 5
# 進み具合の通知: (何段階目か 1〜TOTAL_STEPS, メッセージ)
Progress = Callable[[int, str], None]


class PipelineError(Exception):
    """利用者に見せてよい理由つきの失敗。"""


@dataclass
class Options:
    model: str = DEFAULT_MODEL
    stems_dir: Path | None = None  # 分離済みステムのフォルダ（指定すると分離を省略）
    only: list[str] | None = None  # 楽譜にするパート
    tempo: float | None = None  # テンポを手で指定
    grid: int = 16  # リズムをそろえる細かさ（16 = 16分音符）
    chords: bool = True
    chord_beats: int = 1
    device: str | None = None
    title: str | None = None  # 楽譜のタイトル（省略時はファイル名）


@dataclass
class Result:
    musicxml: Path
    midi: Path
    chord_chart: Path | None = None
    pdf: Path | None = None
    tempo: float = 120.0
    tempo_range: tuple[float, float] = (120.0, 120.0)
    key: str | None = None
    parts: dict[str, int] = field(default_factory=dict)  # パート名 → 音の数
    chords: list[str] = field(default_factory=list)  # 最初の方のコード


# soundfile がそのまま読める形式。それ以外（m4a・aac・webm など）は ffmpeg で WAV にする
DIRECT_FORMATS = {".wav", ".flac", ".ogg", ".aiff", ".aif"}


def prepare_audio(audio: Path, work: Path) -> Path:
    """スマホの録音（m4a など）も読めるように、必要なら WAV に変換する。"""
    if audio.suffix.lower() in DIRECT_FORMATS:
        return audio
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return audio  # 変換できないので、そのまま読めることに期待する
    work.mkdir(parents=True, exist_ok=True)
    wav = work / f"{audio.stem}.wav"
    proc = subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(audio),
                           "-ac", "2", "-ar", "44100", str(wav)], capture_output=True, text=True)
    if proc.returncode != 0 or not wav.exists():
        raise PipelineError("音声ファイルを読み込めませんでした。mp3・m4a・wav などの音声ファイルを選んでください。")
    return wav


def run(audio: Path, out: Path, options: Options | None = None,
        progress: Progress | None = None) -> Result:
    """音声ファイルから楽譜（MusicXML）・MIDI・コード表を作る。"""
    opt = options or Options()
    title = opt.title or audio.stem

    def step(n: int, message: str) -> None:
        log.info("[%d/%d] %s", n, TOTAL_STEPS, message)
        if progress:
            progress(n, message)

    out.mkdir(parents=True, exist_ok=True)
    audio = prepare_audio(audio, out / "input")

    # 1. 音源分離
    if opt.stems_dir:
        stems = {p.stem: p for p in sorted(Path(opt.stems_dir).glob("*.wav"))}
        step(1, "分離済みの楽器の音を使います")
    else:
        step(1, "楽器ごとに音を分けています（いちばん時間がかかります）")
        stems = separate(audio, out / "stems", model=opt.model, device=opt.device)

    # 2. 拍の推定（テンポが揺れる演奏にも合わせて、1拍ずつの時刻を求める）
    step(2, "テンポと拍を調べています")
    grid = track_beats(audio, tempo_hint=opt.tempo)
    low, high = grid.tempo_range
    log.info("    テンポ: %.1f BPM%s", grid.tempo,
             f"（{low:.0f}〜{high:.0f} で揺れています）" if high - low >= 4 else "")

    # 3. 採譜
    tr = Transcription(grid=grid)
    targets = [n for n in stems if n in STEM_SETTINGS and (not opt.only or n in opt.only)]
    for i, name in enumerate(targets):
        step(3, f"音符にしています（{STEM_SETTINGS[name].name}  {i + 1}/{len(targets)}）")
        path = stems[name]
        if is_silent(path):
            log.info("    %-7s ほぼ無音なので省略", name)
            continue
        if name == "drums":
            notes = transcribe_drums(path)
        else:
            notes = transcribe_pitched(path, STEM_SETTINGS[name])
        log.info("    %-7s %d 音", name, len(notes))
        if notes:
            tr.parts[name] = notes
    if not tr.parts:
        raise PipelineError("音符が 1つも見つかりませんでした。音の入ったファイルか確かめてください。")

    # 採譜した音の立ち上がりに合わせて拍の格子を微調整する
    grid.calibrate([n.start for notes in tr.parts.values() for n in notes])

    # 4. コード推定と小節の頭
    step(4, "コードと小節の区切りを調べています")
    harmonic = [p for name, p in stems.items()
                if name in ("guitar", "piano", "other") and not is_silent(p)]

    def chords_now(beats_per_chord: int):
        # ベースは倍音が和音の判定を乱すので混ぜず、ルートの判定だけに使う
        return detect_chords(harmonic or [audio], grid, bass_path=stems.get("bass"),
                             bass_notes=tr.parts.get("bass"), beats_per_chord=beats_per_chord)

    if opt.chords:
        tr.chords = chords_now(1)
    drums = tr.parts.get("drums", [])
    grid.downbeat = estimate_downbeat(
        grid,
        kicks=[n.start for n in drums if n.pitch == KICK],
        snares=[n.start for n in drums if n.pitch == SNARE],
        chord_changes=[c.start for c in tr.chords if c.quality != NO_CHORD],
        bass_onsets=[n.start for n in tr.parts.get("bass", [])],
    )
    log.info("    小節の頭: %d 拍目から数えて 4拍ごと", grid.downbeat + 1)
    if opt.chords and opt.chord_beats > 1:  # 小節の頭がわかってから、2拍・4拍の区切りで判定し直す
        tr.chords = chords_now(opt.chord_beats)
    flats = score_mod.chord_spelling_uses_flats(tr)
    if tr.chords:
        log.info("    コード %d 個（%s …）", len(tr.chords),
                 " ".join(c.label(flats) for c in tr.chords[:8]))

    # 5. 楽譜を書き出す
    step(5, "楽譜を作っています")
    base = out / _safe_name(title)
    midi = score_mod.write_midi(tr, base.with_suffix(".mid"))
    sc = score_mod.build_score(tr, title=title, grid=4 / opt.grid)
    xml = score_mod.write_musicxml(sc, base.with_suffix(".musicxml"))
    pdf = score_mod.write_pdf(xml, base.with_suffix(".pdf"))
    chart = score_mod.write_chord_chart(tr, base.parent / f"{base.name}_chords.txt")

    ks = score_mod._estimate_key(tr)
    return Result(
        musicxml=xml, midi=midi, chord_chart=chart, pdf=pdf,
        tempo=grid.tempo, tempo_range=grid.tempo_range,
        key=_key_name(ks) if ks is not None else None,
        parts={STEM_SETTINGS[k].name: len(v) for k, v in tr.parts.items()},
        chords=[c.label(flats) for c in tr.chords if c.quality != NO_CHORD][:16],
    )


def _safe_name(name: str) -> str:
    keep = "".join(ch if ch.isalnum() or ch in " -_()" else "_" for ch in name).strip()
    return keep[:80] or "score"


def _key_name(ks) -> str:
    tonic = ks.tonic.name.replace("-", "b")
    return f"{tonic} {'major' if ks.mode == 'major' else 'minor'}"
