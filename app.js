'use strict';

const $ = (id) => document.getElementById(id);
const els = {
  format: $('format'), quality: $('quality'), qualityWrap: $('qualityWrap'),
  start: $('start'), pause: $('pause'), stop: $('stop'), status: $('status'),
  previewPanel: $('previewPanel'), preview: $('preview'), audioPreview: $('audioPreview'),
  download: $('download'),
};

// 形式の候補。ブラウザが対応しているものだけを表示する
const FORMATS = {
  video: [
    { label: 'MP4 (H.264)', mime: 'video/mp4;codecs=avc1,mp4a.40.2', ext: 'mp4' },
    { label: 'MP4', mime: 'video/mp4', ext: 'mp4' },
    { label: 'WebM (VP9)', mime: 'video/webm;codecs=vp9,opus', ext: 'webm' },
    { label: 'WebM (VP8)', mime: 'video/webm;codecs=vp8,opus', ext: 'webm' },
    { label: 'WebM', mime: 'video/webm', ext: 'webm' },
  ],
  audio: [
    { label: 'M4A (AAC)', mime: 'audio/mp4;codecs=mp4a.40.2', ext: 'm4a' },
    { label: 'WebM (Opus)', mime: 'audio/webm;codecs=opus', ext: 'webm' },
    { label: 'Ogg (Opus)', mime: 'audio/ogg;codecs=opus', ext: 'ogg' },
  ],
};

let stream = null;
let recorder = null;
let chunks = [];
let timerId = null;
let elapsedMs = 0;
let lastTick = 0;
let objectUrl = null;

const mode = () => document.querySelector('input[name="mode"]:checked').value;

function fillFormats() {
  const m = mode();
  const supported = FORMATS[m].filter((f) => window.MediaRecorder && MediaRecorder.isTypeSupported(f.mime));
  // 同じ拡張子が重なったら最初のものだけ残す
  const seen = new Set();
  els.format.innerHTML = '';
  supported.filter((f) => !seen.has(f.label.split(' ')[0]) && seen.add(f.label.split(' ')[0]))
    .forEach((f) => {
      const o = document.createElement('option');
      o.value = f.mime; o.textContent = f.label; o.dataset.ext = f.ext;
      els.format.appendChild(o);
    });
  els.qualityWrap.hidden = m !== 'video';
  els.start.textContent = m === 'video' ? '● 録画開始' : '● 録音開始';
}

function setStatus(text, recording = false) {
  els.status.textContent = text;
  els.status.classList.toggle('rec', recording);
}

function fmtTime(ms) {
  const s = Math.floor(ms / 1000);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  return (h ? h + ':' : '') + String(m).padStart(2, '0') + ':' + String(sec).padStart(2, '0');
}

function tick() {
  const now = performance.now();
  if (recorder && recorder.state === 'recording') elapsedMs += now - lastTick;
  lastTick = now;
  const label = recorder && recorder.state === 'paused' ? '一時停止中' : (mode() === 'video' ? '録画中' : '録音中');
  setStatus(`${label}  ${fmtTime(elapsedMs)}`, recorder && recorder.state === 'recording');
}

async function start() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getDisplayMedia) {
    alert('このブラウザは画面の記録に対応していません。パソコン版の Chrome か Edge で開いてください。');
    return;
  }
  const m = mode();
  try {
    stream = await navigator.mediaDevices.getDisplayMedia({
      video: { frameRate: 30, width: { ideal: 1920 }, height: { ideal: 1080 } },
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
      preferCurrentTab: false,
      selfBrowserSurface: 'exclude',
      systemAudio: 'include',
      surfaceSwitching: 'include',
    });
  } catch (e) {
    setStatus('共有がキャンセルされました');
    return;
  }

  const audioTracks = stream.getAudioTracks();
  if (audioTracks.length === 0) {
    const ok = m === 'video' && confirm('音声が共有されていません。\n共有画面で「タブの音声も共有する」をオンにする必要があります。\n\n音声なしで録画を続けますか？');
    if (!ok) { stopTracks(); setStatus('音声が共有されなかったため中止しました'); return; }
  }

  // 録音のときは音声トラックだけを使う（ただし映像トラックは共有を保つため止めずに残す）
  const recStream = m === 'audio' ? new MediaStream(audioTracks) : stream;

  const mime = els.format.value;
  const opts = { mimeType: mime, audioBitsPerSecond: 192000 };
  if (m === 'video') opts.videoBitsPerSecond = Number(els.quality.value);

  try {
    recorder = new MediaRecorder(recStream, opts);
  } catch (e) {
    recorder = new MediaRecorder(recStream);
  }

  chunks = [];
  recorder.ondataavailable = (e) => { if (e.data && e.data.size > 0) chunks.push(e.data); };
  recorder.onstop = finish;

  // ユーザーがブラウザの「共有を停止」を押したときも終わらせる
  stream.getTracks().forEach((t) => t.addEventListener('ended', () => {
    if (recorder && recorder.state !== 'inactive') recorder.stop();
  }));

  recorder.start(1000);
  elapsedMs = 0; lastTick = performance.now();
  timerId = setInterval(tick, 250); tick();

  els.start.disabled = true; els.pause.disabled = false; els.stop.disabled = false;
  document.querySelectorAll('input[name="mode"], #format, #quality').forEach((el) => (el.disabled = true));
}

function togglePause() {
  if (!recorder) return;
  if (recorder.state === 'recording') { recorder.pause(); els.pause.textContent = '再開'; }
  else if (recorder.state === 'paused') { recorder.resume(); lastTick = performance.now(); els.pause.textContent = '一時停止'; }
  tick();
}

function stop() {
  if (recorder && recorder.state !== 'inactive') recorder.stop();
}

function stopTracks() {
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
}

function finish() {
  clearInterval(timerId);
  stopTracks();
  const m = mode();
  const type = recorder.mimeType || els.format.value;
  const opt = els.format.selectedOptions[0];
  const ext = opt ? opt.dataset.ext : (m === 'video' ? 'webm' : 'webm');
  const blob = new Blob(chunks, { type });
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = URL.createObjectURL(blob);

  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '_').slice(0, 15);
  els.download.href = objectUrl;
  els.download.download = `${m === 'video' ? 'recording' : 'audio'}_${stamp}.${ext}`;
  els.download.textContent = `ダウンロード（${(blob.size / 1024 / 1024).toFixed(1)} MB）`;

  els.preview.hidden = m !== 'video';
  els.audioPreview.hidden = m !== 'audio';
  (m === 'video' ? els.preview : els.audioPreview).src = objectUrl;
  els.previewPanel.hidden = false;

  setStatus(`完了  ${fmtTime(elapsedMs)}`);
  recorder = null;
  els.start.disabled = false; els.pause.disabled = true; els.stop.disabled = true;
  els.pause.textContent = '一時停止';
  document.querySelectorAll('input[name="mode"], #format, #quality').forEach((el) => (el.disabled = false));
}

document.querySelectorAll('input[name="mode"]').forEach((r) => r.addEventListener('change', fillFormats));
els.start.addEventListener('click', start);
els.pause.addEventListener('click', togglePause);
els.stop.addEventListener('click', stop);
window.addEventListener('beforeunload', (e) => {
  if (recorder && recorder.state !== 'inactive') { e.preventDefault(); e.returnValue = ''; }
});

fillFormats();
