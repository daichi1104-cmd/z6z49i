"""スマホのブラウザから使う Web アプリ（FastAPI）。

重い処理（音源分離・採譜）はこのサーバー（PC やクラウド）で行い、スマホは
音声ファイルを送って、できた楽譜を見る・保存するだけにする。

環境変数:
  BAND2SCORE_DATA      作業データを置くフォルダ（既定: ./web_data）
  BAND2SCORE_PASSWORD  設定すると、使う前にパスワードを求める（ネットに公開するときは必ず設定）
  BAND2SCORE_MAX_MB    アップロードできるファイルの大きさの上限（MB、既定: 100）
  BAND2SCORE_KEEP_HOURS 結果を残しておく時間（既定: 24）
  BAND2SCORE_TEST_STEMS 開発用。分離済みステムのフォルダを指定すると Demucs を使わない
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import queue
import shutil
import threading
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from ..models import PART_ORDER, STEM_SETTINGS
from ..pipeline import TOTAL_STEPS, Options, PipelineError, run

log = logging.getLogger("band2score.web")
STATIC = Path(__file__).parent / "static"
AUDIO_TYPES = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg", ".opus", ".webm", ".aiff",
               ".aif", ".mp4", ".mov", ".caf", ".wma"}
COOKIE = "band2score_auth"


@dataclass
class Job:
    id: str
    title: str
    status: str = "queued"  # queued / running / done / error
    step: int = 0
    message: str = "順番待ちです"
    created: float = field(default_factory=time.time)
    started: float | None = None
    finished: float | None = None
    error: str | None = None
    result: dict | None = None


class JobManager:
    """ジョブを 1つずつ順番に処理する（重い処理を同時に走らせない）。"""

    def __init__(self, data_dir: Path, keep_hours: float = 24.0, test_stems: Path | None = None):
        self.data_dir = data_dir
        self.keep_seconds = keep_hours * 3600
        self.test_stems = test_stems
        self.jobs: dict[str, Job] = {}
        self.order: list[str] = []
        self.queue: queue.Queue[tuple[str, Path, Options]] = queue.Queue()
        self.lock = threading.Lock()
        data_dir.mkdir(parents=True, exist_ok=True)
        self._load_finished()
        threading.Thread(target=self._worker, daemon=True).start()

    def _load_finished(self) -> None:
        """サーバーを再起動しても、できあがった結果は見られるようにする。"""
        for meta in sorted(self.data_dir.glob("*/job.json")):
            try:
                job = Job(**json.loads(meta.read_text(encoding="utf-8")))
            except Exception:
                continue
            if job.status in ("queued", "running"):
                job.status, job.error = "error", "サーバーが再起動したため中断しました。もう一度お試しください。"
            self.jobs[job.id] = job

    def _save(self, job: Job) -> None:
        path = self.data_dir / job.id / "job.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(asdict(job), ensure_ascii=False), encoding="utf-8")

    def submit(self, audio: Path, title: str, options: Options) -> Job:
        self.cleanup()
        job = Job(id=audio.parent.parent.name, title=title)
        if self.test_stems:
            options.stems_dir = self.test_stems
        with self.lock:
            self.jobs[job.id] = job
            self.order.append(job.id)
        self._save(job)
        self.queue.put((job.id, audio, options))
        return job

    def position(self, job_id: str) -> int:
        """順番待ちで、自分の前に何件あるか。"""
        with self.lock:
            waiting = [j for j in self.order if self.jobs.get(j) and self.jobs[j].status in ("queued", "running")]
        return waiting.index(job_id) if job_id in waiting else 0

    def _worker(self) -> None:
        while True:
            job_id, audio, options = self.queue.get()
            job = self.jobs.get(job_id)
            if job is None:
                continue
            job.status, job.started, job.step = "running", time.time(), 1
            job.message = "準備しています"
            self._save(job)

            def progress(step: int, message: str, job=job) -> None:
                job.step, job.message = step, message
                self._save(job)

            out = self.data_dir / job.id / "out"
            try:
                result = run(audio, out, options, progress)
                job.result = {
                    "files": {k: v.name for k, v in {
                        "musicxml": result.musicxml, "midi": result.midi,
                        "chords": result.chord_chart, "pdf": result.pdf}.items() if v},
                    "tempo": round(result.tempo),
                    "tempo_range": [round(x) for x in result.tempo_range],
                    "key": result.key,
                    "parts": result.parts,
                    "chords": result.chords,
                }
                job.status, job.message = "done", "できあがりました"
            except PipelineError as e:
                job.status, job.error = "error", str(e)
            except Exception as e:  # 想定外の失敗も、利用者には分かる言葉で返す
                log.exception("job %s failed", job.id)
                job.status = "error"
                job.error = f"変換中にエラーが起きました（{type(e).__name__}）。別のファイルでお試しください。"
            finally:
                job.finished = time.time()
                self._save(job)
                shutil.rmtree(self.data_dir / job.id / "upload", ignore_errors=True)
                with self.lock:
                    if job.id in self.order:
                        self.order.remove(job.id)

    def cleanup(self) -> None:
        """古い結果を消す。"""
        limit = time.time() - self.keep_seconds
        for job_id, job in list(self.jobs.items()):
            if job.status in ("done", "error") and (job.finished or job.created) < limit:
                shutil.rmtree(self.data_dir / job_id, ignore_errors=True)
                self.jobs.pop(job_id, None)

    def file(self, job_id: str, kind: str) -> Path:
        job = self.jobs.get(job_id)
        if not job or job.status != "done" or not job.result:
            raise HTTPException(404, "まだできあがっていません")
        name = job.result["files"].get(kind)
        if not name:
            raise HTTPException(404, "このファイルはありません")
        return self.data_dir / job_id / "out" / name


def create_app(data_dir: Path | None = None, password: str | None = None,
               max_mb: float | None = None, keep_hours: float | None = None,
               test_stems: Path | None = None) -> FastAPI:
    data_dir = data_dir or Path(os.environ.get("BAND2SCORE_DATA", "web_data"))
    password = password if password is not None else os.environ.get("BAND2SCORE_PASSWORD") or None
    max_mb = max_mb or float(os.environ.get("BAND2SCORE_MAX_MB", "100"))
    keep_hours = keep_hours or float(os.environ.get("BAND2SCORE_KEEP_HOURS", "24"))
    if test_stems is None and os.environ.get("BAND2SCORE_TEST_STEMS"):
        test_stems = Path(os.environ["BAND2SCORE_TEST_STEMS"])

    init_renderer()
    manager = JobManager(data_dir, keep_hours, test_stems)
    token = hmac.new(b"band2score", (password or "").encode(), hashlib.sha256).hexdigest()
    app = FastAPI(title="band2score", docs_url=None, redoc_url=None)
    app.state.manager = manager

    def authed(request: Request) -> bool:
        return not password or hmac.compare_digest(request.cookies.get(COOKIE, ""), token)

    @app.middleware("http")
    async def require_password(request: Request, call_next):
        path = request.url.path
        open_paths = ("/api/config", "/api/login")
        if path.startswith("/api/") and path not in open_paths and not authed(request):
            return JSONResponse({"detail": "パスワードが必要です"}, status_code=401)
        return await call_next(request)

    @app.get("/", response_class=HTMLResponse)
    def index():
        return FileResponse(STATIC / "index.html", headers={"Cache-Control": "no-cache"})

    @app.get("/sw.js")
    def service_worker():
        return FileResponse(STATIC / "sw.js", media_type="text/javascript",
                            headers={"Cache-Control": "no-cache"})

    @app.get("/manifest.webmanifest")
    def manifest():
        return FileResponse(STATIC / "manifest.webmanifest", media_type="application/manifest+json")

    app.mount("/static", StaticFiles(directory=STATIC), name="static")

    @app.get("/api/config")
    def config(request: Request):
        return {
            "password_required": bool(password),
            "authed": authed(request),
            "max_mb": max_mb,
            "parts": [{"id": p, "name": STEM_SETTINGS[p].name} for p in PART_ORDER],
        }

    @app.post("/api/login")
    async def login(request: Request):
        body = await request.json()
        if not password or hmac.compare_digest(str(body.get("password", "")), password):
            resp = JSONResponse({"ok": True})
            resp.set_cookie(COOKIE, token, max_age=60 * 60 * 24 * 90, httponly=True, samesite="lax")
            return resp
        return JSONResponse({"detail": "パスワードが違います"}, status_code=403)

    @app.post("/api/jobs")
    async def create_job(audio: UploadFile = File(...), chords: bool = Form(True),
                         parts: str = Form(""), tempo: str = Form(""), grid: int = Form(16),
                         title: str = Form("")):
        filename = Path(audio.filename or "audio").name
        suffix = Path(filename).suffix.lower()
        if suffix not in AUDIO_TYPES:
            raise HTTPException(400, "音声ファイル（mp3・m4a・wav など）を選んでください")
        job_id = uuid.uuid4().hex[:12]
        upload_dir = data_dir / job_id / "upload"
        upload_dir.mkdir(parents=True, exist_ok=True)
        dest = upload_dir / f"input{suffix}"
        size = 0
        with dest.open("wb") as f:
            while chunk := await audio.read(1024 * 1024):
                size += len(chunk)
                if size > max_mb * 1024 * 1024:
                    f.close()
                    shutil.rmtree(data_dir / job_id, ignore_errors=True)
                    raise HTTPException(413, f"ファイルが大きすぎます（{max_mb:.0f}MB まで）")
                f.write(chunk)
        only = [p for p in parts.split(",") if p in STEM_SETTINGS] or None
        try:
            tempo_value = float(tempo) if tempo.strip() else None
        except ValueError:
            tempo_value = None
        if tempo_value is not None and not 30 <= tempo_value <= 300:
            tempo_value = None
        name = title.strip() or Path(filename).stem
        options = Options(only=only, tempo=tempo_value, grid=grid if grid in (8, 16) else 16,
                          chords=chords, title=name)
        job = manager.submit(dest, name, options)
        return {"id": job.id}

    @app.get("/api/jobs/{job_id}")
    def job_status(job_id: str):
        job = manager.jobs.get(job_id)
        if not job:
            raise HTTPException(404, "見つかりません（時間がたって消えたかもしれません）")
        data = asdict(job)
        data["total_steps"] = TOTAL_STEPS
        data["position"] = manager.position(job_id) if job.status == "queued" else 0
        return data

    @app.get("/api/jobs/{job_id}/files/{kind}")
    def download(job_id: str, kind: str):
        path = manager.file(job_id, kind)
        media = {"musicxml": "application/vnd.recordare.musicxml+xml", "midi": "audio/midi",
                 "chords": "text/plain; charset=utf-8", "pdf": "application/pdf"}[kind]
        return FileResponse(path, media_type=media, filename=path.name)

    @app.get("/api/jobs/{job_id}/score.svg")
    def score_svg(job_id: str, page: int = 1, width: int = 800, zoom: int = 100,
                  parts: str = ""):
        """楽譜を画面の幅に合わせて SVG で返す（parts で表示するパートを選べる）。"""
        xml = manager.file(job_id, "musicxml")
        svg, pages = render_svg(xml, page, width, zoom, parts)
        return Response(svg, media_type="image/svg+xml",
                        headers={"X-Pages": str(pages), "Cache-Control": "no-store",
                                 "Access-Control-Expose-Headers": "X-Pages"})

    return app


_render_lock = threading.Lock()
_toolkit = None


def init_renderer() -> None:
    """楽譜描画（verovio）を用意する。必ずメインスレッドで呼ぶこと。

    verovio はメインスレッド以外で作ったツールキットだとフォントを読み込めないため、
    起動時に 1つ作って使い回す（使うときはロックして 1つずつ）。
    """
    global _toolkit
    if _toolkit is None:
        import verovio

        _toolkit = verovio.toolkit()


def render_svg(xml: Path, page: int, width: int, zoom: int, parts: str) -> tuple[str, int]:
    init_renderer()
    source = _part_subset(xml, parts) if parts else xml.read_text(encoding="utf-8")
    width = max(320, min(width, 2400))
    zoom = max(30, min(zoom, 200))
    with _render_lock:  # verovio のツールキットは同時に使わない
        tk = _toolkit
        scale = zoom * 0.32  # zoom 100 でスマホの幅に 2〜3小節入る大きさ
        tk.setOptions({
            "pageWidth": int(width * 100 / scale), "pageHeight": int(width * 100 / scale * 1.4),
            "scale": int(scale), "adjustPageHeight": True, "breaks": "auto",
            "footer": "none", "header": "auto", "svgViewBox": True, "svgHtml5": True,
        })
        if not tk.loadData(source):
            raise HTTPException(500, "楽譜を表示できませんでした")
        pages = tk.getPageCount()
        page = max(1, min(page, pages))
        return tk.renderToSVG(page), pages


def _part_subset(xml: Path, parts: str) -> str:
    """選んだパートだけの MusicXML を作る（キャッシュする）。"""
    wanted = [p for p in parts.split(",") if p]
    cache = xml.with_name(f".view_{'_'.join(sorted(wanted))}.musicxml")
    if cache.exists():
        return cache.read_text(encoding="utf-8")
    from music21 import converter, layout

    from music21 import harmony

    score = converter.parse(xml)
    names = {p.lower() for p in wanted}
    top = score.parts[0] if score.parts else None
    removed = [p for p in score.parts if (p.partName or "").lower() not in names]
    kept = [p for p in score.parts if p not in removed]
    if top is not None and top in removed and kept and kept[0].partName != "Drums":
        # コードネームは一番上のパートに付いているので、表示するパートに移す
        target = {m.number: m for m in kept[0].getElementsByClass("Measure")}
        for m in top.getElementsByClass("Measure"):
            for cs in m.getElementsByClass(harmony.ChordSymbol):
                if m.number in target:
                    target[m.number].insert(cs.offset, cs)
    for part in removed:
        score.remove(part)
    for group in list(score.getElementsByClass(layout.StaffGroup)):
        if not all(p in score.parts for p in group.getSpannedElements()):
            score.remove(group)
    score.write("musicxml", fp=str(cache))
    return cache.read_text(encoding="utf-8")
