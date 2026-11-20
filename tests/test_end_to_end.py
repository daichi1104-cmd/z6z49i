"""いちばん難しい条件（テンポが揺れる・弱起・タイミングの揺れ）で、分離以降を通して確かめる。"""

from pathlib import Path

from benchmark import SCENARIOS, run


def test_drift_pickup_humanize(tmp_path: Path):
    result = run("drift-pickup-humanize", SCENARIOS["drift-pickup-humanize"], tmp_path)
    assert result["chords"] == 1.0
    for part in ("bass", "lead", "kick", "snare"):
        assert result[part] >= 0.95, (part, result)
    assert result["piano"] >= 0.9, result


def test_conversion_does_not_load_scikit_learn(tmp_path: Path):
    """変換で scikit-learn を読み込まないこと。

    Windows の「スマート アプリ コントロール」が scikit-learn の部品を止める PC があり、
    librosa.effects.harmonic などを使うと（使わないのに）読み込まれてしまうため。
    """
    import os
    import subprocess
    import sys

    from make_test_song import make_song

    wav = make_song(tmp_path / "song", bars=2)
    script = (
        "import sys; from pathlib import Path; import logging; logging.disable(50)\n"
        "from band2score.pipeline import run, Options\n"
        f"run(Path({str(wav)!r}), Path({str(tmp_path / 'out')!r}),"
        f" Options(stems_dir=Path({str(tmp_path / 'song' / 'stems')!r})))\n"
        "print(sorted(m for m in sys.modules if m.split('.')[0] == 'sklearn'))\n"
    )
    root = Path(__file__).resolve().parents[1]
    res = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True,
                         env=dict(os.environ, PYTHONPATH=str(root)), timeout=600)
    assert res.returncode == 0, res.stderr[-2000:]
    assert res.stdout.strip().splitlines()[-1] == "[]"
