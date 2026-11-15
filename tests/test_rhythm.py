"""拍の格子・小節の頭の推定のテスト。"""

from pathlib import Path

import numpy as np

from band2score.rhythm import BeatGrid, estimate_downbeat, track_beats
from make_test_song import make_song


def test_beat_grid_maps_seconds_along_varying_beats():
    grid = BeatGrid(np.array([0.0, 0.5, 1.0, 1.6, 2.2]), downbeat=1)
    assert grid.to_beats(1.3) == 2.5
    assert grid.to_beats(-0.25) == -0.5  # 格子の外は端の間隔でのばす
    assert grid.to_beats(2.5) == 4.5
    assert grid.position(0.5) == 0.0  # 小節の頭の拍が位置 0


def test_downbeat_from_chord_changes_and_drums():
    grid = BeatGrid.constant(120, 0.0, 20)
    # 小節の頭が 3拍目（番号 2）から: キックとコードの変わり目はそこ、スネアはその 1・3拍後
    downs = [0.5 * k for k in range(2, 40, 4)]
    snares = [0.5 * k for k in range(3, 40, 2) if (k - 2) % 4 in (1, 3)]
    assert estimate_downbeat(grid, kicks=downs, snares=snares, chord_changes=downs) == 2
    assert estimate_downbeat(grid) == 0  # 手がかりが無ければ最初の拍


def test_track_beats_follows_tempo_drift(tmp_path: Path):
    wav = make_song(tmp_path, bars=16, bpm=112, bpm_end=126)
    grid = track_beats(wav)
    low, high = grid.tempo_range
    assert low < 116 and high > 122
    # 実際の拍（ベースの音の位置）が格子のほぼ整数の位置に来る
    import pretty_midi
    bass = [i for i in pretty_midi.PrettyMIDI(str(tmp_path / "test_band_truth.mid")).instruments
            if i.name == "bass"][0]
    b = grid.to_beats(np.array([n.start for n in bass.notes]))
    assert np.max(np.abs(b - np.round(b))) < 0.15
