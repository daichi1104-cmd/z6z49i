"""使う部品（ライブラリ）がこの PC で読み込めるかを確かめる: python -m band2score.check

Windows 11 の「スマート アプリ コントロール」などに部品が止められていないかを、変換の前に調べる。
"""

from __future__ import annotations

import argparse
import ctypes
import importlib
import importlib.util
import os
import shutil
import sys
from pathlib import Path

# (表示名, 確かめ方) — 確かめ方は import するモジュール名か、実際に少し動かす関数
# 変換の途中で読み込まれる scipy の部品（実際の変換で読み込まれるものを調べて並べた）
SCIPY_PARTS = ["fft", "fftpack", "integrate", "interpolate", "io", "linalg", "ndimage", "optimize",
               "signal", "sparse", "spatial", "special", "stats"]


def _import_all(prefix: str, parts: list[str]) -> None:
    """部品をまとめて読み込み、読めなかったものを全部並べてエラーにする。"""
    errors = []
    for part in parts:
        try:
            importlib.import_module(f"{prefix}.{part}")
        except Exception as e:  # noqa: BLE001
            errors.append(f"{prefix}.{part}: {type(e).__name__}: {e}")
    if errors:
        raise ImportError(" / ".join(errors))


def _librosa_trial() -> None:
    """librosa で、変換と同じ種類の計算を短い音で試す（途中で読み込まれる部品も確かめられる）。"""
    import numpy as np
    import librosa

    from .chords import harmonic

    sr = 22050
    t = np.arange(sr * 2) / sr
    y = (0.3 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)
    y[:: sr // 2] += 1.0
    env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=256)
    librosa.onset.onset_detect(onset_envelope=env, sr=sr, hop_length=256)
    librosa.beat.beat_track(onset_envelope=env, sr=sr, hop_length=256)
    librosa.feature.chroma_cqt(y=harmonic(y), sr=sr)
    librosa.sequence.viterbi(np.full((3, 10), 1 / 3), librosa.sequence.transition_loop(3, 0.8))


CHECKS = [
    ("numpy（数値計算）", "numpy"),
    ("scipy（信号処理など）", lambda: _import_all("scipy", SCIPY_PARTS)),
    ("soundfile（音声ファイルの読み書き）", "soundfile"),
    ("soxr（音声の変換）", "soxr"),
    ("numba（librosa の高速化）", lambda: __import__("numba").njit(lambda x: x + 1)(1)),
    ("librosa（テンポ・コードの解析）", "librosa"),
    ("librosa の計算（試し）", _librosa_trial),
    ("torch（AI の計算）", "torch"),
    ("demucs（楽器ごとに音を分ける AI）", "demucs.api"),
    ("onnxruntime（採譜 AI の計算）", "onnxruntime"),
    ("basic-pitch（音符にする AI）", "basic_pitch.inference"),
    ("music21（楽譜づくり）", "music21"),
    ("pretty_midi（MIDI づくり）", "pretty_midi"),
    ("fastapi / uvicorn（スマホ用の画面）", lambda: (__import__("fastapi"), __import__("uvicorn"))),
]

BLOCK_HINTS = ("アプリケーション制御ポリシー", "Application Control", "application control", "4551")
VC_REDIST_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
# 部品の中の DLL（Windows）。読み込めないとき、本当の理由（Windows のエラー番号）を調べるのに使う
DLLS = {"numba（librosa の高速化）": ("llvmlite", "binding/llvmlite.dll")}


def vc_runtime_missing() -> bool:
    """Windows に Visual C++ ランタイム（msvcp140.dll など）が入っていないか。"""
    if os.name != "nt":
        return False
    system32 = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
    return not all((system32 / f).exists() for f in ("msvcp140.dll", "vcruntime140.dll",
                                                       "vcruntime140_1.dll"))


def dll_error(package: str, relative: str) -> tuple[int | None, str]:
    """DLL を直接読み込んでみて、Windows のエラー番号と説明を返す（読めれば (None, "")）。"""
    if os.name != "nt":
        return None, ""
    spec = importlib.util.find_spec(package)
    if not spec or not spec.submodule_search_locations:
        return None, "部品が見つかりません"
    path = Path(list(spec.submodule_search_locations)[0]) / relative
    try:
        ctypes.WinDLL(str(path))
    except OSError as e:
        return getattr(e, "winerror", None), str(e)
    return None, ""


def run(quiet: bool = False) -> int:
    import logging
    import warnings

    logging.disable(logging.WARNING)  # basic-pitch などが出す関係のない警告を隠す
    warnings.filterwarnings("ignore")
    blocked, failed, runtime = [], [], []
    numba_broken = False
    for name, how in CHECKS:
        try:
            how() if callable(how) else importlib.import_module(how)
        except Exception as e:  # noqa: BLE001 — どんな失敗でも一覧にする
            msg = f"{type(e).__name__}: {e}"
            if numba_broken and "numba" in msg:  # 巻き添え（原因は numba の方で案内する）
                print(f"  NG  {name}\n        （numba を読み込めないため、こちらも動きません）")
                continue
            if name in DLLS:
                # 部品のエラー文では理由が隠れるので、DLL を直接読み込んで本当の理由を調べる
                code, detail = dll_error(*DLLS[name])
                if code is not None:
                    msg += f"\n        Windows のエラー {code}: {detail}"
                if code == 4551:
                    msg += "\n        → スマート アプリ コントロールに止められています"
                elif code == 126 or vc_runtime_missing():
                    runtime.append(name)
                    msg += "\n        → Visual C++ ランタイムが足りないようです"
                numba_broken = numba_broken or name.startswith("numba")
            (blocked if any(h in msg for h in BLOCK_HINTS) else failed).append((name, msg))
            print(f"  NG  {name}\n        {msg}")
        else:
            if not quiet:
                print(f"  OK  {name}")
    from . import numba_fallback

    if numba_fallback.ACTIVE:
        print("  ※ numba はこの PC では読み込めないため、代わりの部品で動いています"
              "（結果は同じで、少し遅くなるだけです）")
        if not quiet:
            print(f"     理由: {numba_fallback.REASON[:200]}")
    if not shutil.which("ffmpeg"):
        failed.append(("ffmpeg", "見つかりません"))
        print("  NG  ffmpeg（スマホの録音 m4a などを読む）: 見つかりません")
    elif not quiet:
        print("  OK  ffmpeg（スマホの録音 m4a などを読む）")

    if blocked:
        print("\nWindows の「スマート アプリ コントロール」（アプリケーション制御ポリシー）に"
              "止められている部品があります:")
        for name, _ in blocked:
            print(f"  - {name}")
        print("この画面の写真（スクリーンショット）を送ってください。対処を案内します。")
    if runtime:
        print("\nWindows に「Visual C++ ランタイム」（Microsoft の基本部品）が足りないようです。")
        print(f"次のリンクから vc_redist.x64.exe をダウンロードして入れてください:\n  {VC_REDIST_URL}")
        print("入れたあと、もう一度 start.bat を実行してください。")
    elif failed:
        print("\n読み込めない部品があります。setup.bat をもう一度実行してみてください。"
              "直らなければ、この画面の写真を送ってください。")
    if not blocked and not failed and not quiet:
        print("\nすべての部品を読み込めました。")
    return 1 if blocked or failed else 0


def main() -> None:
    p = argparse.ArgumentParser(prog="band2score.check", description=__doc__.split("\n")[0])
    p.add_argument("--quiet", action="store_true", help="問題があるときだけ表示する")
    sys.exit(run(p.parse_args().quiet))


if __name__ == "__main__":
    main()
