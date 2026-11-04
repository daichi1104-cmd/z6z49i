"""AIモデルを使わない部分（音符の整理・楽譜生成・ドラム検出）のテスト。"""

from pathlib import Path

import numpy as np
import pretty_midi
import soundfile as sf
from music21 import converter

from band2score.models import NoteEvent, Transcription
from band2score.score import build_score, write_midi, write_musicxml
from band2score.transcribe import HIHAT, KICK, SNARE, make_monophonic, transcribe_drums


def test_make_monophonic_cuts_overlaps_and_drops_simultaneous():
    notes = [
        NoteEvent(0.0, 1.0, 60, 100),
        NoteEvent(0.01, 1.0, 72, 40),  # ほぼ同時の弱い音（倍音）→ 捨てる
        NoteEvent(0.5, 1.5, 62, 90),  # 前の音にかぶる → 前の音を 0.5 で切る
    ]
    mono = make_monophonic(notes)
    assert [n.pitch for n in mono] == [60, 62]
    assert mono[0].end == 0.5


def _transcription():
    beat = 0.5  # 120 BPM
    tr = Transcription(tempo=120, beat_offset=0.0)
    tr.parts["bass"] = [NoteEvent(i * beat, i * beat + 0.45, 36) for i in range(8)]
    tr.parts["piano"] = [NoteEvent(0, 0.95, p) for p in (60, 64, 67)]
    tr.parts["drums"] = [NoteEvent(0, 0.1, KICK), NoteEvent(0, 0.1, HIHAT),
                         NoteEvent(0.5, 0.6, SNARE)]
    return tr


def test_build_score_writes_valid_musicxml(tmp_path: Path):
    tr = _transcription()
    xml = write_musicxml(build_score(tr, "test"), tmp_path / "t.musicxml")
    parsed = converter.parse(xml)
    names = [p.partName for p in parsed.parts]
    assert names == ["Piano", "Bass", "Drums"]
    bass = parsed.parts[1]
    # 0.45 秒の音は次の音まで伸ばされて 4分音符になる
    durations = [n.quarterLength for n in bass.recurse().notes]
    assert durations == [1.0] * 8
    assert len(bass.getElementsByClass("Measure")) == 2
    piano_chord = parsed.parts[0].recurse().notes[0]
    assert {p.midi for p in piano_chord.pitches} == {60, 64, 67}


def test_write_midi(tmp_path: Path):
    path = write_midi(_transcription(), tmp_path / "t.mid")
    pm = pretty_midi.PrettyMIDI(str(path))
    assert [i.name for i in pm.instruments] == ["Piano", "Bass", "Drums"]
    assert pm.instruments[2].is_drum


def test_transcribe_drums_separates_kick_and_hihat(tmp_path: Path):
    sr = 22050
    rng = np.random.default_rng(0)
    y = np.zeros(sr * 2)
    t = np.arange(int(0.2 * sr)) / sr
    kick = np.sin(2 * np.pi * 60 * t) * np.exp(-t * 20)
    hat = np.diff(rng.standard_normal(len(t)), prepend=0) * np.exp(-t * 60) * 0.3
    for start, sig in [(0.25, kick), (0.75, hat), (1.25, kick), (1.75 - 0.2, hat)]:
        i = int(start * sr)
        y[i:i + len(sig)] += sig
    path = tmp_path / "drums.wav"
    sf.write(path, y, sr)
    hits = transcribe_drums(path)
    kicks = [n.start for n in hits if n.pitch == KICK]
    hats = [n.start for n in hits if n.pitch == HIHAT]
    assert len(kicks) == 2 and abs(kicks[0] - 0.25) < 0.03
    assert len(hats) == 2 and abs(hats[0] - 0.75) < 0.03
