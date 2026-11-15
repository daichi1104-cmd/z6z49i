"""合成テスト音源で band2score の精度を測る。

いくつかの「演奏の条件」（テンポが一定 / だんだん速くなる / 弱起 / タイミングの揺れ）で
テスト音源を作り、分離済みステムから楽譜を作って、正解と比べる。

  位置の正解率 = 正解の音のうち、楽譜上の正しい位置（小節・拍）に正しい音で書かれた割合
  piano       = 和音のパートの F値（取りこぼしと余分な音の両方を数える。1 に近いほど良い）
  コード正解率 = 正解のコードのうち、正しい位置に正しい名前で書かれた割合

    python tests/benchmark.py            # 全部の条件
    python tests/benchmark.py drift      # 名前に drift を含む条件だけ
"""

from __future__ import annotations

import contextlib
import io
import json
import logging
import sys
import tempfile
from pathlib import Path

from music21 import converter, harmony, note

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from band2score.cli import main as band2score_main  # noqa: E402
from make_test_song import make_song  # noqa: E402

SCENARIOS = {
    "steady-120": dict(bpm=120),
    "steady-92-pickup1": dict(bpm=92, pickup=1),
    "pickup2": dict(bpm=120, pickup=2),
    "drift-112-126": dict(bpm=112, bpm_end=126, bars=16),
    "drift-pickup-humanize": dict(bpm=126, bpm_end=114, bars=16, pickup=2, humanize_ms=12),
}
DRUM_STEP = {"F4": "kick", "C5": "snare"}


def _score_positions(xml: Path):
    score = converter.parse(xml)
    found: dict[str, set] = {"bass": set(), "lead": set(), "piano": set(), "kick": set(),
                             "snare": set()}
    chords: set = set()
    for part in score.parts:
        name = (part.partName or "").lower()
        for el in part.recurse().notes:
            if isinstance(el, harmony.ChordSymbol):
                continue
            off = float(el.getOffsetInHierarchy(score))
            if el.tie is not None and el.tie.type in ("stop", "continue"):
                continue
            if name == "bass":
                found["bass"].update((off, p.midi) for p in el.pitches)
            elif name == "vocals":
                found["lead"].update((off, p.midi) for p in el.pitches)
            elif name.startswith("piano"):
                found["piano"].update((off, p.midi) for p in el.pitches)
            elif name == "drums":
                heads = el.notes if hasattr(el, "notes") and el.notes else [el]
                for h in heads:
                    if isinstance(h, note.Unpitched):
                        kind = DRUM_STEP.get(f"{h.displayStep}{h.displayOctave}")
                        if kind:
                            found[kind].add(off)
        for cs in part.recurse().getElementsByClass(harmony.ChordSymbol):
            if not isinstance(cs, harmony.NoChord):
                chords.add((float(cs.getOffsetInHierarchy(score)), cs.figure.replace("-", "b")))
    return found, chords


def run(name: str, params: dict, work: Path) -> dict:
    d = work / name
    wav = make_song(d, **params)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        logging.disable(logging.CRITICAL)
        try:
            band2score_main([str(wav), "--stems-dir", str(d / "stems"), "-o", str(d / "out")])
        finally:
            logging.disable(logging.NOTSET)
    truth = json.loads((d / "truth.json").read_text())
    found, chords = _score_positions(d / "out" / "test_band.musicxml")
    result = {}
    for part in ("bass", "lead"):
        items = [(float(o), p) for o, p in truth[part]]
        result[part] = sum(i in found[part] for i in items) / len(items)
    for part in ("kick", "snare"):
        result[part] = sum(float(o) in found[part] for o in truth[part]) / len(truth[part])
    items = {(float(o), p) for o, p in truth["piano"]}
    hit = len(items & found["piano"])
    result["piano"] = 2 * hit / (len(items) + len(found["piano"])) if items else 0.0  # F値
    items = [(float(o), c) for o, c in truth["chords"]]
    result["chords"] = sum(i in chords for i in items) / len(items)
    return result


def main() -> None:
    selected = {k: v for k, v in SCENARIOS.items() if len(sys.argv) < 2 or sys.argv[1] in k}
    cols = ["bass", "lead", "piano", "kick", "snare", "chords"]
    print(f"{'条件':<24}" + "".join(f"{c:>8}" for c in cols))
    totals = {c: [] for c in cols}
    with tempfile.TemporaryDirectory() as tmp:
        for name, params in selected.items():
            r = run(name, params, Path(tmp))
            for c in cols:
                totals[c].append(r[c])
            print(f"{name:<24}" + "".join(f"{r[c]:>8.0%}" for c in cols), flush=True)
    print(f"{'平均':<24}" + "".join(f"{sum(v) / len(v):>8.0%}" for v in totals.values()))


if __name__ == "__main__":
    main()
