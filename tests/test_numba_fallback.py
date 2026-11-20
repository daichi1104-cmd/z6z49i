"""numba の代わりの部品（Windows のスマート アプリ コントロールで numba が止められる PC 用）のテスト。"""

import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

from band2score import numba_fallback as f

ROOT = Path(__file__).resolve().parents[1]

# 本物の numba と代わりの部品で、librosa の計算結果が同じになるかを比べるスクリプト
SCRIPT = r"""
import json, sys
import band2score
from band2score import numba_fallback
import numpy as np, librosa
sr = 22050
t = np.arange(sr * 6) / sr
y = (0.4 * np.sin(2 * np.pi * 220 * t) + 0.3 * np.sin(2 * np.pi * 330 * t)).astype(np.float32)
y[:: sr // 2] += 1.0  # 120 BPM のクリック
env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=256)
probs = np.random.default_rng(0).dirichlet(np.ones(6), 120).T
out = {
    "active": numba_fallback.ACTIVE,
    "onsets": librosa.onset.onset_detect(onset_envelope=env, sr=sr, hop_length=256).tolist(),
    "beats": librosa.beat.beat_track(onset_envelope=env, sr=sr, hop_length=256)[1].tolist(),
    "localmax": np.flatnonzero(librosa.util.localmax(env)).tolist(),
    "chroma": librosa.feature.chroma_cqt(y=y, sr=sr).round(5).tolist(),
    "viterbi": librosa.sequence.viterbi(probs, librosa.sequence.transition_loop(6, 0.8)).tolist(),
    "zc": int(librosa.zero_crossings(y[:4000]).sum()),
}
json.dump(out, sys.stdout)
"""


def _run(fallback: bool) -> dict:
    env = dict(os.environ, PYTHONPATH=str(ROOT))
    env.pop("BAND2SCORE_NUMBA_FALLBACK", None)
    if fallback:
        env["BAND2SCORE_NUMBA_FALLBACK"] = "1"
    res = subprocess.run([sys.executable, "-c", SCRIPT], capture_output=True, text=True, env=env,
                         timeout=300)
    assert res.returncode == 0, res.stderr[-2000:]
    return json.loads(res.stdout)


def test_librosa_results_match_real_numba():
    real, fallback = _run(False), _run(True)
    assert fallback["active"]
    if real["active"]:
        pytest.skip("この環境では本物の numba が使えないので比べられない")
    for key in ("onsets", "beats", "localmax", "viterbi", "zc"):
        assert real[key] == fallback[key], key
    assert np.allclose(real["chroma"], fallback["chroma"], atol=1e-4)


def test_guvectorize_scalar_and_multiple_outputs():
    @f.guvectorize(["void(float64[:], float64, float64[:], int64[:])"], "(n),()->(n),()")
    def scale_and_argmax(x, k, y, best):
        best[0] = 0
        for i in range(len(x)):
            y[i] = x[i] * k
            if x[i] > x[best[0]]:
                best[0] = i

    x = np.array([[1.0, 5.0, 2.0], [7.0, 0.0, 1.0]])
    y, best = scale_and_argmax(x, 2.0)
    assert y.tolist() == [[2.0, 10.0, 4.0], [14.0, 0.0, 2.0]]
    assert best.tolist() == [1, 0] and best.dtype == np.int64

    out = np.zeros(3, dtype=bool)  # 出力を外から渡す使い方（librosa.util.localmax の書き方）

    @f.guvectorize(["void(float64[:], bool_[:])"], "(n)->(n)")
    def positive(x, y):
        for i in range(len(x)):
            y[i] = x[i] > 0

    positive(np.array([-1.0, 2.0, 3.0]), out)
    assert out.tolist() == [False, True, True]


def test_generic_stencil_widens_dtype_like_numba():
    @f.stencil
    def half_step(x):
        if x[1] == x[-1]:
            return 0
        return (x[1] - x[-1]) / 4

    assert half_step(np.array([0.0, 1.0, 1.0, 3.0])).tolist() == [0.0, 0.25, 0.5, 0.0]


def test_range_with_floats_truncates_like_numba():
    # librosa 0.11 の拍の検出は range に小数を渡す（numba は 0 の方向に切り捨てる）
    assert list(f._numba_range(10.6, 3.2, -1)) == [10, 9, 8, 7, 6, 5, 4]
    assert list(f._numba_range(-2.5, -6.7, -1)) == [-2, -3, -4, -5]
    assert list(f._numba_range(np.float64(7.0), np.float64(1.25), -2)) == [7, 5, 3]
    assert list(f._numba_range(4)) == [0, 1, 2, 3]
