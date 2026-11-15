import sys
from pathlib import Path

# tests/make_test_song.py をテストから import できるようにする
sys.path.insert(0, str(Path(__file__).resolve().parent))
