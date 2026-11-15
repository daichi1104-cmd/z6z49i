"""拍と小節の推定。

実際の演奏はクリック（メトロノーム）無しだとテンポが少しずつ揺れるので、
「テンポ 1つ + 最初の拍の位置」ではなく、拍ごとの時刻（拍の格子）を求めて、
秒 → 拍の変換をその格子に沿って行う。
さらに、キックの位置・コードが変わる位置・スネアの 2拍4拍から、どの拍が小節の頭かを決める。
"""

from __future__ import annotations

from dataclasses import dataclass

import librosa
import numpy as np
from scipy.signal import savgol_filter

SR = 22050
HOP = 256
BEATS_PER_BAR = 4


@dataclass
class BeatGrid:
    """拍の格子。times[k] が k 番目の拍の時刻（秒）。downbeat は小節の頭になる拍の番号 (0〜3)。"""

    times: np.ndarray
    downbeat: int = 0

    @classmethod
    def constant(cls, tempo: float, offset: float = 0.0, duration: float = 600.0,
                 downbeat: int = 0) -> "BeatGrid":
        period = 60.0 / tempo
        return cls(np.arange(offset, duration + period, period), downbeat)

    @property
    def tempo(self) -> float:
        """代表のテンポ（拍の間隔の中央値から）。"""
        if len(self.times) < 2:
            return 120.0
        return float(60.0 / np.median(np.diff(self.times)))

    @property
    def tempo_range(self) -> tuple[float, float]:
        """テンポの変化の幅（拍の間隔を 8拍ずつならした最小・最大）。"""
        d = np.diff(self.times)
        if len(d) < 8:
            return self.tempo, self.tempo
        smooth = np.convolve(d, np.ones(8) / 8, mode="valid")
        return float(60.0 / smooth.max()), float(60.0 / smooth.min())

    def to_beats(self, t: float | np.ndarray) -> float | np.ndarray:
        """秒 → 通しの拍番号（小数）。格子の外は端の拍の間隔でのばす。"""
        times = self.times
        k = np.arange(len(times), dtype=float)
        t_arr = np.asarray(t, dtype=float)
        out = np.interp(t_arr, times, k)
        first, last = times[1] - times[0], times[-1] - times[-2]
        out = np.where(t_arr < times[0], (t_arr - times[0]) / first, out)
        out = np.where(t_arr > times[-1], k[-1] + (t_arr - times[-1]) / last, out)
        return float(out) if np.ndim(t) == 0 else out

    def calibrate(self, onsets: list[float], window: int = 4) -> None:
        """採譜した音の立ち上がり（拍の上に来る音）に合わせて、格子の位置を細かく直す。

        拍の検出は音量の変化から求めるので少し遅れがちで、揺れもある。
        各拍の前後 window 拍にある音が、その拍から平均でどれだけずれているかを見て、格子を動かす。
        """
        if len(onsets) < 8 or len(self.times) < 3:
            return
        b = self.to_beats(np.asarray(onsets, dtype=float))
        nearest = np.round(b)
        res = b - nearest
        on_beat = np.abs(res) < 0.2  # 裏拍の音などは使わない
        nearest, res = nearest[on_beat], res[on_beat]
        periods = np.diff(self.times)
        periods = np.concatenate([periods, periods[-1:]])
        new = self.times.copy()
        for k in range(len(self.times)):
            near = np.abs(nearest - k) <= window
            if near.sum() >= 3:
                new[k] = self.times[k] + float(np.median(res[near])) * periods[k]
        if np.all(np.diff(new) > 0):
            self.times = new

    def position(self, t: float | np.ndarray) -> float | np.ndarray:
        """秒 → 楽譜上の位置（4分音符単位）。小節の頭の拍が 4 の倍数になる。"""
        return self.to_beats(t) - self.downbeat


def track_beats(audio_path, tempo_hint: float | None = None,
                steady_tolerance: float = 0.012) -> BeatGrid:
    """拍の格子を求める。

    テンポがほぼ一定の演奏（クリックに合わせた録音など）なら等間隔の格子にし、
    揺れている演奏なら 1拍ずつ追いかけた格子を、細かいぶれだけならして使う。
    steady_tolerance: 等間隔からのずれ（秒）がこれ以下なら「テンポ一定」とみなす
    """
    y, sr = librosa.load(audio_path, sr=SR, mono=True)
    duration = len(y) / sr
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=HOP)
    tempo = float(tempo_hint) if tempo_hint else _global_tempo(onset_env)
    period = 60.0 / tempo

    _, frames = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, hop_length=HOP,
                                        bpm=tempo, tightness=50, trim=False)
    beats = librosa.frames_to_time(frames, sr=sr, hop_length=HOP)
    beats = _fix_gaps(beats, period)

    if len(beats) >= 8:
        idx = np.arange(len(beats))
        slope, intercept = np.polyfit(idx, beats, 1)
        residual = beats - (intercept + slope * idx)
        steady = float(np.std(residual)) <= steady_tolerance
    else:
        steady = True

    if steady:
        if not tempo_hint and len(beats) >= 8:
            tempo = 60.0 / slope
        phase = _beat_phase(onset_env, sr, 60.0 / tempo)
        return BeatGrid.constant(tempo, phase, duration)

    # 1拍ずつの時刻のぶれ（演奏の揺れ・検出の誤差）をならし、ゆっくりしたテンポの変化だけ残す
    window = min(len(beats) - (1 - len(beats) % 2), 9)
    if window >= 5:
        beats = savgol_filter(beats, window, 2)
    return BeatGrid(_extend(beats, duration))


def _global_tempo(onset_env: np.ndarray) -> float:
    tempo, frames = librosa.beat.beat_track(onset_envelope=onset_env, sr=SR, hop_length=HOP)
    tempo = float(np.atleast_1d(tempo)[0])
    beats = librosa.frames_to_time(frames, sr=SR, hop_length=HOP)
    if len(beats) >= 8:
        tempo = 60.0 / float(np.median(np.diff(beats)))
    if tempo <= 0:
        tempo = 120.0
    while tempo < 70:  # 速すぎ・遅すぎる推定は倍テン/ハーフテンとして直す
        tempo *= 2
    while tempo > 180:
        tempo /= 2
    return tempo


def _fix_gaps(beats: np.ndarray, period: float) -> np.ndarray:
    """拍が抜けている所を補い、近すぎる（裏拍を拾った）拍を除く。"""
    if len(beats) < 2:
        return beats
    out = [float(beats[0])]
    for b in beats[1:]:
        gap = b - out[-1]
        if gap < 0.6 * period:
            continue
        n = int(round(gap / period))
        for i in range(1, n):
            out.append(out[-1] + gap / n)
        out.append(float(b))
    return np.array(out)


def _extend(beats: np.ndarray, duration: float) -> np.ndarray:
    """曲の最初と最後まで、端の拍の間隔で拍をのばす。"""
    first = beats[1] - beats[0]
    last = beats[-1] - beats[-2]
    head = []
    t = beats[0] - first
    while t > -0.5 * first:
        head.insert(0, t)
        t -= first
    tail = []
    t = beats[-1] + last
    while t < duration + last:
        tail.append(t)
        t += last
    return np.concatenate([head, beats, tail])


def _beat_phase(onset_env: np.ndarray, sr: int, period: float) -> float:
    """等間隔の拍の格子を少しずつずらし、音の立ち上がりと一番よく重なる位置を返す。"""
    times = librosa.frames_to_time(np.arange(len(onset_env)), sr=sr, hop_length=HOP)
    best, best_score = 0.0, -1.0
    for phase in np.arange(0.0, period, 0.005):
        grid = np.arange(phase, times[-1], period)
        idx = np.searchsorted(times, grid).clip(0, len(onset_env) - 1)
        score = float(onset_env[idx].sum())
        if score > best_score:
            best, best_score = float(phase), score
    return best


def estimate_downbeat(grid: BeatGrid, kicks: list[float] | None = None,
                      snares: list[float] | None = None,
                      chord_changes: list[float] | None = None,
                      bass_onsets: list[float] | None = None) -> int:
    """どの拍が小節の頭か（0〜3）を決める。

    手がかり（すべて秒のリスト）:
      chord_changes: コードが変わる時刻。コードはふつう小節の頭で変わる（いちばん強い手がかり）
      kicks:         キック。小節の頭に来やすい
      snares:        スネア。2拍目・4拍目に来やすい（＝小節の頭には来にくい）
      bass_onsets:   ベースの弾き始め。小節の頭に来やすい
    """
    n = len(grid.times)
    if n < BEATS_PER_BAR * 2:
        return 0
    def per_beat(times: list[float] | None) -> np.ndarray:
        """拍ごとに、その拍ちょうど（±1/8拍）に音があるか。"""
        hits = np.zeros(n)
        if not times:
            return hits
        b = grid.to_beats(np.asarray(times))
        k = np.round(b).astype(int)
        ok = (np.abs(b - k) < 0.125) & (k >= 0) & (k < n)
        np.add.at(hits, k[ok], 1.0)
        return np.minimum(hits, 1.0)

    kick, snare = per_beat(kicks), per_beat(snares)
    change, bass = per_beat(chord_changes), per_beat(bass_onsets)
    if not (kick.any() or snare.any() or change.any()):
        return 0

    scores = []
    for p in range(BEATS_PER_BAR):
        down = np.arange(p, n, BEATS_PER_BAR)
        back = np.concatenate([np.arange(p + 1, n, BEATS_PER_BAR),
                               np.arange(p + 3, n, BEATS_PER_BAR)])
        s = (3.0 * change[down].mean() + 1.0 * kick[down].mean() - 1.0 * snare[down].mean()
             + 1.0 * snare[back].mean() + 0.5 * bass[down].mean())
        scores.append(s)
    return int(np.argmax(scores))
