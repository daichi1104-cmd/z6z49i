/**
 * スクショ・LINE → Googleカレンダー 自動登録（共通部分）
 *
 * 使い方は README.md を参照。
 *  - 入口A: Google ドライブの「受信フォルダ」に画像を置く → 5分ごとに自動登録
 *  - 入口B: Web アプリURLに画像を POST（iPhone ショートカット等）→ 即時登録
 *  - 入口C: LINE ボットに文章・画像を送る → 確認ボタンを押すと登録（Line.gs）
 *
 * スクリプトプロパティ（プロジェクトの設定 → スクリプト プロパティ）:
 *   ANTHROPIC_API_KEY  必須  Claude API キー
 *   CALENDAR_ID        任意  登録先。家族で使うなら共有カレンダーのID。省略時はメインカレンダー
 *   CLAUDE_MODEL       任意  省略時 claude-haiku-5-5（精度を上げたいなら claude-sonnet-5-5 / claude-opus-5-5）
 *   WEBHOOK_TOKEN      入口Bを使うなら必須  任意の長いランダム文字列
 *   LINE_* は Line.gs の先頭を参照
 *   INBOX_FOLDER_ID / DONE_FOLDER_ID  setup() が自動で設定
 */

const DEFAULT_MODEL = 'claude-haiku-5-5';
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
  console.log('登録先カレンダー: ' + getCalendar_().getName());
}

function getOrCreateFolder_(name) {
  const it = DriveApp.getFoldersByName(name);
  return it.hasNext() ? it.next() : DriveApp.createFolder(name);
}

function getDoneFolder_() {
  const id = PropertiesService.getScriptProperties().getProperty('DONE_FOLDER_ID');
  return id ? DriveApp.getFolderById(id) : null;
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
      if (!/^image\//.test(file.getMimeType())) continue;
      try {
        const result = extractAndCreate_({ blob: file.getBlob() },
          { sourceUrl: file.getUrl(), sourceLabel: 'スクショ（ドライブ）' });
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

// ───────────────────────── 入口B / C: Web アプリ ─────────────────────────

/**
 * LINE からの Webhook（URL に ?key=... 付き）は Line.gs へ。
 * それ以外はショートカット用:
 *   POST 本文(JSON): { "token": "...", "image": "<base64>", "mimeType": "image/jpeg", "note": "任意メモ" }
 *   レスポンス: { ok, message, created, skipped }
 */
function doPost(e) {
  let body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return json_({ ok: false, message: 'JSON ではありません' });
  }
  if ((e.parameter && e.parameter.key !== undefined) || body.destination !== undefined) {
    return handleLineWebhook_(e, body);
  }

  try {
    const expected = PropertiesService.getScriptProperties().getProperty('WEBHOOK_TOKEN');
    if (!expected || body.token !== expected) return json_({ ok: false, message: 'token が不正です' });
    if (!body.image) return json_({ ok: false, message: 'image がありません' });

    const mime = body.mimeType || 'image/png';
    const blob = Utilities.newBlob(Utilities.base64Decode(String(body.image).replace(/\s/g, '')), mime,
      'screenshot_' + Utilities.formatDate(new Date(), TIMEZONE, 'yyyyMMdd_HHmmss') + extFor_(mime));

    // 元画像も処理済みフォルダに保存し、予定の詳細からリンクする
    const folder = getDoneFolder_();
    const saved = folder ? folder.createFile(blob) : null;

    const result = extractAndCreate_({ blob: blob, note: body.note },
      { sourceUrl: saved ? saved.getUrl() : '', sourceLabel: 'スクショ（ショートカット）' });
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

/** 抽出してそのまま全件登録する（入口A/B 用。確認なし）。 */
function extractAndCreate_(input, ctx) {
  const extracted = extractEvents_(input);
  ctx.transcript = input.text || extracted.transcript;
  const created = [];
  const skipped = [];
  const cal = getCalendar_();

  extracted.events.forEach(ev => {
    try {
      const r = createEvent_(cal, ev, ctx);
      (r.duplicate ? skipped : created).push(r);
    } catch (e) {
      skipped.push({ title: ev.title, reason: String(e) });
    }
  });
  return { created: created, skipped: skipped, noEventReason: extracted.events.length ? '' : extracted.source_summary };
}

function summarize_(r) {
  const lines = [];
  r.created.forEach(c => lines.push('✅ ' + c.when + ' ' + c.title));
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

/**
 * 抽出した1件をカレンダーに登録。同名・同開始時刻の予定があればスキップ。
 * ctx: { transcript, sourceUrl, sourceLabel, registeredBy }
 * 戻り値: { title, when, id, url } または { duplicate: true, title, when, reason }
 */
function createEvent_(cal, ev, ctx) {
  const range = eventRange_(ev);
  const title = ev.title;
  const opts = options_(ev, ctx);

  const exists = cal.getEvents(range.start, range.end).some(e =>
    e.getTitle() === title && e.isAllDayEvent() === range.allDay &&
    e.getStartTime().getTime() === range.start.getTime());
  if (exists) return { duplicate: true, title: title, when: whenText_(ev), reason: '同じ予定が既にあります' };

  let e;
  if (range.allDay) {
    e = cal.createAllDayEvent(title, range.start, range.end, opts);
  } else {
    e = cal.createEvent(title, range.start, range.end, opts);
    if (ev.reminder_minutes_before != null) {
      e.removeAllReminders();
      e.addPopupReminder(ev.reminder_minutes_before);
    }
  }
  return { title: title, when: whenText_(ev), id: e.getId(), url: eventUrl_(e, cal) };
}

/** 抽出結果から開始・終了の Date を求める（終日は終了を翌日0時にする）。 */
function eventRange_(ev) {
  const start = parseLocal_(ev.start);
  if (!start) throw new Error('開始日時を読めません: ' + ev.start);
  let end = ev.end ? parseLocal_(ev.end) : null;

  if (ev.all_day) {
    // 日付部分だけを東京時間の0時として扱う（実行環境のタイムゾーンに依存しない）
    const startDay = parseLocal_(String(ev.start).slice(0, 10));
    const endDay = ev.end ? parseLocal_(String(ev.end).slice(0, 10)) : null;
    const lastDay = endDay && endDay >= startDay ? endDay : startDay;
    return { allDay: true, start: startDay, end: new Date(lastDay.getTime() + 24 * 3600 * 1000) };
  }
  if (!end || end <= start) end = new Date(start.getTime() + 60 * 60 * 1000); // 終了不明なら1時間
  return { allDay: false, start: start, end: end };
}

/** 表示用の日時文字列: "11/5(木) 14:00〜15:00" / "11/5(木) 終日" */
function whenText_(ev) {
  const r = eventRange_(ev);
  const day = d => Utilities.formatDate(d, TIMEZONE, 'M/d(E)');
  const hm = d => Utilities.formatDate(d, TIMEZONE, 'HH:mm');
  if (r.allDay) {
    const last = new Date(r.end.getTime() - 24 * 3600 * 1000);
    return day(r.start) === day(last) ? day(r.start) + ' 終日' : day(r.start) + '〜' + day(last) + ' 終日';
  }
  return day(r.start) === day(r.end)
    ? day(r.start) + ' ' + hm(r.start) + '〜' + hm(r.end)
    : day(r.start) + ' ' + hm(r.start) + '〜' + day(r.end) + ' ' + hm(r.end);
}

function options_(ev, ctx) {
  const parts = [];
  if (ev.details) parts.push(ev.details);
  if (ev.urls && ev.urls.length) parts.push('🔗 リンク\n' + ev.urls.join('\n'));
  if (ev.contacts) parts.push('👤 連絡先・関係者\n' + ev.contacts);
  if (ev.uncertain_points) parts.push('⚠️ 要確認\n' + ev.uncertain_points);
  if (ctx.sourceUrl) parts.push('🖼 元の画像\n' + ctx.sourceUrl);
  if (ctx.transcript) parts.push('📝 元の内容（全文）\n' + ctx.transcript);
  parts.push('― ' + (ctx.sourceLabel || '自動登録') + (ctx.registeredBy ? ' / 登録: ' + ctx.registeredBy : '') +
    ' / ' + Utilities.formatDate(new Date(), TIMEZONE, 'yyyy/MM/dd HH:mm'));
  return { description: parts.join('\n\n').slice(0, 8000), location: ev.location || '' };
}

/** Google カレンダーで予定を開く URL。 */
function eventUrl_(event, cal) {
  const eid = Utilities.base64EncodeWebSafe(event.getId().replace(/@google\.com$/, '') + ' ' + cal.getId())
    .replace(/=+$/, '');
  return 'https://www.google.com/calendar/event?eid=' + eid;
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
    source_summary: { type: 'string', description: '送られてきた内容が何かを1文で' },
    transcript: { type: 'string', description: '画像の場合は画像内の文字をできるだけそのまま書き起こす。文章の場合は空文字' },
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
          reminder_minutes_before: { type: ['integer', 'null'], description: '内容に指示がある場合のみ' }
        },
        required: ['title', 'start', 'end', 'all_day', 'location', 'details', 'urls', 'contacts',
          'uncertain_points', 'reminder_minutes_before'],
        additionalProperties: false
      }
    }
  },
  required: ['source_summary', 'transcript', 'events'],
  additionalProperties: false
};

/**
 * input: { blob?: 画像Blob, text?: 文章, note?: 補足, sender?: 送信者名 }
 * 戻り値: { source_summary, transcript, events: [...] }
 */
function extractEvents_(input) {
  const props = PropertiesService.getScriptProperties();
  const apiKey = props.getProperty('ANTHROPIC_API_KEY');
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY が未設定です');

  const now = Utilities.formatDate(new Date(), TIMEZONE, "yyyy-MM-dd'('E')' HH:mm");
  const content = [];
  if (input.blob) {
    const bytes = input.blob.getBytes();
    if (bytes.length > MAX_IMAGE_BYTES) throw new Error('画像が大きすぎます（5MBまで）');
    content.push({ type: 'image', source: { type: 'base64', media_type: normalizeMime_(input.blob.getContentType()), data: Utilities.base64Encode(bytes) } });
  }
  if (input.text) {
    content.push({ type: 'text', text: '<message>\n' + input.text + '\n</message>' });
  }
  content.push({
    type: 'text',
    text: [
      (input.blob ? 'この画像' : '<message> の文章') + 'から、Googleカレンダーに登録すべき予定をすべて抽出してください。',
      '現在日時は ' + now + '（日本時間）です。「明日」「来週金曜」や年の省略はこれを基準に、未来の日付として解釈してください。',
      '予約確認メール、LINEのやり取り、チケット、イベント告知、学校のお便り、シフト表などが想定されます。',
      '時刻が書かれていなければ all_day を true にしてください。',
      '件名は一目で分かる短いものにし、予約番号・料金・持ち物・集合場所・相手の名前などの詳細は details に漏れなく残してください。',
      '予定が1件もなければ events は空配列にしてください。',
      input.sender ? '送ってきたのは「' + input.sender + '」です（文中の「私」はこの人）。' : '',
      input.note ? '利用者からの補足: ' + input.note : ''
    ].filter(Boolean).join('\n')
  });

  const model = props.getProperty('CLAUDE_MODEL') || DEFAULT_MODEL;
  const payload = {
    model: model,
    max_tokens: 16000,
    output_config: { effort: 'low', format: { type: 'json_schema', schema: EVENT_SCHEMA } },
    messages: [{ role: 'user', content: content }]
  };
  const headers = { 'x-api-key': apiKey, 'anthropic-version': '2026-10-21' };
  // Opus / Sonnet 5.5 などは安全判定で断られたとき別モデルで自動再試行させる（Haiku は非対応）
  if (/^claude-(opus-5|opus-5-5|fable-5-1|sonnet-5-5)$/.test(model)) {
    payload.fallbacks = 'default';
    headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
  }

  const res = fetchWithRetry_('https://api.anthropic.com/v1/messages', {
    method: 'post',
    contentType: 'application/json',
    headers: headers,
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });

  const data = JSON.parse(res.getContentText());
  if (data.stop_reason === 'refusal') throw new Error('Claude が処理を断りました: ' + JSON.stringify(data.stop_details));
  if (data.stop_reason === 'max_tokens') throw new Error('出力が長すぎて途中で切れました');
  const text = (data.content || []).filter(b => b.type === 'text').map(b => b.text).join('');
  const out = JSON.parse(text);
  out.events = out.events || [];
  return out;
}

function normalizeMime_(mime) {
  return ['image/png', 'image/jpeg', 'image/gif', 'image/webp'].indexOf(mime) >= 0 ? mime : 'image/jpeg';
}

/** 429 / 5xx は指数バックオフで再試行、それ以外のエラーは即失敗。 */
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

/** 文章からの抽出だけを試す（カレンダーには登録しない）。結果は実行ログに出る。 */
function testExtractText() {
  console.log(JSON.stringify(extractEvents_({ text: '来週土曜の10時から駅前のカフェで田中さんとランチ。予約番号 R-123', sender: 'テスト' }), null, 2));
}
