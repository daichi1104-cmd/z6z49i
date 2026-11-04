"""コマンドライン入口: python -m band2score song.mp3"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from . import score as score_mod
from .models import STEM_SETTINGS, Transcription
from .separate import DEFAULT_MODEL, is_silent, separate
from .transcribe import estimate_tempo, transcribe_drums, transcribe_pitched


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
    out.mkdir(parents=True, exist_ok=True)

    # 1. 音源分離
    if args.stems_dir:
        stems = {p.stem: p for p in sorted(args.stems_dir.glob("*.wav"))}
        log.info("[1/4] 分離済みステムを使います: %s", ", ".join(stems))
    else:
        log.info("[1/4] 楽器ごとに音を分けています（Demucs %s）…", args.model)
        stems = separate(audio, out / "stems", model=args.model, device=args.device)

    # 2. テンポ推定
    est_tempo, beat_offset = estimate_tempo(audio)
    tempo = args.tempo or est_tempo
    log.info("[2/4] テンポ: %.1f BPM（最初の拍 %.2f 秒）", tempo, beat_offset)

    # 3. 採譜
    tr = Transcription(tempo=tempo, beat_offset=beat_offset)
    for name, path in stems.items():
        if name not in STEM_SETTINGS or (args.only and name not in args.only):
            continue
        if is_silent(path):
            log.info("[3/4] %-7s ほぼ無音なので省略", name)
            continue
        if name == "drums":
            notes = transcribe_drums(path)
        else:
            notes = transcribe_pitched(path, STEM_SETTINGS[name])
        log.info("[3/4] %-7s %d 音", name, len(notes))
        if notes:
            tr.parts[name] = notes
    if not tr.parts:
        log.error("音符が 1つも見つかりませんでした。")
        return 1

    # 4. 楽譜を書き出す
    log.info("[4/4] 楽譜を作っています…")
    midi = score_mod.write_midi(tr, out / f"{audio.stem}.mid")
    sc = score_mod.build_score(tr, title=audio.stem, grid=4 / args.grid)
    xml = score_mod.write_musicxml(sc, out / f"{audio.stem}.musicxml")
    pdf = score_mod.write_pdf(xml, out / f"{audio.stem}.pdf")

    log.info("\n完了しました:")
    log.info("  楽譜 (MusicXML): %s", xml)
    log.info("  MIDI            : %s", midi)
    if pdf:
        log.info("  PDF             : %s", pdf)
    else:
        log.info("  PDF は MuseScore が見つからないので作っていません。"
                 "MusicXML を MuseScore で開けば表示・印刷できます。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
