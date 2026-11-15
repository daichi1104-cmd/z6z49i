"""AIモデルを使わない部分（音符の整理・楽譜生成・ドラム検出）のテスト。"""

from pathlib import Path

import numpy as np
import pretty_midi
import soundfile as sf
from music21 import converter

from band2score.models import NoteEvent, Transcription
from band2score.rhythm import BeatGrid
from band2score.score import build_score, write_midi, write_musicxml
from band2score.transcribe import (HIHAT, KICK, SNARE, fix_octave_errors, make_monophonic,
                                   prune_overtones, transcribe_drums)


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
    tr = Transcription(grid=BeatGrid.constant(120, 0.0, 10))
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


def test_fix_octave_errors_moves_quiet_jumps_but_keeps_real_leaps():
    def seq(pitches, vels):
        return [NoteEvent(i * 0.5, i * 0.5 + 0.45, p, v) for i, (p, v) in enumerate(zip(pitches, vels))]

    # 弱い C6・B5（倍音の取り違え）は 1オクターブ下に直る
    fixed = fix_octave_errors(seq([74, 84, 83, 72, 74], [90, 45, 45, 90, 90]))
    assert [n.pitch for n in fixed] == [74, 72, 71, 72, 74]
    # 普通の強さで弾いたオクターブの跳躍はそのまま
    leap = fix_octave_errors(seq([60, 72, 71, 60, 62], [90, 92, 88, 90, 90]))
    assert [n.pitch for n in leap] == [60, 72, 71, 60, 62]


def test_prune_overtones_keeps_played_octaves():
    chord_with_ghost = [NoteEvent(0, 1, 55, 90), NoteEvent(0, 1, 60, 90), NoteEvent(0, 1, 64, 90),
                        NoteEvent(0.01, 0.2, 74, 40)]  # D5 = G3 の 3倍音（短く弱い）
    assert sorted(n.pitch for n in prune_overtones(chord_with_ghost)) == [55, 60, 64]
    octave = [NoteEvent(0, 1, 36, 90), NoteEvent(0, 1, 48, 85)]  # 左手のオクターブ
    assert len(prune_overtones(octave)) == 2


def test_piano_grand_staff(tmp_path: Path):
    tr = Transcription(grid=BeatGrid.constant(120, 0.0, 10))
    tr.parts["piano"] = ([NoteEvent(i, i + 0.95, p) for i in range(4) for p in (36, 48)]
                         + [NoteEvent(i * 0.5, i * 0.5 + 0.45, p) for i in range(8)
                            for p in (64, 67, 72)])
    xml = write_musicxml(build_score(tr, "gs"), tmp_path / "gs.musicxml")
    text = xml.read_text()
    assert "<staves>2</staves>" in text
    parts = converter.parse(xml).parts
    assert min(p.midi for p in parts[1].pitches) == 36
    assert min(p.midi for p in parts[0].pitches) >= 60
