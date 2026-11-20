"""使う部品（ライブラリ）がこの PC で読み込めるかを確かめる: python -m band2score.check

Windows 11 の「スマート アプリ コントロール」などに部品が止められていないかを、変換の前に調べる。
"""

from __future__ import annotations

import argparse
import importlib
import shutil
import sys

# (表示名, 確かめ方) — 確かめ方は import するモジュール名か、実際に少し動かす関数
CHECKS = [
    ("numpy（数値計算）", "numpy"),
    ("scipy（信号処理）", "scipy.signal"),
    ("soundfile（音声ファイルの読み書き）", "soundfile"),
    ("numba（librosa の高速化）", lambda: __import__("numba").njit(lambda x: x + 1)(1)),
    ("librosa（テンポ・コードの解析）", "librosa"),
    ("torch（AI の計算）", "torch"),
    ("demucs（楽器ごとに音を分ける AI）", "demucs.api"),
    ("onnxruntime（採譜 AI の計算）", "onnxruntime"),
    ("basic-pitch（音符にする AI）", "basic_pitch.inference"),
    ("music21（楽譜づくり）", "music21"),
    ("pretty_midi（MIDI づくり）", "pretty_midi"),
    ("fastapi / uvicorn（スマホ用の画面）", lambda: (__import__("fastapi"), __import__("uvicorn"))),
]

BLOCK_HINTS = ("アプリケーション制御ポリシー", "Application Control", "application control", "4551")


def run(quiet: bool = False) -> int:
    import logging
    import warnings

    logging.disable(logging.WARNING)  # basic-pitch などが出す関係のない警告を隠す
    warnings.filterwarnings("ignore")
    blocked, failed = [], []
    for name, how in CHECKS:
        try:
            how() if callable(how) else importlib.import_module(how)
        except Exception as e:  # noqa: BLE001 — どんな失敗でも一覧にする
            msg = f"{type(e).__name__}: {e}"
            (blocked if any(h in msg for h in BLOCK_HINTS) else failed).append((name, msg))
            print(f"  NG  {name}\n        {msg}")
        else:
            if not quiet:
                print(f"  OK  {name}")
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
    if failed:
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
