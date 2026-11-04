"""採譜結果（秒単位の音符）→ 楽譜（MusicXML）と MIDI への変換。"""

from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

import pretty_midi
from music21 import (chord, clef, instrument, key, metadata, meter, note, percussion,
                     stream, tempo as m21tempo)

from .models import PART_ORDER, STEM_SETTINGS, NoteEvent, Transcription
from .transcribe import HIHAT, KICK, SNARE

BEATS_PER_BAR = 4
# ドラム譜で使う五線上の位置と符頭
DRUM_DISPLAY = {KICK: ("F4", "normal"), SNARE: ("C5", "normal"), HIHAT: ("G5", "x")}


def _to_beats(t: float, tr: Transcription, shift: float) -> float:
    return (t - tr.beat_offset) * tr.tempo / 60.0 + shift


def _quantize(x: float, grid: float) -> float:
    return round(x / grid) * grid


def _bar_shift(tr: Transcription) -> float:
    """1小節目より前に始まる音（弱起など）があるとき、何拍ずらすか。"""
    starts = [n.start for notes in tr.parts.values() for n in notes]
    if not starts:
        return 0.0
    earliest = _to_beats(min(starts), tr, 0.0)
    if earliest >= -0.125:  # 32分音符より小さいずれは 1小節目の頭とみなす
        return 0.0
    return math.ceil(-earliest / BEATS_PER_BAR) * BEATS_PER_BAR


def _quantized_notes(notes: list[NoteEvent], tr: Transcription, shift: float,
                     grid: float) -> list[tuple[float, float, NoteEvent]]:
    """(開始拍, 長さ, 元の音符) のリストに変換し、グリッドにそろえる。"""
    out = []
    for n in notes:
        start = _quantize(_to_beats(n.start, tr, shift), grid)
        end = _quantize(_to_beats(n.end, tr, shift), grid)
        if start < 0:
            if start < -grid:
                continue
            start = 0.0
        out.append((start, max(end - start, grid), n))
    return _close_small_gaps(out, grid)


def _close_small_gaps(notes: list[tuple[float, float, NoteEvent]],
                      grid: float) -> list[tuple[float, float, NoteEvent]]:
    """音の終わりが次の音の直前（1グリッド以内）なら、次の音までのばす。

    演奏では音を少し短めに切ることが多く、そのままだと細かい休符や
    タイだらけの読みにくい楽譜になるため。
    """
    onsets = sorted({start for start, _, _ in notes})
    out = []
    for start, dur, n in notes:
        end = start + dur
        later = [o for o in onsets if o > start]
        if later:
            gap = later[0] - end
            if 0 < gap <= grid + 1e-9:
                end = later[0]
        out.append((start, end - start, n))
    return out


def _pitched_part(stem: str, notes: list[NoteEvent], tr: Transcription, shift: float,
                  grid: float, ks: key.Key | None) -> stream.Part:
    settings = STEM_SETTINGS[stem]
    raw = stream.Part()
    seen: set[tuple[float, int]] = set()
    for start, dur, n in _quantized_notes(notes, tr, shift, grid):
        if (start, n.pitch) in seen:
            continue  # グリッドにそろえた結果、同じ位置に重なった同じ音
        seen.add((start, n.pitch))
        m21note = note.Note(n.pitch, quarterLength=dur)
        m21note.volume.velocity = n.velocity
        raw.insert(start, m21note)

    # 重なり合う音を縦に切りそろえて和音にする（必要な所はタイでつなぐ）
    part = raw.chordify() if len(raw.notes) else stream.Part()
    part.partName = settings.name
    part.partAbbreviation = settings.name[:2] + "."
    inst = instrument.Instrument()
    inst.partName = settings.name
    inst.partAbbreviation = settings.name[:2] + "."
    inst.midiProgram = settings.gm_program
    part.insert(0, inst)
    part.insert(0, _clef(settings.clef))
    if ks is not None:
        part.insert(0, key.KeySignature(ks.sharps))
    _simplify_chords(part)
    _respell(part, ks)
    return part


def _respell(part: stream.Part, ks: key.Key | None) -> None:
    """臨時記号を調に合わせて整える（フラット系の調では C# ではなく D♭ と書く）。"""
    use_flats = ks is not None and ks.sharps < 0
    for p in (p for n in part.recurse().notes for p in n.pitches):
        if p.accidental is not None and p.accidental.alter == 0:
            p.accidental = None  # 余計なナチュラルを付けない
        elif use_flats and p.accidental is not None and p.accidental.alter > 0:
            flat = p.getEnharmonic()
            p.step, p.octave, p.accidental = flat.step, flat.octave, flat.accidental


def _simplify_chords(part: stream.Part) -> None:
    """chordify で 1音だけになった和音を普通の音符に戻す。"""
    for c in list(part.recurse().getElementsByClass(chord.Chord)):
        if len(c.pitches) == 1:
            n = note.Note(c.pitches[0], quarterLength=c.quarterLength)
            n.tie = c.tie
            c.activeSite.replace(c, n)


def _drum_part(notes: list[NoteEvent], tr: Transcription, shift: float,
               grid: float) -> stream.Part:
    part = stream.Part()
    part.partName = "Drums"
    part.partAbbreviation = "Dr."
    perc = instrument.Percussion()
    perc.partName = "Drums"
    perc.partAbbreviation = "Dr."
    part.insert(0, perc)
    part.insert(0, clef.PercussionClef())

    groups: dict[float, set[int]] = {}
    for start, _, n in _quantized_notes(notes, tr, shift, grid):
        groups.setdefault(start, set()).add(n.pitch)
    onsets = sorted(groups)
    for i, start in enumerate(onsets):
        nxt = onsets[i + 1] if i + 1 < len(onsets) else start + 1.0
        # 次の打点まで、ただし拍の頭をまたがない長さにする（読みやすさ優先）
        beat_end = math.floor(start) + 1.0
        dur = max(min(nxt, beat_end) - start, grid)
        heads = []
        for pitch in sorted(groups[start]):
            display, head = DRUM_DISPLAY.get(pitch, ("C5", "normal"))
            u = note.Unpitched(displayName=display)
            u.notehead = head
            u.stemDirection = "up"
            heads.append(u)
        el = heads[0] if len(heads) == 1 else percussion.PercussionChord(heads)
        el.quarterLength = dur
        part.insert(start, el)
    return part


def _clef(name: str) -> clef.Clef:
    return {
        "treble": clef.TrebleClef(),
        "bass": clef.BassClef(),
        "treble8vb": clef.Treble8vbClef(),
        "percussion": clef.PercussionClef(),
    }[name]


def _estimate_key(tr: Transcription) -> key.Key | None:
    s = stream.Stream()
    for stem, notes in tr.parts.items():
        if stem == "drums":
            continue
        for n in notes:
            s.append(note.Note(n.pitch, quarterLength=max(n.end - n.start, 0.1)))
    if not len(s.notes):
        return None
    try:
        return s.analyze("key")
    except Exception:  # 音が少なすぎる等
        return None


def build_score(tr: Transcription, title: str, grid: float = 0.25) -> stream.Score:
    """採譜結果から music21 の Score を組み立てる。"""
    shift = _bar_shift(tr)
    ks = _estimate_key(tr)
    score = stream.Score()
    score.insert(0, metadata.Metadata(title=title, composer="band2score (自動採譜)"))

    for stem in PART_ORDER:
        notes = tr.parts.get(stem)
        if not notes:
            continue
        if stem == "drums":
            part = _drum_part(notes, tr, shift, grid)
        else:
            part = _pitched_part(stem, notes, tr, shift, grid, ks)
        part.insert(0, meter.TimeSignature(f"{BEATS_PER_BAR}/4"))
        score.insert(0, part)

    parts = list(score.parts)
    if parts:
        parts[0].insert(0, m21tempo.MetronomeMark(number=round(tr.tempo)))
        # 全パートの長さを最後の小節線までそろえる
        end = max(p.highestTime for p in parts)
        end = math.ceil(end / BEATS_PER_BAR) * BEATS_PER_BAR or BEATS_PER_BAR
        for p in parts:
            if p.highestTime < end:
                p.insert(p.highestTime, note.Rest(quarterLength=end - p.highestTime))
            p.makeRests(fillGaps=True, inPlace=True, hideRests=False)
            p.makeMeasures(inPlace=True)
            p.makeTies(inPlace=True)
            p.makeBeams(inPlace=True)
            if p.partName != "Drums":
                p.makeAccidentals(inPlace=True, overrideStatus=True)
    return score


def write_musicxml(score: stream.Score, path: Path) -> Path:
    score.write("musicxml", fp=str(path))
    return path


def write_pdf(musicxml: Path, pdf: Path) -> Path | None:
    """MuseScore が入っていれば PDF も作る。無ければ None。"""
    for exe in ("mscore", "musescore", "mscore4portable", "MuseScore4", "musescore4",
                "mscore3", "musescore3"):
        path = shutil.which(exe)
        if path:
            subprocess.run([path, "-o", str(pdf), str(musicxml)], check=True,
                           capture_output=True)
            return pdf
    return None


def write_midi(tr: Transcription, path: Path) -> Path:
    """採譜結果をそのまま（クオンタイズ前のタイミングで）MIDI に書き出す。"""
    pm = pretty_midi.PrettyMIDI(initial_tempo=tr.tempo)
    for stem in PART_ORDER:
        notes = tr.parts.get(stem)
        if not notes:
            continue
        settings = STEM_SETTINGS[stem]
        inst = pretty_midi.Instrument(program=settings.gm_program,
                                      is_drum=(stem == "drums"), name=settings.name)
        for n in notes:
            inst.notes.append(pretty_midi.Note(velocity=n.velocity, pitch=n.pitch,
                                               start=n.start, end=max(n.end, n.start + 0.02)))
        pm.instruments.append(inst)
    pm.write(str(path))
    return path
