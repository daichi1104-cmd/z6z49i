"""音声からコード（和音の名前）を推定する。

ベース・ギター・ピアノなど和音を鳴らす楽器の音を混ぜ、拍ごとに
「12音それぞれがどれだけ鳴っているか」（クロマ）を求めて、コードの型と照らし合わせる。
コードがころころ変わらないように、Viterbi アルゴリズムで前後のつながりも考えて決める。
ルートと分数コード（C/E など）はベースの一番低い音から判断する。
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .models import NoteEvent

import librosa
import numpy as np

SR = 22050
HOP = 512
NOTE_NAMES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
NOTE_NAMES_FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

# 基本の三和音: (表記, ルートからの半音, 好みの重み)
TRIADS: list[tuple[str, tuple[int, ...], float]] = [
    ("", (0, 4, 7), 1.00),
    ("m", (0, 3, 7), 1.00),
    ("sus4", (0, 5, 7), 0.94),
    ("dim", (0, 3, 6), 0.92),
]
# 三和音に 7th を足す条件: (三和音, 7th の半音, 付ける表記)
SEVENTHS = [("", 10, "7"), ("", 11, "maj7"), ("m", 10, "m7"), ("sus4", 10, "7sus4")]
SEVENTH_THRESHOLD = 0.35  # 7th の音がこれ以上（一番強い音を 1 として）鳴っていたら付ける
BASS_WEIGHT = 1.0  # ベースの音を和音の判定にどれだけ効かせるか
SHARPNESS = 60.0  # スコアの差をどれだけ強く確率の差にするか
NO_CHORD = "N.C."


@dataclass
class ChordEvent:
    """秒単位のコード。bass はルート以外の音がベースのとき（分数コード）だけ入る。"""

    start: float
    end: float
    root: int  # 0=C … 11=B
    quality: str
    bass: int | None = None

    def label(self, flats: bool = False) -> str:
        if self.quality == NO_CHORD:
            return NO_CHORD
        names = NOTE_NAMES_FLAT if flats else NOTE_NAMES_SHARP
        text = names[self.root] + self.quality
        if self.bass is not None:
            text += "/" + names[self.bass]
        return text

    def music21_figure(self, flats: bool = False) -> str:
        """music21 の ChordSymbol 用の表記（フラットは「-」で書く）。"""
        return self.label(flats).replace("b", "-")


def _templates() -> tuple[list[tuple[int, str, tuple[int, ...]]], np.ndarray, np.ndarray]:
    labels, mats, weights = [], [], []
    for root in range(12):
        for quality, intervals, weight in TRIADS:
            t = np.zeros(12)
            for i in intervals:
                t[(root + i) % 12] = 1.0
            t[root] += 0.25  # ルートを少し強めに
            labels.append((root, quality, intervals))
            mats.append(t / np.linalg.norm(t))
            weights.append(weight)
    return labels, np.array(mats), np.array(weights)


def _load_mix(paths: list[Path]) -> np.ndarray:
    mix = None
    for p in paths:
        y, _ = librosa.load(p, sr=SR, mono=True)
        if mix is None:
            mix = y
        else:
            n = max(len(mix), len(y))
            mix = np.pad(mix, (0, n - len(mix))) + np.pad(y, (0, n - len(y)))
    return mix if mix is not None else np.zeros(SR)


def _segments(data: np.ndarray, frames: np.ndarray, aggregate=np.median) -> np.ndarray:
    """フレームごとの値を区間 [frames[i], frames[i+1]) ごとにまとめる。

    librosa.util.sync は先頭に区間を自動で足すことがあり、拍の位置がずれるので使わない。
    """
    cols = []
    for a, b in zip(frames[:-1], frames[1:]):
        a, b = int(a), max(int(b), int(a) + 1)
        block = data[:, a:b]
        cols.append(aggregate(block, axis=1) if block.shape[1] else np.zeros(data.shape[0]))
    return np.stack(cols, axis=1)


def _bass_from_notes(notes: list[NoteEvent], bounds: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """採譜したベースの音から、区間ごとに一番長く鳴っている音（音名）を求める。"""
    n = len(bounds) - 1
    pcs = np.zeros(n, dtype=int)
    clear = np.zeros(n, dtype=bool)
    for i in range(n):
        a, b = bounds[i], bounds[i + 1]
        sounding = []  # (鳴っている長さ, 音の高さ)
        for note in notes:
            overlap = min(note.end, b) - max(note.start, a)
            if overlap > 0:
                sounding.append((overlap, note.pitch))
        if not sounding:
            continue
        longest = max(o for o, _ in sounding)
        if longest < 0.25 * (b - a):
            continue
        # ある程度の長さ鳴っている音のうち一番低い音（上の音は倍音の誤検出が多い）
        lowest = min(p for o, p in sounding if o >= 0.5 * longest)
        pcs[i] = lowest % 12
        clear[i] = True
    return pcs, clear


def _bass_from_audio(y: np.ndarray, frames: np.ndarray, n: int) -> tuple[np.ndarray, np.ndarray]:
    """ベースの音声（または元の音源の低音域）から、区間ごとのベース音を求める。"""
    bc = librosa.feature.chroma_cqt(y=y, sr=SR, hop_length=HOP,
                                    fmin=librosa.note_to_hz("C1"), n_octaves=3)
    bc = _segments(bc, frames)[:, :n]
    return bc.argmax(axis=0), bc.max(axis=0) > 0.5


def detect_chords(harmony_paths: list[Path], tempo: float, beat_offset: float,
                  bass_path: Path | None = None, bass_notes: list[NoteEvent] | None = None,
                  beats_per_chord: int = 1, change_penalty: float = 0.8) -> list[ChordEvent]:
    """コード進行を推定する。

    harmony_paths: 和音を鳴らす楽器の音声（ギター・ピアノなど。ベースは入れない方が正確）
    bass_path:     ベースの音声。ルート・分数コードの判定に使う
    bass_notes:    採譜済みのベースの音。あれば bass_path より優先して使う
    beats_per_chord: コードを判定する細かさ（拍）。1 なら拍ごとにコードが変わりうる
    change_penalty:  0〜1。大きいほどコードが変わりにくくなる
    """
    y = _load_mix(harmony_paths)
    if not np.any(y):
        return []
    y = librosa.effects.harmonic(y)  # 打楽器っぽい成分を減らす
    duration = len(y) / SR

    # 区切り（楽譜と同じテンポ・拍位置を使う）
    seg = 60.0 / tempo * beats_per_chord
    bounds = np.arange(beat_offset, duration, seg)
    if len(bounds) < 2:
        return []
    n = len(bounds) - 1
    frames = librosa.time_to_frames(bounds, sr=SR, hop_length=HOP)

    # 和音は C3 より上で見る（低音域はベースの倍音が混ざり、時間方向にもぼやけるため）
    chroma = librosa.feature.chroma_cqt(y=y, sr=SR, hop_length=HOP,
                                        fmin=librosa.note_to_hz("C3"), n_octaves=4)
    chroma = _segments(chroma, frames)[:, :n]
    energy = _segments(librosa.feature.rms(y=y, hop_length=HOP), frames, np.mean)[0, :n]

    if bass_path is not None:
        yb, _ = librosa.load(bass_path, sr=SR, mono=True)
        bass_pc, bass_clear = _bass_from_audio(yb, frames, n)
    else:
        bass_pc, bass_clear = _bass_from_audio(y, frames, n)
    if bass_notes:
        # 採譜したベースの音を優先し、はっきりしない区間だけ音声からの推定を使う
        note_pc, note_clear = _bass_from_notes(bass_notes, bounds)
        bass_pc = np.where(note_clear, note_pc, bass_pc)
        bass_clear = note_clear | bass_clear

    # ベースの音も和音の一部として足す（上の楽器だけだとルートの無い和音に見えることがある）
    chroma = chroma / (chroma.max(axis=0, keepdims=True) + 1e-9)
    chroma[bass_pc[bass_clear], np.nonzero(bass_clear)[0]] += BASS_WEIGHT

    labels, mats, weights = _templates()
    norm = chroma / (np.linalg.norm(chroma, axis=0, keepdims=True) + 1e-9)
    scores = (mats @ norm) * weights[:, None]  # (コード数, 区間数)

    # ベースの音がルートと一致するコードを少し優先する
    roots = np.array([r for r, _, _ in labels])
    scores = scores + 0.08 * ((roots[:, None] == bass_pc[None, :]) & bass_clear[None, :])

    # 無音に近い区間は「コードなし」
    quiet = energy < 0.05 * (energy.max() + 1e-9)
    scores = np.vstack([scores, np.where(quiet, 1.0, 0.0)[None, :]])

    # スコア → 確率にして、コードが変わりにくくなるように Viterbi で並びを決める
    prob = np.exp((scores - scores.max(axis=0, keepdims=True)) * SHARPNESS)
    prob /= prob.sum(axis=0, keepdims=True)
    n_states = prob.shape[0]
    path = librosa.sequence.viterbi(prob, librosa.sequence.transition_loop(n_states, change_penalty))

    # 同じコードが続く区間をまとめる（分数コードはベースが変わったら分ける）
    runs: list[tuple[int, int, int, int | None]] = []  # (state, 開始区間, 終了区間, bass)
    for i, state in enumerate(path):
        bass = None
        if state != n_states - 1 and bass_clear[i]:
            root, _, intervals = labels[state]
            pc = int(bass_pc[i])
            if pc != root and (pc - root) % 12 in intervals:
                bass = pc  # ルート以外のコードの音がベース → 分数コード
        if runs and runs[-1][0] == state and runs[-1][3] == bass:
            runs[-1] = (state, runs[-1][1], i + 1, bass)
        else:
            runs.append((state, i, i + 1, bass))

    events: list[ChordEvent] = []
    for state, a, b, bass in runs:
        start, end = float(bounds[a]), float(bounds[b])
        if state == n_states - 1:
            events.append(ChordEvent(start, end, 0, NO_CHORD))
            continue
        root, quality, _ = labels[state]
        quality = _add_seventh(root, quality, chroma[:, a:b].mean(axis=1))
        events.append(ChordEvent(start, end, root, quality, bass))
    # 前後の「コードなし」は書かない
    while events and events[0].quality == NO_CHORD:
        events.pop(0)
    while events and events[-1].quality == NO_CHORD:
        events.pop()
    return events


def _add_seventh(root: int, quality: str, chroma: np.ndarray) -> str:
    """コード全体で 7th の音がはっきり鳴っていれば 7 / maj7 / m7 を付ける。"""
    level = chroma / (chroma.max() + 1e-9)
    best, best_level = quality, SEVENTH_THRESHOLD
    for triad, interval, name in SEVENTHS:
        if triad == quality and level[(root + interval) % 12] >= best_level:
            best, best_level = name, level[(root + interval) % 12]
    return best
