"""音声 → 音符（NoteEvent）への変換。"""

from __future__ import annotations

import logging
from pathlib import Path

import librosa
import numpy as np

from .models import NoteEvent, StemSettings

# GM ドラム番号
KICK, SNARE, HIHAT = 36, 38, 42


def transcribe_pitched(audio_path: Path, settings: StemSettings) -> list[NoteEvent]:
    """basic-pitch でメロディ・和音のある楽器を採譜する。"""
    # basic-pitch は import 時に TensorFlow 等が無い旨の警告を出すので、その間だけ抑える
    root = logging.getLogger()
    level = root.level
    root.setLevel(logging.ERROR)
    try:
        from basic_pitch.inference import predict
    finally:
        root.setLevel(level)

    _, _, events = predict(
        str(audio_path),
        onset_threshold=settings.onset_threshold,
        frame_threshold=settings.frame_threshold,
        minimum_frequency=settings.min_freq,
        maximum_frequency=settings.max_freq,
        minimum_note_length=80,
    )
    notes = [
        NoteEvent(float(s), float(e), int(p), int(np.clip(a * 127, 1, 127)))
        for s, e, p, a, _ in events
    ]
    notes.sort(key=lambda n: (n.start, n.pitch))
    if settings.monophonic:
        notes = merge_fragments(fix_octave_errors(make_monophonic(notes)))
    else:
        notes = prune_overtones(notes)
    return notes


# 倍音の音程（半音）: 2倍音=オクターブ, 3倍音=オクターブ+5度, 4倍音=2オクターブ, 5倍音, 6倍音
HARMONIC_INTERVALS = (12, 19, 24, 28, 31)


def prune_overtones(notes: list[NoteEvent]) -> list[NoteEvent]:
    """和音のパートから、倍音を拾っただけの音を除く。

    ほぼ同時に始まる低い音の倍音の高さにあり、その音より明らかに弱いか短い音を捨てる。
    （本当に弾いたオクターブは、ふつう同じくらいの強さ・長さで鳴るので残る）
    """
    keep = []
    for n in notes:
        ghost = False
        for m in notes:
            if m is n or n.pitch - m.pitch not in HARMONIC_INTERVALS:
                continue
            if abs(n.start - m.start) > 0.06:
                continue
            weaker = n.velocity < 0.75 * m.velocity
            shorter = (n.end - n.start) < 0.6 * (m.end - m.start)
            if weaker or shorter:
                ghost = True
                break
        if not ghost:
            keep.append(n)
    return keep


# 倍音として誤検出されやすい音程（半音数）: オクターブ、オクターブ+5度、2オクターブ
OVERTONE_INTERVALS = (12, 19, 24)


def make_monophonic(notes: list[NoteEvent]) -> list[NoteEvent]:
    """同時に鳴る音を 1つに絞る（単音楽器用）。

    同じ時刻に始まる音は一番強いものを残し、前の音が次の音にかぶるときは切る。
    ただし、鳴っている音の倍音にあたる高さの音は誤検出として捨てる。
    """
    if not notes:
        return []
    notes = sorted(notes, key=lambda n: (n.start, -n.velocity))
    result: list[NoteEvent] = []
    for note in notes:
        if result and abs(note.start - result[-1].start) < 0.03:
            continue  # ほぼ同時に始まる弱い音（倍音の誤検出が多い）は捨てる
        if result and result[-1].end > note.start:
            prev = result[-1]
            if note.pitch - prev.pitch in OVERTONE_INTERVALS and note.velocity <= prev.velocity * 1.2:
                continue  # 鳴っている音の倍音（オクターブ上など）を拾っただけ
            prev.end = note.start
        result.append(NoteEvent(note.start, note.end, note.pitch, note.velocity))
    return [n for n in result if n.end - n.start > 0.03]


# ドラムの帯域（Hz）: キック=低域、スネア=中域、ハイハット/シンバル=高域
DRUM_BANDS = {KICK: (30, 150), SNARE: (180, 2500), HIHAT: (6000, 11000)}


def merge_fragments(notes: list[NoteEvent], max_gap: float = 0.02,
                    short: float = 0.15) -> list[NoteEvent]:
    """1つの音が途中で切れて 2つに検出されたものをつなぐ（単音のパート用）。

    同じ高さの音がすき間なく続き、どちらかがとても短いときは、同じ音が切れただけとみなす。
    （本当に弾き直した同じ音は、ふつうわずかなすき間があり、極端に短くもない）
    """
    out: list[NoteEvent] = []
    for n in notes:
        if out:
            prev = out[-1]
            contiguous = prev.pitch == n.pitch and n.start - prev.end < max_gap
            if contiguous and min(prev.end - prev.start, n.end - n.start) < short:
                prev.end = max(prev.end, n.end)
                prev.velocity = max(prev.velocity, n.velocity)
                continue
        out.append(NoteEvent(n.start, n.end, n.pitch, n.velocity))
    return out


def fix_octave_errors(notes: list[NoteEvent], max_run: int = 3) -> list[NoteEvent]:
    """単音のパートで、1オクターブずれて検出された音を直す。

    倍音を本来の音と取り違えると、前後から大きく（9半音以上）跳んだ、弱めの音として出てくる。
    そういう音（数音続くこともある）を 1オクターブ動かすと前後の音に近づくなら、動かす。
    """
    if len(notes) < 3:
        return notes
    typical = float(np.median([n.velocity for n in notes]))
    out = [NoteEvent(n.start, n.end, n.pitch, n.velocity) for n in notes]
    # 跳躍の小さい音どうしをひとまとまり（run）にする
    runs: list[list[int]] = [[0]]
    for i in range(1, len(out)):
        if abs(out[i].pitch - out[i - 1].pitch) >= 9:
            runs.append([i])
        else:
            runs[-1].append(i)
    for r, run in enumerate(runs):
        if len(run) > max_run or len(runs) == 1:
            continue
        if np.mean([out[i].velocity for i in run]) > 0.8 * typical:
            continue
        neighbors = []
        if r > 0:
            neighbors.append((out[run[0]].pitch, out[runs[r - 1][-1]].pitch))
        if r + 1 < len(runs):
            neighbors.append((out[run[-1]].pitch, out[runs[r + 1][0]].pitch))
        for shift in (-12, 12):
            if all(abs(mine + shift - other) < abs(mine - other) for mine, other in neighbors):
                for i in run:
                    out[i].pitch += shift
                break
    return out


def transcribe_drums(audio_path: Path) -> list[NoteEvent]:
    """ドラムの打点を帯域ごとに検出し、キック・スネア・ハイハットに分ける。

    それぞれの帯域で音量が急に大きくなった所を打点とみなす簡易的な方法なので、
    タムやシンバルの種類までは区別しない。
    """
    y, sr = librosa.load(audio_path, sr=22050, mono=True)
    if not np.any(y):
        return []
    hop = 256
    spec = np.abs(librosa.stft(y, n_fft=2048, hop_length=hop))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=2048)
    times = librosa.frames_to_time(np.arange(spec.shape[1]), sr=sr, hop_length=hop)

    notes: list[NoteEvent] = []
    for pitch, (lo, hi) in DRUM_BANDS.items():
        band = spec[(freqs >= lo) & (freqs < hi)]
        if band.size == 0:
            continue
        envelope = librosa.onset.onset_strength(
            S=librosa.amplitude_to_db(band, ref=np.max), sr=sr, hop_length=hop)
        if envelope.max() <= 0:
            continue
        envelope = envelope / envelope.max()
        frames = librosa.onset.onset_detect(
            onset_envelope=envelope, sr=sr, hop_length=hop,
            delta=0.15, wait=int(0.06 * sr / hop))
        band_energy = band.sum(axis=0)
        loudest = band_energy.max() or 1.0
        levels = np.array([band_energy[f:f + 4].max(initial=0.0) / loudest for f in frames])
        if levels.size == 0:
            continue
        # キック・スネアの帯域には他の太鼓の音も漏れて入るので、
        # その帯域の普段の強さ（上位 10%）に比べてずっと弱い打点は捨てる
        floor = 0.08 if pitch == HIHAT else max(0.08, 0.45 * float(np.percentile(levels, 90)))
        for f, level in zip(frames, levels):
            if level < floor:
                continue
            t = float(times[f])
            vel = int(np.clip(40 + level * 87, 1, 127))
            notes.append(NoteEvent(t, t + 0.1, pitch, vel))
    notes.sort(key=lambda n: (n.start, n.pitch))
    return notes
