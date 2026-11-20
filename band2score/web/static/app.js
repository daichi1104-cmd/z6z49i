"use strict";
// band2score スマホ用画面。画面の切り替えは URL の # で行う（#/job/<id>）。

const $ = (id) => document.getElementById(id);
const views = ["locked", "login", "home", "progress", "result"];
const state = { config: null, file: null, job: null, poll: null, zoom: 100, parts: null };

const store = {
  get(key, fallback) {
    try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* 保存できなくても動く */ }
  },
};

function show(name) {
  for (const v of views) $(`view-${v}`).hidden = v !== name;
  window.scrollTo(0, 0);
}

async function api(path, opts = {}) {
  const res = await fetch(path, { credentials: "same-origin", ...opts });
  if (res.status === 401) { show("login"); throw new Error("login"); }
  if (!res.ok) {
    let detail = `エラー (${res.status})`;
    try { detail = (await res.json()).detail || detail; } catch { /* JSON でない */ }
    throw new Error(detail);
  }
  return res;
}

// ---------- 起動 ----------
async function boot() {
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
  state.config = await (await fetch("/api/config")).json();
  buildPartOptions();
  if (state.config.locked) { show("locked"); return; }
  if (state.config.password_required && !state.config.authed) { show("login"); return; }
  route();
}

function route() {
  clearInterval(state.poll);
  const m = location.hash.match(/^#\/job\/([0-9a-f]+)/);
  if (m) { openJob(m[1]); return; }
  renderHistory();
  show("home");
}
window.addEventListener("hashchange", route);
$("home-link").addEventListener("click", () => { location.hash = "#/"; });
$("again").addEventListener("click", () => { location.hash = "#/"; });

// ---------- パスワード ----------
$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("login-error").hidden = true;
  const res = await fetch("/api/login", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password: $("login-password").value }),
  });
  if (res.ok) { state.config.authed = true; route(); }
  else { $("login-error").textContent = "パスワードが違います"; $("login-error").hidden = false; }
});

// ---------- 最初の画面 ----------
function buildPartOptions() {
  const box = $("opt-parts");
  box.innerHTML = "";
  for (const p of state.config.parts) {
    const b = document.createElement("button");
    b.type = "button"; b.className = "chip"; b.dataset.part = p.id;
    b.textContent = p.name; b.setAttribute("aria-pressed", "true");
    b.addEventListener("click", () => b.setAttribute("aria-pressed", b.getAttribute("aria-pressed") === "true" ? "false" : "true"));
    box.appendChild(b);
  }
}

function setFile(file) {
  state.file = file || null;
  const drop = $("drop");
  if (!file) {
    $("file-label").textContent = "音源を選ぶ";
    $("file-sub").textContent = "mp3・m4a（ボイスメモ）・wav など";
    drop.classList.remove("has-file");
    $("submit").disabled = true;
    return;
  }
  const mb = file.size / 1024 / 1024;
  $("file-label").textContent = file.name;
  $("file-sub").textContent = `${mb.toFixed(1)} MB ・ タップして選び直す`;
  drop.classList.add("has-file");
  $("submit").disabled = mb > state.config.max_mb;
  showError(mb > state.config.max_mb ? `ファイルが大きすぎます（${state.config.max_mb}MB まで）` : "");
}

function showError(msg) {
  $("upload-error").textContent = msg;
  $("upload-error").hidden = !msg;
}

$("file").addEventListener("change", (e) => setFile(e.target.files[0]));
for (const ev of ["dragenter", "dragover"]) {
  $("drop").addEventListener(ev, (e) => { e.preventDefault(); $("drop").classList.add("over"); });
}
for (const ev of ["dragleave", "drop"]) {
  $("drop").addEventListener(ev, () => $("drop").classList.remove("over"));
}
$("drop").addEventListener("drop", (e) => { e.preventDefault(); setFile(e.dataTransfer.files[0]); });

$("upload-form").addEventListener("submit", (e) => {
  e.preventDefault();
  if (!state.file) return;
  const chosen = [...document.querySelectorAll("#opt-parts .chip[aria-pressed='true']")].map((b) => b.dataset.part);
  if (!chosen.length) { showError("パートを 1つ以上選んでください"); return; }
  const form = new FormData();
  form.append("audio", state.file);
  form.append("title", $("opt-title").value);
  form.append("chords", $("opt-chords").checked ? "true" : "false");
  form.append("parts", chosen.length === state.config.parts.length ? "" : chosen.join(","));
  form.append("tempo", $("opt-tempo").value);
  form.append("grid", $("opt-grid").value);

  // 送信の進み具合を出すため XMLHttpRequest を使う
  show("progress");
  $("progress-title").textContent = $("opt-title").value || state.file.name.replace(/\.[^.]+$/, "");
  setSteps(0);
  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/api/jobs");
  xhr.upload.onprogress = (ev) => {
    if (!ev.lengthComputable) return;
    const pct = Math.round((ev.loaded / ev.total) * 100);
    $("progress-message").textContent = `送信しています… ${pct}%`;
    $("progress-bar").style.width = `${pct * 0.1}%`;
  };
  xhr.onload = () => {
    let body = {};
    try { body = JSON.parse(xhr.responseText); } catch { /* なし */ }
    if (xhr.status === 401) { show("login"); return; }
    if (xhr.status >= 400) { show("home"); showError(body.detail || `送信できませんでした (${xhr.status})`); return; }
    remember(body.id, $("progress-title").textContent);
    setFile(null);
    $("file").value = "";
    location.hash = `#/job/${body.id}`;
  };
  xhr.onerror = () => { show("home"); showError("送信できませんでした。通信状態を確かめてください。"); };
  xhr.send(form);
});

function remember(id, title) {
  const list = store.get("history", []).filter((h) => h.id !== id);
  list.unshift({ id, title, time: Date.now() });
  store.set("history", list.slice(0, 20));
}

function renderHistory() {
  const list = store.get("history", []);
  const box = $("history-list");
  box.innerHTML = "";
  $("history").hidden = !list.length;
  for (const h of list) {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = `#/job/${h.id}`;
    const t = document.createElement("span"); t.className = "title"; t.textContent = h.title;
    const w = document.createElement("span"); w.className = "when"; w.textContent = when(h.time);
    a.append(t, w); li.appendChild(a); box.appendChild(li);
  }
}

function when(ms) {
  const d = new Date(ms);
  const sameDay = new Date().toDateString() === d.toDateString();
  return sameDay ? d.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" })
                 : d.toLocaleDateString("ja-JP", { month: "numeric", day: "numeric" });
}

// ---------- 処理中 ----------
function setSteps(step, total = 5) {
  [...$("steps").children].forEach((li, i) => {
    li.className = i + 1 < step ? "done" : i + 1 === step ? "active" : "";
  });
  if (step > 0) $("progress-bar").style.width = `${10 + ((step - 1) / total) * 90}%`;
}

async function openJob(id) {
  let job;
  try { job = await (await api(`/api/jobs/${id}`)).json(); }
  catch (e) {
    if (e.message === "login") return;
    store.set("history", store.get("history", []).filter((h) => h.id !== id));
    location.hash = "#/";
    setTimeout(() => showError(e.message), 50);
    return;
  }
  state.job = job;
  if (job.status === "done") { showResult(job); return; }
  if (job.status === "error") {
    location.hash = "#/";
    setTimeout(() => showError(job.error || "変換できませんでした"), 50);
    return;
  }
  show("progress");
  $("progress-title").textContent = job.title;
  updateProgress(job);
  state.poll = setInterval(async () => {
    try {
      const j = await (await api(`/api/jobs/${id}`)).json();
      state.job = j;
      if (j.status === "done") { clearInterval(state.poll); showResult(j); }
      else if (j.status === "error") { clearInterval(state.poll); location.hash = "#/"; setTimeout(() => showError(j.error), 50); }
      else updateProgress(j);
    } catch { /* 通信が切れても次の回にまた聞く */ }
  }, 2000);
}

function updateProgress(job) {
  if (job.status === "queued") {
    setSteps(0);
    $("progress-message").textContent = job.position > 0 ? `順番待ちです（前に ${job.position} 件）` : "まもなく始まります";
    return;
  }
  setSteps(job.step, job.total_steps);
  const elapsed = job.started ? Math.round(Date.now() / 1000 - job.started) : 0;
  const mm = Math.floor(elapsed / 60), ss = String(elapsed % 60).padStart(2, "0");
  $("progress-message").textContent = `${job.message}… (${mm}:${ss})`;
}

// ---------- 結果 ----------
function showResult(job) {
  show("result");
  remember(job.id, job.title);
  const r = job.result;
  $("result-title").textContent = job.title;
  const meta = $("result-meta");
  meta.innerHTML = "";
  const [lo, hi] = r.tempo_range || [r.tempo, r.tempo];
  const chips = [`♩ = ${r.tempo}${hi - lo >= 4 ? `（${lo}–${hi}）` : ""}`];
  if (r.key) chips.push(keyName(r.key));
  chips.push(...Object.keys(r.parts));
  for (const c of chips) { const s = document.createElement("span"); s.textContent = c; meta.appendChild(s); }

  buildViewParts(r);
  selectTab("score");
  renderScore();
  renderChords(job);
  renderDownloads(job);
}

function keyName(k) {
  const [tonic, mode] = k.split(" ");
  return `${tonic} ${mode === "major" ? "メジャー" : "マイナー"}`;
}

document.querySelectorAll(".tab").forEach((t) => t.addEventListener("click", () => selectTab(t.dataset.tab)));
function selectTab(name) {
  document.querySelectorAll(".tab").forEach((t) => t.setAttribute("aria-selected", String(t.dataset.tab === name)));
  for (const n of ["score", "chords", "save"]) $(`tab-${n}`).hidden = n !== name;
}

function buildViewParts(r) {
  const names = Object.keys(r.parts);
  state.parts = null; // null = 全パート
  const box = $("view-parts");
  box.innerHTML = "";
  const all = document.createElement("button");
  all.type = "button"; all.className = "chip"; all.textContent = "全パート"; all.setAttribute("aria-pressed", "true");
  box.appendChild(all);
  const buttons = names.map((n) => {
    const b = document.createElement("button");
    b.type = "button"; b.className = "chip"; b.textContent = n; b.dataset.name = n; b.setAttribute("aria-pressed", "false");
    box.appendChild(b);
    return b;
  });
  all.addEventListener("click", () => {
    state.parts = null;
    all.setAttribute("aria-pressed", "true");
    buttons.forEach((b) => b.setAttribute("aria-pressed", "false"));
    renderScore();
  });
  for (const b of buttons) {
    b.addEventListener("click", () => {
      b.setAttribute("aria-pressed", b.getAttribute("aria-pressed") === "true" ? "false" : "true");
      const on = buttons.filter((x) => x.getAttribute("aria-pressed") === "true").map((x) => x.dataset.name);
      state.parts = on.length ? on : null;
      all.setAttribute("aria-pressed", String(!on.length));
      renderScore();
    });
  }
}

$("zoom-in").addEventListener("click", () => { state.zoom = Math.min(200, state.zoom + 20); renderScore(); });
$("zoom-out").addEventListener("click", () => { state.zoom = Math.max(40, state.zoom - 20); renderScore(); });

// 楽譜の描画はスマホのブラウザで行う（verovio の WebAssembly 版。初回だけ読み込む）
let verovioPromise = null;
function loadVerovio() {
  if (!verovioPromise) {
    verovioPromise = (async () => {
      const [{ default: createVerovioModule }, { VerovioToolkit }] = await Promise.all([
        import("/static/vendor/verovio/verovio-module.mjs"),
        import("/static/vendor/verovio/verovio.mjs"),
      ]);
      return new VerovioToolkit(await createVerovioModule());
    })();
    verovioPromise.catch(() => { verovioPromise = null; });  // 失敗したら次はやり直す
  }
  return verovioPromise;
}

const scoreCache = new Map();  // パートの選び方ごとの MusicXML
let renderToken = 0;
async function renderScore() {
  const token = ++renderToken;
  const box = $("score");
  box.innerHTML = "";
  const parts = state.parts ? state.parts.join(",") : "";
  const key = `${state.job.id}|${parts}`;
  try {
    $("score-status").textContent = verovioPromise ? "楽譜を読み込んでいます…" : "楽譜の表示部品を読み込んでいます…（初回のみ・少し時間がかかります）";
    const [tk, xml] = await Promise.all([
      loadVerovio(),
      scoreCache.get(key) ?? api(`/api/jobs/${state.job.id}/view.musicxml?parts=${encodeURIComponent(parts)}`)
        .then((r) => r.text()).then((t) => { scoreCache.set(key, t); return t; }),
    ]);
    if (token !== renderToken) return;
    const width = Math.max(320, Math.round(box.clientWidth || window.innerWidth));
    const scale = Math.round(state.zoom * 0.32);  // zoom 100 でスマホの幅に 2〜3小節入る大きさ
    tk.setOptions({
      pageWidth: Math.round(width * 100 / scale), pageHeight: Math.round(width * 100 / scale * 1.4),
      scale, adjustPageHeight: true, breaks: "auto", footer: "none", header: "auto",
      svgViewBox: true, svgHtml5: true,
    });
    if (!tk.loadData(xml)) throw new Error("楽譜を読み込めませんでした");
    const pages = tk.getPageCount();
    for (let p = 1; p <= pages; p++) {
      addPage(box, tk.renderToSVG(p));
      if (p < pages) await new Promise((r) => setTimeout(r, 0));  // 長い曲でも画面が固まらないように
      if (token !== renderToken) return;
    }
    $("score-status").textContent = pages > 1 ? `${pages} ページ` : "";
  } catch (e) {
    if (token === renderToken) $("score-status").textContent = `表示できませんでした: ${e.message}`;
  }
}

function addPage(box, svg) {
  const div = document.createElement("div");
  div.className = "page";
  if (svg) div.innerHTML = svg; else { div.classList.add("loading"); div.textContent = "読み込み中…"; }
  box.appendChild(div);
  return div;
}

async function renderChords(job) {
  const grid = $("chord-grid");
  grid.innerHTML = "";
  const has = job.result.files.chords;
  $("chords-empty").hidden = !!has;
  if (!has) return;
  const text = await (await api(`/api/jobs/${job.id}/files/chords`)).text();
  const lines = text.split("\n");
  const head = document.createElement("p");
  head.className = "chord-tempo"; head.textContent = lines[0];
  grid.appendChild(head);
  let prev = "";
  for (const line of lines.slice(2)) {
    const m = line.match(/^\s*(\d+)\s*\|(.*)\|\s*$/);
    if (!m) continue;
    const row = document.createElement("div");
    row.className = "chord-row";
    const num = document.createElement("span"); num.className = "num"; num.textContent = m[1];
    row.appendChild(num);
    for (const cell of m[2].split("|")) {
      const c = document.createElement("div");
      const value = cell.trim();
      c.className = "chord-cell";
      if (value && value === prev) { c.classList.add("same"); c.textContent = "％"; }
      else for (const name of value.split(/\s+/).filter(Boolean)) {
        const s = document.createElement("span"); s.textContent = name; c.appendChild(s);
      }
      if (value) prev = value.split(/\s+/).pop();
      row.appendChild(c);
    }
    grid.appendChild(row);
  }
}

function renderDownloads(job) {
  const box = $("downloads");
  box.innerHTML = "";
  const labels = {
    musicxml: ["楽譜（MusicXML）", "MuseScore などで開けます"],
    pdf: ["楽譜（PDF）", "印刷用"],
    midi: ["MIDI", "DAW・音楽アプリで鳴らせます"],
    chords: ["コード表（テキスト）", "小節ごとのコード"],
  };
  for (const [kind, [name, sub]] of Object.entries(labels)) {
    if (!job.result.files[kind]) continue;
    const a = document.createElement("a");
    a.className = "btn"; a.href = `/api/jobs/${job.id}/files/${kind}`;
    a.setAttribute("download", job.result.files[kind]);
    const left = document.createElement("span"); left.textContent = name;
    const right = document.createElement("span"); right.className = "sub"; right.textContent = sub;
    a.append(left, right);
    box.appendChild(a);
  }
  if (navigator.share) {
    const b = document.createElement("button");
    b.type = "button"; b.className = "btn"; b.textContent = "このページを共有";
    b.addEventListener("click", () => navigator.share({ title: job.title, url: location.href }).catch(() => {}));
    box.appendChild(b);
  }
}

boot().catch(() => show("home"));
