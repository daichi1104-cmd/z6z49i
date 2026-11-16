"""コマンドライン入口: python -m band2score song.mp3"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .models import STEM_SETTINGS
from .pipeline import Options, PipelineError, run
from .separate import DEFAULT_MODEL


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="band2score",
        description="バンド音源（mp3/wav など）を楽器ごとの楽譜（MusicXML・MIDI）に変換します。",
    )
    p.add_argument("audio", type=Path, help="入力する音声ファイル")
    p.add_argument("-o", "--out", type=Path, default=None,
                   help="出力先フォルダ（省略時: ./output/<曲名>）")
    p.add_argument("--model", default=DEFAULT_MODEL,
                   help=f"Demucs のモデル（既定: {DEFAULT_MODEL}。4パートなら htdemucs）")
    p.add_argument("--stems-dir", type=Path, default=None,
                   help="分離済みのステム（vocals.wav など）が入ったフォルダ。指定すると分離を省略")
    p.add_argument("--only", nargs="+", choices=sorted(STEM_SETTINGS), default=None,
                   help="指定したパートだけ楽譜にする（例: --only bass drums）")
    p.add_argument("--tempo", type=float, default=None, help="テンポ（BPM）を手で指定する")
    p.add_argument("--grid", type=int, choices=[4, 8, 16, 32], default=16,
                   help="リズムをそろえる細かさ（16 = 16分音符。既定: 16）")
    p.add_argument("--no-chords", action="store_true", help="コードネームを付けない")
    p.add_argument("--chord-beats", type=int, choices=[1, 2, 4], default=1,
                   help="コードを判定する細かさ（拍）。コードが細かく変わりすぎるときは 2 や 4 に（既定: 1）")
    p.add_argument("--device", default=None, help="cpu / cuda（省略時は自動）")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    log = logging.getLogger("band2score")

    audio: Path = args.audio
    if not audio.exists():
        log.error("ファイルが見つかりません: %s", audio)
        return 1
    out: Path = args.out or Path("output") / audio.stem
    options = Options(model=args.model, stems_dir=args.stems_dir, only=args.only,
                      tempo=args.tempo, grid=args.grid, chords=not args.no_chords,
                      chord_beats=args.chord_beats, device=args.device)
    try:
        result = run(audio, out, options)
    except PipelineError as e:
        log.error(str(e))
        return 1

    log.info("\n完了しました:")
    log.info("  楽譜 (MusicXML): %s", result.musicxml)
    log.info("  MIDI            : %s", result.midi)
    if result.chord_chart:
        log.info("  コード表        : %s", result.chord_chart)
    if result.pdf:
        log.info("  PDF             : %s", result.pdf)
    else:
        log.info("  PDF は MuseScore が見つからないので作っていません。"
                 "MusicXML を MuseScore で開けば表示・印刷できます。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
