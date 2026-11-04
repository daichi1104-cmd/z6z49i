"""音声 → 音符（NoteEvent）への変換。"""

from __future__ import annotations

import logging
from pathlib import Path

import librosa
import numpy as np

from .models import NoteEvent, StemSettings

# GM ドラム番号
KICK, SNARE, HIHAT = 36, 38, 42


def estimate_tempo(audio_path: Path) -> tuple[float, float]:
    """テンポ（BPM）と最初の拍の位置（秒）を推定する。"""
    y, sr = librosa.load(audio_path, sr=22050, mono=True)
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr, units="time")
    tempo = float(np.atleast_1d(tempo)[0])
    if len(beats) >= 8:
        # 検出した拍の位置に直線を当てはめて、テンポと拍の位置を細かく求める
        idx = np.arange(len(beats))
        period, intercept = np.polyfit(idx, beats, 1)
        tempo = 60.0 / period
        beats = intercept + idx * period
    if tempo <= 0:
        tempo = 120.0
    # 速すぎ・遅すぎる推定は倍テン/ハーフテンとして直す
    while tempo < 70:
        tempo *= 2
    while tempo > 180:
        tempo /= 2
    first_beat = float(beats[0]) if len(beats) else 0.0
    # 最初の拍が遅い（イントロに無音がある等）ときは 1拍の長さで割った余りにそろえる
    first_beat %= 60.0 / tempo
    return tempo, first_beat


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
        notes = make_monophonic(notes)
    return notes


def make_monophonic(notes: list[NoteEvent]) -> list[NoteEvent]:
    """同時に鳴る音を 1つに絞る（単音楽器用）。

    同じ時刻に始まる音は一番強いものを残し、前の音が次の音にかぶるときは切る。
    """
    if not notes:
        return []
    notes = sorted(notes, key=lambda n: (n.start, -n.velocity))
    result: list[NoteEvent] = []
    for note in notes:
        if result and abs(note.start - result[-1].start) < 0.03:
            continue  # ほぼ同時に始まる弱い音（倍音の誤検出が多い）は捨てる
        if result and result[-1].end > note.start:
            result[-1].end = note.start
        result.append(NoteEvent(note.start, note.end, note.pitch, note.velocity))
    return [n for n in result if n.end - n.start > 0.03]


# ドラムの帯域（Hz）: キック=低域、スネア=中域、ハイハット/シンバル=高域
DRUM_BANDS = {KICK: (30, 150), SNARE: (180, 2500), HIHAT: (6000, 11000)}


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
