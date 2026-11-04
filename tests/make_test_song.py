"""動作確認用のバンド風テスト音源（合成音）を作る。

ベース・ピアノ（和音）・メロディ・ドラムを 120 BPM / C メジャーで鳴らし、
WAV・楽器ごとのステム（stems/）・正解 MIDI を書き出す。
Demucs のモデルを使わずに分離以降を試すときは --stems-dir stems を使う。

    python tests/make_test_song.py out_dir
"""

import sys
from pathlib import Path

import numpy as np
import pretty_midi
import soundfile as sf

SR = 44100
BPM = 120
BEAT = 60 / BPM


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


def main(out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(0)
    bars = 8
    total = bars * 4 * BEAT + 1
    mix = np.zeros(int(total * SR))
    stems = {k: np.zeros_like(mix) for k in ("bass", "piano", "vocals", "drums")}
    stem_of = {"bass": "bass", "piano": "piano", "lead": "vocals", "drums": "drums"}
    pm = pretty_midi.PrettyMIDI(initial_tempo=BPM)
    parts = {name: pretty_midi.Instrument(program=prog, name=name, is_drum=drum_)
             for name, prog, drum_ in [("bass", 33, False), ("piano", 0, False),
                                       ("lead", 80, False), ("drums", 0, True)]}

    def add(sig, start, gain, part):
        i = int(start * SR)
        seg = gain * sig[: len(mix) - i]
        mix[i:i + len(seg)] += seg
        stems[stem_of[part]][i:i + len(seg)] += seg

    def note(part, pitch, start, dur, harm, decay, gain):
        add(tone(pretty_midi.note_number_to_hz(pitch), dur, harm, decay), start, gain, part)
        parts[part].notes.append(pretty_midi.Note(90, pitch, start, start + dur))

    progression = [(48, [60, 64, 67]), (45, [57, 60, 64]), (41, [57, 60, 65]), (43, [59, 62, 67])]
    melody = [72, 74, 76, 79, 76, 74, 72, 71]
    for bar in range(bars):
        root, triad = progression[bar % 4]
        t0 = bar * 4 * BEAT
        for b in range(4):  # ベース: 4分音符
            note("bass", root, t0 + b * BEAT, BEAT * 0.9, [1, 0.5, 0.25], 2, 0.5)
        for b in (0, 2):  # ピアノ: 2分音符の和音
            for p in triad:
                note("piano", p, t0 + b * BEAT, 2 * BEAT * 0.95, [1, 0.3, 0.1], 1.5, 0.18)
        for b in range(0, 8, 2):  # メロディ: 4分音符
            p = melody[(bar * 4 + b // 2) % len(melody)]
            note("lead", p, t0 + b / 2 * BEAT, BEAT * 0.9, [1, 0.6, 0.4, 0.2], 0.5, 0.22)
        for e in range(8):  # ドラム: 8ビート
            t = t0 + e * BEAT / 2
            add(drum("hat", rng), t, 0.3, "drums")
            parts["drums"].notes.append(pretty_midi.Note(80, 42, t, t + 0.1))
            if e in (0, 4, 5):
                add(drum("kick", rng), t, 0.8, "drums")
                parts["drums"].notes.append(pretty_midi.Note(100, 36, t, t + 0.1))
            if e in (2, 6):
                add(drum("snare", rng), t, 0.5, "drums")
                parts["drums"].notes.append(pretty_midi.Note(100, 38, t, t + 0.1))

    scale = np.abs(mix).max() * 1.1
    sf.write(out_dir / "test_band.wav", mix / scale, SR)
    # 楽器ごとの音（理想的に分離できた場合のステム）も書き出す
    (out_dir / "stems").mkdir(exist_ok=True)
    for name, sig in stems.items():
        sf.write(out_dir / "stems" / f"{name}.wav", sig / scale, SR)
    pm.instruments.extend(parts.values())
    pm.write(str(out_dir / "test_band_truth.mid"))
    print(out_dir / "test_band.wav")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "test_data"))
