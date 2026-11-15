"""動作確認用のバンド風テスト音源（合成音）を作る。

ベース・ピアノ（和音）・メロディ・ドラムを C メジャーで鳴らし、
WAV・楽器ごとのステム（stems/）・正解 MIDI・正解の楽譜上の位置（truth.json）を書き出す。
Demucs のモデルを使わずに分離以降を試すときは --stems-dir stems を使う。

    python tests/make_test_song.py out_dir
    python tests/make_test_song.py out_dir --bpm 112 --bpm-end 124 --pickup 2 --humanize 15

--bpm-end を付けるとテンポが少しずつ変わる（走る・もたる）演奏になり、
--pickup 2 で 2拍の弱起（1小節目の前に始まるメロディ）、--humanize でタイミングの揺れ（ミリ秒）が入る。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pretty_midi
import soundfile as sf

SR = 44100
PROGRESSION = [("C", 48, [60, 64, 67]), ("Am", 45, [57, 60, 64]), ("F", 41, [57, 60, 65]),
               ("G", 43, [59, 62, 67])]
MELODY = [72, 74, 76, 79, 76, 74, 72, 71]
PICKUP_NOTES = [67, 69, 71]  # 弱起のメロディ（最後の音から逆順に使う）


def tone(freq, dur, harmonics, decay):
    t = np.arange(int(dur * SR)) / SR
    wave = sum(a * np.sin(2 * np.pi * freq * (i + 1) * t) for i, a in enumerate(harmonics))
    env = np.exp(-t * decay) * np.minimum(1, t * 200)
    env[-200:] *= np.linspace(1, 0, 200)
    return wave * env


def drum(kind, rng):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    if kind == "kick":
        f = 120 * np.exp(-t * 30) + 45
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 18)
    if kind == "snare":
        return (0.6 * rng.standard_normal(n) + 0.5 * np.sin(2 * np.pi * 190 * t)) * np.exp(-t * 25)
    noise = rng.standard_normal(n)
    noise = np.diff(noise, prepend=0)  # 高域を強調
    return 0.4 * noise * np.exp(-t * 60)


def make_song(out_dir: Path, bars: int = 8, bpm: float = 120, bpm_end: float | None = None,
              pickup: int = 0, humanize_ms: float = 0.0, seed: int = 0) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    bpm_end = bpm_end or bpm
    n_beats = pickup + bars * 4 + 1
    # 拍ごとのテンポを bpm → bpm_end へ直線的に変え、拍の時刻を積み上げる
    bpms = np.linspace(bpm, bpm_end, n_beats)
    beat_times = np.concatenate([[0.0], np.cumsum(60.0 / bpms)]) + 0.05

    def at(beat: float) -> float:
        """弱起を含めた通しの拍番号（小数可）→ 秒。揺れも足す。"""
        i = int(np.floor(beat))
        t = beat_times[i] + (beat - i) * (beat_times[i + 1] - beat_times[i])
        return float(t + rng.normal(0, humanize_ms / 1000)) if humanize_ms else float(t)

    total = beat_times[-1] + 1
    mix = np.zeros(int(total * SR))
    stems = {k: np.zeros_like(mix) for k in ("bass", "piano", "vocals", "drums")}
    stem_of = {"bass": "bass", "piano": "piano", "lead": "vocals", "drums": "drums"}
    pm = pretty_midi.PrettyMIDI(initial_tempo=bpm)
    parts = {name: pretty_midi.Instrument(program=prog, name=name, is_drum=drum_)
             for name, prog, drum_ in [("bass", 33, False), ("piano", 0, False),
                                       ("lead", 80, False), ("drums", 0, True)]}
    # 楽譜上の正解位置（4分音符単位）。弱起があれば 1小節目は休符で埋めた不完全小節になる
    bar_one = 4.0 if pickup else 0.0
    truth: dict[str, list] = {k: [] for k in ("bass", "lead", "piano", "kick", "snare", "chords")}

    def add(sig, start, gain, part):
        i = int(start * SR)
        seg = gain * sig[: len(mix) - i]
        mix[i:i + len(seg)] += seg
        stems[stem_of[part]][i:i + len(seg)] += seg

    def note(part, pitch, beat, beats, harm, decay, gain):
        start = at(beat + pickup)
        dur = (at(beat + pickup + beats) - start) * 0.9
        add(tone(pretty_midi.note_number_to_hz(pitch), dur, harm, decay), start, gain, part)
        parts[part].notes.append(pretty_midi.Note(90, pitch, start, start + dur))
        if part in truth:
            truth[part].append([bar_one + beat, pitch])

    for k in range(pickup):  # 弱起: メロディだけ
        note("lead", PICKUP_NOTES[-pickup + k], k - pickup, 1, [1, 0.6, 0.4, 0.2], 0.5, 0.22)
    for bar in range(bars):
        name, root, triad = PROGRESSION[bar % 4]
        b0 = bar * 4
        truth["chords"].append([bar_one + b0, name])
        for b in range(4):  # ベース: 4分音符
            note("bass", root, b0 + b, 1, [1, 0.5, 0.25], 2, 0.5)
        for b in (0, 2):  # ピアノ: 2分音符の和音
            for p in triad:
                note("piano", p, b0 + b, 2, [1, 0.3, 0.1], 1.5, 0.18)
        for b in range(4):  # メロディ: 4分音符
            note("lead", MELODY[(bar * 4 + b) % len(MELODY)], b0 + b, 1, [1, 0.6, 0.4, 0.2], 0.5, 0.22)
        for e in range(8):  # ドラム: 8ビート
            beat = b0 + e / 2
            t = at(beat + pickup)
            hits = [("hat", 42, 0.3)]
            if e in (0, 4, 5):
                hits.append(("kick", 36, 0.8))
                truth["kick"].append(bar_one + beat)
            if e in (2, 6):
                hits.append(("snare", 38, 0.5))
                truth["snare"].append(bar_one + beat)
            for kind, gm, gain in hits:
                add(drum(kind, rng), t, gain, "drums")
                parts["drums"].notes.append(pretty_midi.Note(90, gm, t, t + 0.1))

    scale = np.abs(mix).max() * 1.1
    sf.write(out_dir / "test_band.wav", mix / scale, SR)
    # 楽器ごとの音（理想的に分離できた場合のステム）も書き出す
    (out_dir / "stems").mkdir(exist_ok=True)
    for name, sig in stems.items():
        sf.write(out_dir / "stems" / f"{name}.wav", sig / scale, SR)
    pm.instruments.extend(parts.values())
    pm.write(str(out_dir / "test_band_truth.mid"))
    (out_dir / "truth.json").write_text(json.dumps(truth), encoding="utf-8")
    return out_dir / "test_band.wav"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("out_dir", type=Path, nargs="?", default=Path("test_data"))
    p.add_argument("--bars", type=int, default=8)
    p.add_argument("--bpm", type=float, default=120)
    p.add_argument("--bpm-end", type=float, default=None, help="最後の小節のテンポ（だんだん変わる）")
    p.add_argument("--pickup", type=int, default=0, choices=[0, 1, 2, 3], help="弱起の拍数")
    p.add_argument("--humanize", type=float, default=0.0, help="タイミングの揺れ（ミリ秒）")
    p.add_argument("--seed", type=int, default=0)
    a = p.parse_args()
    print(make_song(a.out_dir, a.bars, a.bpm, a.bpm_end, a.pickup, a.humanize, a.seed))


if __name__ == "__main__":
    main()
