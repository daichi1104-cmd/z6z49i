"""Web アプリ（スマホ用）の API のテスト。Demucs の代わりに分離済みステムを使う。"""

import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from band2score.web.server import create_app
from make_test_song import make_song


@pytest.fixture(scope="module")
def song(tmp_path_factory):
    d = tmp_path_factory.mktemp("song")
    make_song(d, bars=4)
    return d


def _client(tmp_path: Path, song: Path, **kw) -> TestClient:
    return TestClient(create_app(data_dir=tmp_path / "data", test_stems=song / "stems", **kw))


def _wait(client: TestClient, job_id: str, timeout: float = 120) -> dict:
    end = time.time() + timeout
    while time.time() < end:
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in ("done", "error"):
            return job
        time.sleep(0.3)
    raise AssertionError("timeout")


def test_upload_convert_view_and_download(tmp_path: Path, song: Path):
    client = _client(tmp_path, song)
    assert client.get("/").status_code == 200
    assert client.get("/manifest.webmanifest").status_code == 200
    config = client.get("/api/config").json()
    assert not config["password_required"] and len(config["parts"]) == 6

    with open(song / "test_band.wav", "rb") as f:
        res = client.post("/api/jobs", files={"audio": ("練習.wav", f, "audio/wav")},
                          data={"chords": "true", "title": "練習"})
    assert res.status_code == 200, res.text
    job = _wait(client, res.json()["id"])
    assert job["status"] == "done", job
    r = job["result"]
    assert r["tempo"] == 120 and r["chords"][:4] == ["C", "Am", "F", "G"]
    assert set(r["files"]) >= {"musicxml", "midi", "chords"}

    view = client.get(f"/api/jobs/{job['id']}/view.musicxml")
    assert view.status_code == 200 and "score-partwise" in view.text and "Vocals" in view.text
    bass = client.get(f"/api/jobs/{job['id']}/view.musicxml?parts=Bass")
    assert bass.status_code == 200 and "Vocals" not in bass.text
    assert "<harmony" in bass.text  # ベースだけでもコードネームが付く
    js = client.get("/static/vendor/verovio/verovio.mjs", headers={"Accept-Encoding": "gzip"})
    assert js.status_code == 200 and "javascript" in js.headers["content-type"]
    assert js.headers.get("content-encoding") == "gzip"

    xml = client.get(f"/api/jobs/{job['id']}/files/musicxml")
    assert xml.status_code == 200 and b"score-partwise" in xml.content
    chart = client.get(f"/api/jobs/{job['id']}/files/chords").text
    assert "| C" in chart


def test_rejects_non_audio_and_too_large(tmp_path: Path, song: Path):
    client = _client(tmp_path, song, max_mb=0.001)
    res = client.post("/api/jobs", files={"audio": ("memo.txt", b"hello", "text/plain")})
    assert res.status_code == 400
    res = client.post("/api/jobs", files={"audio": ("a.wav", b"0" * 5000, "audio/wav")})
    assert res.status_code == 413


def test_password(tmp_path: Path, song: Path):
    client = _client(tmp_path, song, password="secret")
    assert client.get("/api/config").json()["password_required"]
    assert client.get("/api/jobs/abc").status_code == 401
    assert client.post("/api/login", json={"password": "wrong"}).status_code == 403
    assert client.post("/api/login", json={"password": "secret"}).status_code == 200
    assert client.get("/api/jobs/abc").status_code == 404  # ログイン後は通る（ジョブが無いだけ）


def test_locked_when_public_without_password(tmp_path: Path, song: Path):
    client = _client(tmp_path, song, require_password=True)
    assert client.get("/api/config").json()["locked"]
    assert client.get("/api/jobs/abc").status_code == 503
    res = client.post("/api/jobs", files={"audio": ("a.wav", b"0", "audio/wav")})
    assert res.status_code == 503
    ok = _client(tmp_path / "b", song, require_password=True, password="pw")
    assert not ok.get("/api/config").json()["locked"]
