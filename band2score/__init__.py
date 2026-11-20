"""band2score: バンド音源（音声ファイル）を楽譜（MusicXML / MIDI）に変換するツール。"""

__version__ = "0.1.0"

# numba が Windows の「スマート アプリ コントロール」などで読み込めない PC では、
# librosa より先に、同じ使い方ができる代わりの部品（少し遅い）に切り替えておく
from . import numba_fallback as _numba_fallback

_numba_fallback.ensure()
