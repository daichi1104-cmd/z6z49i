"""コード推定・コード表示のテスト（合成音を使う）。"""

from pathlib import Path

import numpy as np
import pretty_midi
import soundfile as sf
from music21 import converter, harmony

from band2score.chords import ChordEvent, detect_chords
from band2score.models import NoteEvent, Transcription
from band2score.score import build_score, write_chord_chart, write_musicxml
from band2score.transcribe import make_monophonic

SR = 22050
BEAT = 0.5  # 120 BPM

# (ベース, 上の和音, 拍数, 正解)。7th・分数コード・sus4・2拍で変わるコードを含む
PROGRESSION = [
    (46, [57, 62, 65], 4, "Bbmaj7"),
    (43, [58, 62, 65, 70], 4, "Gm7"),
    (43, [58, 63, 67], 2, "Eb/G"),
    (41, [57, 60, 63], 2, "F7"),
    (39, [55, 58, 62], 4, "Ebmaj7"),
    (41, [60, 65, 70], 2, "Fsus4"),
    (41, [57, 60, 65], 2, "F"),
    (38, [57, 62, 65], 4, "Dm"),
    (36, [60, 64, 67], 4, "C"),
]


def _tone(midi: int, dur: float) -> np.ndarray:
    t = np.arange(int(dur * SR)) / SR
    f = pretty_midi.note_number_to_hz(midi)
    wave = sum(a * np.sin(2 * np.pi * f * (i + 1) * t) for i, a in enumerate([1, 0.4, 0.2]))
    env = np.exp(-t * 1.2) * np.minimum(1, t * 200)
    env[-200:] *= np.linspace(1, 0, 200)
    return wave * env


def _make_song(tmp: Path):
    total = sum(p[2] for p in PROGRESSION) * BEAT + 1
    piano = np.zeros(int(total * SR))
    bass = np.zeros_like(piano)
    bass_notes = []
    t = 0.0
    for root, voicing, beats, _ in PROGRESSION:
        for k in range(beats):
            start = t + k * BEAT
            sig = _tone(root, BEAT * 0.9)
            i = int(start * SR)
            bass[i:i + len(sig)] += 0.5 * sig
            bass_notes.append(NoteEvent(start, start + 0.45, root))
        for p in voicing:
            sig = _tone(p, beats * BEAT * 0.95)
            i = int(t * SR)
            piano[i:i + len(sig)] += 0.15 * sig
        t += beats * BEAT
    sf.write(tmp / "piano.wav", piano, SR)
    sf.write(tmp / "bass.wav", bass, SR)
    return tmp / "piano.wav", tmp / "bass.wav", bass_notes


def test_detect_chords_progression(tmp_path: Path):
    piano, bass, bass_notes = _make_song(tmp_path)
    events = detect_chords([piano], 120, 0.0, bass_path=bass, bass_notes=bass_notes)
    assert [e.label(flats=True) for e in events] == [p[3] for p in PROGRESSION]
    starts = [round(e.start / BEAT) for e in events]
    assert starts == list(np.cumsum([0] + [p[2] for p in PROGRESSION[:-1]]))


def test_make_monophonic_drops_overtones():
    notes = [NoteEvent(0.0, 1.0, 39, 100), NoteEvent(0.5, 0.6, 58, 60),  # Eb2 と Bb3（倍音）
             NoteEvent(1.0, 2.0, 41, 100)]
    assert [(n.pitch, n.end) for n in make_monophonic(notes)] == [(39, 1.0), (41, 2.0)]


def _transcription_with_chords():
    tr = Transcription(tempo=120, beat_offset=0.0)
    tr.parts["piano"] = [NoteEvent(0, 4.0, p) for p in (58, 62, 65)]
    tr.chords = [ChordEvent(0.0, 2.0, 10, "maj7"), ChordEvent(2.0, 3.0, 3, "", bass=7),
                 ChordEvent(3.0, 4.0, 5, "7")]
    return tr


def test_chord_symbols_in_musicxml(tmp_path: Path):
    xml = write_musicxml(build_score(_transcription_with_chords(), "t"), tmp_path / "t.musicxml")
    score = converter.parse(xml)
    symbols = list(score.parts[0].recurse().getElementsByClass(harmony.ChordSymbol))
    assert [(s.root().name, s.bass().name) for s in symbols] == [("B-", "B-"), ("E-", "G"),
                                                                  ("F", "F")]
    assert [s.getOffsetInHierarchy(score) for s in symbols] == [0.0, 4.0, 6.0]


def test_chord_chart(tmp_path: Path):
    path = write_chord_chart(_transcription_with_chords(), tmp_path / "c.txt")
    lines = path.read_text(encoding="utf-8").splitlines()
    assert lines[0].startswith("Tempo: 120 BPM")
    assert lines[2].split("|")[1:3] == [" Bbmaj7   ", " Eb/G F7  "]
