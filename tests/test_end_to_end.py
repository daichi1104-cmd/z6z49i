"""いちばん難しい条件（テンポが揺れる・弱起・タイミングの揺れ）で、分離以降を通して確かめる。"""

from pathlib import Path

from benchmark import SCENARIOS, run


def test_drift_pickup_humanize(tmp_path: Path):
    result = run("drift-pickup-humanize", SCENARIOS["drift-pickup-humanize"], tmp_path)
    assert result["chords"] == 1.0
    for part in ("bass", "lead", "kick", "snare"):
        assert result[part] >= 0.95, (part, result)
    assert result["piano"] >= 0.9, result
