/**
 * スクショ → Googleカレンダー 自動登録
 *
 * 使い方は README.md を参照。
 *  - 入口A: Google ドライブの「受信フォルダ」に画像を置く → 5分ごとに自動処理
 *  - 入口B: Web アプリURLに画像を POST（iPhone ショートカット等）→ 即時処理
 *
 * スクリプトプロパティ（プロジェクトの設定 → スクリプト プロパティ）:
 *   ANTHROPIC_API_KEY  必須  Claude API キー
 *   WEBHOOK_TOKEN      入口Bを使うなら必須  任意の長いランダム文字列
 *   CALENDAR_ID        任意  省略時はメインカレンダー
 *   CLAUDE_MODEL       任意  省略時 claude-opus-5-5（安くしたいなら claude-haiku-5-5）
 *   INBOX_FOLDER_ID / DONE_FOLDER_ID  setup() が自動で設定
 */

const DEFAULT_MODEL = 'claude-opus-5-5';
const TIMEZONE = 'Asia/Tokyo';
const INBOX_FOLDER_NAME = 'スクショ→予定（受信）';
const DONE_FOLDER_NAME = 'スクショ→予定（処理済み）';
const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // Claude API の画像1枚あたり上限

// ───────────────────────── セットアップ ─────────────────────────

/** 初回に1回だけ手動実行する。フォルダ作成と5分おきのトリガー登録を行う。 */
function setup() {
  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty('ANTHROPIC_API_KEY')) {
    throw new Error('スクリプトプロパティ ANTHROPIC_API_KEY を先に設定してください。');
  }
  const inbox = getOrCreateFolder_(INBOX_FOLDER_NAME);
  const done = getOrCreateFolder_(DONE_FOLDER_NAME);
  props.setProperty('INBOX_FOLDER_ID', inbox.getId());
  props.setProperty('DONE_FOLDER_ID', done.getId());

  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'processInbox')
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('processInbox').timeBased().everyMinutes(5).create();

  console.log('受信フォルダ: ' + inbox.getUrl());
  console.log('処理済みフォルダ: ' + done.getUrl());
}

function getOrCreateFolder_(name) {
  const it = DriveApp.getFoldersByName(name);
  return it.hasNext() ? it.next() : DriveApp.createFolder(name);
}

// ───────────────────────── 入口A: ドライブ監視 ─────────────────────────

/** 受信フォルダ内の画像を処理する（トリガーから呼ばれる）。 */
function processInbox() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return; // 前回の実行がまだ動いている
  try {
    const props = PropertiesService.getScriptProperties();
    const inbox = DriveApp.getFolderById(props.getProperty('INBOX_FOLDER_ID'));
    const done = DriveApp.getFolderById(props.getProperty('DONE_FOLDER_ID'));
    const files = inbox.getFiles();
    while (files.hasNext()) {
      const file = files.next();
      const mime = file.getMimeType();
      if (!/^image\//.test(mime)) continue;
      try {
        const result = handleImage_(file.getBlob(), file.getUrl(), file.getName());
        file.setDescription(summarize_(result));
        file.moveTo(done);
      } catch (e) {
        console.error(file.getName() + ': ' + e);
        file.setName('[エラー] ' + file.getName());
        file.setDescription(String(e));
        file.moveTo(done);
      }
    }
  } finally {
    lock.releaseLock();
  }
}

// ───────────────────────── 入口B: Web アプリ ─────────────────────────

/**
 * POST 本文(JSON): { "token": "...", "image": "<base64>", "mimeType": "image/png", "note": "任意メモ" }
 * レスポンス: { ok, created: [{title, start, url}], skipped, message }
 */
function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    const expected = PropertiesService.getScriptProperties().getProperty('WEBHOOK_TOKEN');
    if (!expected || body.token !== expected) return json_({ ok: false, message: 'token が不正です' });
    if (!body.image) return json_({ ok: false, message: 'image がありません' });

    const mime = body.mimeType || 'image/png';
    const blob = Utilities.newBlob(Utilities.base64Decode(String(body.image).replace(/\s/g, '')), mime,
      'screenshot_' + Utilities.formatDate(new Date(), TIMEZONE, 'yyyyMMdd_HHmmss') + extFor_(mime));

    // 元画像も処理済みフォルダに保存し、予定の詳細からリンクする
    const doneId = PropertiesService.getScriptProperties().getProperty('DONE_FOLDER_ID');
    const saved = doneId ? DriveApp.getFolderById(doneId).createFile(blob) : null;

    const result = handleImage_(blob, saved ? saved.getUrl() : '', blob.getName(), body.note);
    if (saved) saved.setDescription(summarize_(result));
    return json_(Object.assign({ ok: true, message: summarize_(result) }, result));
  } catch (err) {
    console.error(err);
    return json_({ ok: false, message: String(err) });
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function extFor_(mime) {
  return { 'image/png': '.png', 'image/jpeg': '.jpg', 'image/gif': '.gif', 'image/webp': '.webp' }[mime] || '';
}

// ───────────────────────── 共通処理 ─────────────────────────

function handleImage_(blob, imageUrl, fileName, note) {
  const extracted = extractEvents_(blob, note);
  const created = [];
  const skipped = [];
  const cal = getCalendar_();

  (extracted.events || []).forEach(ev => {
    try {
      const r = createEvent_(cal, ev, extracted, imageUrl, fileName);
      (r.duplicate ? skipped : created).push(r);
    } catch (e) {
      skipped.push({ title: ev.title, reason: String(e) });
    }
  });
  return { created: created, skipped: skipped, noEventReason: extracted.events.length ? '' : extracted.image_summary };
}

function summarize_(r) {
  const lines = [];
  r.created.forEach(c => lines.push('✅ ' + c.start + ' ' + c.title));
  r.skipped.forEach(s => lines.push('⏭ ' + s.title + '（' + (s.reason || '重複') + '）'));
  if (!lines.length) lines.push('予定が見つかりませんでした: ' + (r.noEventReason || ''));
  return lines.join('\n');
}

function getCalendar_() {
  const id = PropertiesService.getScriptProperties().getProperty('CALENDAR_ID');
  const cal = id ? CalendarApp.getCalendarById(id) : CalendarApp.getDefaultCalendar();
  if (!cal) throw new Error('カレンダーが見つかりません: ' + id);
  return cal;
}

/** 抽出した1件をカレンダーに登録。同名・同開始時刻の予定があればスキップ。 */
function createEvent_(cal, ev, extracted, imageUrl, fileName) {
  const start = parseLocal_(ev.start);
  if (!start) throw new Error('開始日時を読めません: ' + ev.start);

  let end = ev.end ? parseLocal_(ev.end) : null;
  if (ev.all_day) {
    // 終日: end は「最終日」を含む扱い → CalendarApp は翌日0時を終了に取る
    const startDay = new Date(start.getFullYear(), start.getMonth(), start.getDate());
    const lastDay = end ? new Date(end.getFullYear(), end.getMonth(), end.getDate()) : startDay;
    const endExclusive = new Date(lastDay.getTime() + 24 * 3600 * 1000);
    if (isDuplicate_(cal, ev.title, startDay, endExclusive, true)) return dup_(ev, start);
    const e = cal.createAllDayEvent(ev.title, startDay, endExclusive, options_(ev, extracted, imageUrl, fileName));
    return done_(e, ev, start);
  }

  if (!end || end <= start) end = new Date(start.getTime() + 60 * 60 * 1000); // 終了不明なら1時間
  if (isDuplicate_(cal, ev.title, start, end, false)) return dup_(ev, start);
  const e = cal.createEvent(ev.title, start, end, options_(ev, extracted, imageUrl, fileName));
  if (ev.reminder_minutes_before != null) {
    e.removeAllReminders();
    e.addPopupReminder(ev.reminder_minutes_before);
  }
  return done_(e, ev, start);
}

function options_(ev, extracted, imageUrl, fileName) {
  const parts = [];
  if (ev.details) parts.push(ev.details);
  if (ev.urls && ev.urls.length) parts.push('🔗 リンク\n' + ev.urls.join('\n'));
  if (ev.contacts) parts.push('👤 連絡先・関係者\n' + ev.contacts);
  if (ev.uncertain_points) parts.push('⚠️ 要確認\n' + ev.uncertain_points);
  parts.push('🖼 元のスクショ\n' + (imageUrl || fileName));
  if (extracted.transcript) parts.push('📝 画像内テキスト（全文）\n' + extracted.transcript);
  parts.push('― スクショから自動登録 ' + Utilities.formatDate(new Date(), TIMEZONE, 'yyyy/MM/dd HH:mm'));
  return { description: parts.join('\n\n').slice(0, 8000), location: ev.location || '' };
}

function isDuplicate_(cal, title, start, end, allDay) {
  return cal.getEvents(start, end).some(e =>
    e.getTitle() === title && e.isAllDayEvent() === allDay && e.getStartTime().getTime() === start.getTime());
}

function dup_(ev, start) {
  return { duplicate: true, title: ev.title, start: fmt_(start), reason: '同じ予定が既にあります' };
}

function done_(e, ev, start) {
  return { title: ev.title, start: fmt_(start), id: e.getId() };
}

function fmt_(d) {
  return Utilities.formatDate(d, TIMEZONE, 'M/d(E) HH:mm');
}

/** "2026-11-05T14:00" / "2026-11-05" を東京時間として Date に変換。 */
function parseLocal_(s) {
  const m = String(s || '').match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?/);
  if (!m) return null;
  const iso = m[1] + '-' + m[2] + '-' + m[3] + 'T' + (m[4] || '00') + ':' + (m[5] || '00') + ':00+09:00';
  return new Date(iso);
}

// ───────────────────────── Claude API ─────────────────────────

const EVENT_SCHEMA = {
  type: 'object',
  properties: {
    image_summary: { type: 'string', description: '画像が何のスクショかを1文で' },
    transcript: { type: 'string', description: '画像内の文字をできるだけそのまま書き起こしたもの' },
    events: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'カレンダーに表示する短い件名' },
          start: { type: 'string', description: 'YYYY-MM-DDTHH:MM（終日なら YYYY-MM-DD）。日本時間' },
          end: { type: 'string', description: '同形式。不明なら空文字' },
          all_day: { type: 'boolean' },
          location: { type: 'string', description: '場所・住所・オンラインURL。なければ空文字' },
          details: { type: 'string', description: '持ち物、料金、予約番号、注意事項、相手の名前など予定に役立つ詳細を箇条書きで' },
          urls: { type: 'array', items: { type: 'string' } },
          contacts: { type: 'string', description: '主催者・相手・電話番号など。なければ空文字' },
          uncertain_points: { type: 'string', description: '推測で補った箇所や読み取れなかった箇所。なければ空文字' },
          reminder_minutes_before: { type: ['integer', 'null'], description: '画像内で指示がある場合のみ' }
        },
        required: ['title', 'start', 'end', 'all_day', 'location', 'details', 'urls', 'contacts',
          'uncertain_points', 'reminder_minutes_before'],
        additionalProperties: false
      }
    }
  },
  required: ['image_summary', 'transcript', 'events'],
  additionalProperties: false
};

function extractEvents_(blob, note) {
  const props = PropertiesService.getScriptProperties();
  const apiKey = props.getProperty('ANTHROPIC_API_KEY');
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY が未設定です');
  const bytes = blob.getBytes();
  if (bytes.length > MAX_IMAGE_BYTES) throw new Error('画像が大きすぎます（5MBまで）');

  const now = Utilities.formatDate(new Date(), TIMEZONE, "yyyy-MM-dd'('E')' HH:mm");
  const prompt = [
    'このスクリーンショットから、Googleカレンダーに登録すべき予定をすべて抽出してください。',
    '現在日時は ' + now + '（日本時間）です。「明日」「来週金曜」や年の省略はこれを基準に、未来の日付として解釈してください。',
    '予約確認メール、LINEのやり取り、チケット、イベント告知、シフト表などが想定されます。',
    '時刻が書かれていなければ all_day を true にしてください。',
    '件名は一目で分かる短いものにし、予約番号・料金・持ち物・集合場所・相手の名前などの詳細は details に漏れなく残してください。',
    '予定が1件もない画像なら events は空配列にしてください。',
    note ? '利用者からの補足: ' + note : ''
  ].join('\n');

  const payload = {
    model: props.getProperty('CLAUDE_MODEL') || DEFAULT_MODEL,
    max_tokens: 16000,
    output_config: { effort: 'low', format: { type: 'json_schema', schema: EVENT_SCHEMA } },
    fallbacks: 'default',
    messages: [{
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', media_type: normalizeMime_(blob.getContentType()), data: Utilities.base64Encode(bytes) } },
        { type: 'text', text: prompt }
      ]
    }]
  };

  const res = fetchWithRetry_('https://api.anthropic.com/v1/messages', {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2026-10-21',
      'anthropic-beta': 'server-side-fallback-2026-07-01'
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });

  const data = JSON.parse(res.getContentText());
  if (data.stop_reason === 'refusal') throw new Error('Claude が処理を断りました: ' + JSON.stringify(data.stop_details));
  if (data.stop_reason === 'max_tokens') throw new Error('出力が長すぎて途中で切れました');
  const text = (data.content || []).filter(b => b.type === 'text').map(b => b.text).join('');
  return JSON.parse(text);
}

function normalizeMime_(mime) {
  return ['image/png', 'image/jpeg', 'image/gif', 'image/webp'].indexOf(mime) >= 0 ? mime : 'image/png';
}

/** 429 / 5xx / 529 は指数バックオフで再試行、それ以外のエラーは即失敗。 */
function fetchWithRetry_(url, opts) {
  let wait = 2000;
  for (let i = 0; ; i++) {
    const res = UrlFetchApp.fetch(url, opts);
    const code = res.getResponseCode();
    if (code === 200) return res;
    const retryable = code === 429 || code >= 500;
    if (!retryable || i >= 3) throw new Error('Claude API エラー ' + code + ': ' + res.getContentText().slice(0, 500));
    Utilities.sleep(wait);
    wait *= 2;
  }
}

// ───────────────────────── 動作確認用 ─────────────────────────

/** 受信フォルダの処理を今すぐ1回実行する（エディタから手動実行用）。 */
function runNow() {
  processInbox();
}
