/**
 * LINE ボット → 確認ボタン → Googleカレンダー（家族共有）
 *
 * スクリプトプロパティ:
 *   LINE_CHANNEL_ACCESS_TOKEN  必須  LINE Developers で発行した「チャネルアクセストークン（長期）」
 *   LINE_WEBHOOK_KEY           必須  任意の長いランダム文字列。Webhook URL の末尾に ?key=この値 を付ける
 *   LINE_ALLOWED_USER_IDS      必須  使ってよい家族の LINE ユーザーID をカンマ区切りで（U から始まる33文字）
 *   LINE_NAME_IN_TITLE         任意  true にすると件名の先頭に【登録した人の名前】を付ける
 *   CALENDAR_ID                家族の共有カレンダーのIDを推奨（Code.gs 参照）
 *
 * 使い方（LINE で送る内容）:
 *   文章・転送メッセージ・画像 … 予定を読み取り「登録しますか？」と確認ボタンを出す
 *   取り消し                    … 自分が最後に登録した予定を削除
 *   今日 / 明日 / 今週          … 登録先カレンダーの予定を一覧表示
 *   ヘルプ                      … 使い方を表示
 *   グループでは「予定 〜」で始めるか、ボットにメンションした文章だけに反応（画像は1対1トークで送る）
 */

const LINE_API = 'https://api.line.me/v2/bot';
const LINE_DATA_API = 'https://api-data.line.me/v2/bot';
const PENDING_TTL_SEC = 6 * 3600; // 確認待ちの有効期限（CacheService の上限）
const UNDO_STACK_SIZE = 10;

// ───────────────────────── Webhook 入口 ─────────────────────────

function handleLineWebhook_(e, body) {
  const props = PropertiesService.getScriptProperties();
  const key = props.getProperty('LINE_WEBHOOK_KEY');
  // Apps Script では LINE の署名ヘッダーを読めないため、URL の key と許可ユーザーで守る
  if (!key || !e.parameter || e.parameter.key !== key) {
    console.warn('LINE webhook: key が一致しません');
    return ContentService.createTextOutput('ng');
  }

  (body.events || []).forEach(ev => {
    try {
      if (isDuplicateDelivery_(ev)) return;
      handleLineEvent_(ev);
    } catch (err) {
      console.error(err);
      safeReply_(ev, [text_('⚠️ エラーが起きました\n' + String(err).slice(0, 300))]);
    }
  });
  return ContentService.createTextOutput('ok');
}

function isDuplicateDelivery_(ev) {
  if (!ev.webhookEventId) return false;
  const cache = CacheService.getScriptCache();
  const k = 'wh_' + ev.webhookEventId;
  if (cache.get(k)) return true;
  cache.put(k, '1', 3600);
  return false;
}

function handleLineEvent_(ev) {
  const userId = ev.source && ev.source.userId;
  const inGroup = ev.source && ev.source.type !== 'user';

  if (ev.type === 'follow') {
    return safeReply_(ev, [text_(isAllowed_(userId) ? helpText_() :
      '友だち追加ありがとうございます。\nあなたのLINEユーザーIDは\n' + userId +
      '\nです。管理者にこのIDを LINE_ALLOWED_USER_IDS へ追加してもらうと使えるようになります。')]);
  }
  if (ev.type === 'postback') return handlePostback_(ev);
  if (ev.type !== 'message') return;

  const msg = ev.message;
  let text = msg.type === 'text' ? msg.text.trim() : '';

  if (inGroup) {
    // グループでは呼びかけられた時だけ反応する（全部の会話を Claude に送らない）
    if (msg.type !== 'text') return;
    const mentioned = msg.mention && (msg.mention.mentionees || []).some(m => m.isSelf);
    const prefixed = /^[#＃]?予定[\s:：　]/.test(text);
    if (!mentioned && !prefixed) return;
    text = text.replace(/^[#＃]?予定[\s:：　]+/, '').replace(/@\S+\s*/g, '').trim();
  }

  if (!isAllowed_(userId)) {
    return safeReply_(ev, [text_('このボットは登録された家族だけが使えます。\nあなたのLINEユーザーID: ' + userId)]);
  }

  // コマンド
  if (/^(ヘルプ|使い方|help)$/i.test(text)) return safeReply_(ev, [text_(helpText_())]);
  if (/^(取り消し|取消|とりけし|undo)$/i.test(text)) return safeReply_(ev, [text_(undoLast_(userId))]);
  if (/^(今日|きょう)(の予定)?$/.test(text)) return safeReply_(ev, [text_(listEvents_(0, 1, '今日'))]);
  if (/^(明日|あした)(の予定)?$/.test(text)) return safeReply_(ev, [text_(listEvents_(1, 1, '明日'))]);
  if (/^(今週|こんしゅう)(の予定)?$/.test(text)) return safeReply_(ev, [text_(listEvents_(0, 7, '今日から7日間'))]);

  if (msg.type === 'text' && text) return proposeFrom_(ev, { text: text });
  if (msg.type === 'image') return proposeFrom_(ev, { imageMessageId: msg.id });
  if (msg.type === 'sticker') return;
  return safeReply_(ev, [text_('文章か画像を送ってください。「ヘルプ」で使い方を表示します。')]);
}

// ───────────────────────── 読み取り → 確認ボタン ─────────────────────────

function proposeFrom_(ev, src) {
  const userId = ev.source.userId;
  if (ev.source.type === 'user') startLoading_(userId);
  const sender = displayName_(ev.source);

  const ctx = { sourceLabel: 'LINE', registeredBy: sender };
  const input = { sender: sender };
  if (src.text) {
    input.text = src.text;
    ctx.transcript = src.text;
  } else {
    const blob = fetchLineContent_(src.imageMessageId);
    input.blob = blob;
    const folder = getDoneFolder_();
    if (folder) ctx.sourceUrl = folder.createFile(blob).getUrl();
  }

  const extracted = extractEvents_(input);
  if (!ctx.transcript) ctx.transcript = extracted.transcript;
  if (!extracted.events.length) {
    return safeReply_(ev, [text_('予定は見つかりませんでした。\n（' + (extracted.source_summary || '') + '）\n日時が分かるように書き直して送ってみてください。')]);
  }

  const cache = CacheService.getScriptCache();
  const bubbles = extracted.events.slice(0, 12).map(item => {
    if (props_().getProperty('LINE_NAME_IN_TITLE') === 'true' && sender) item.title = '【' + sender + '】' + item.title;
    const k = Utilities.getUuid().replace(/-/g, '');
    const pending = { ev: item, ctx: Object.assign({}, ctx, { transcript: String(ctx.transcript || '').slice(0, 20000) }) };
    cache.put('p_' + k, JSON.stringify(pending), PENDING_TTL_SEC);
    return confirmBubble_(item, k);
  });

  const alt = extracted.events.length + '件の予定が見つかりました: ' + extracted.events.map(x => x.title).join('、');
  const flex = { type: 'flex', altText: alt.slice(0, 400), contents: bubbles.length === 1 ? bubbles[0] : { type: 'carousel', contents: bubbles } };
  return safeReply_(ev, [flex]);
}

function confirmBubble_(item, k) {
  const rows = [
    { type: 'text', text: 'この予定を登録しますか？', size: 'xs', color: '#888888' },
    { type: 'text', text: item.title || '(件名なし)', weight: 'bold', size: 'lg', wrap: true },
    row_('日時', safeWhen_(item))
  ];
  if (item.location) rows.push(row_('場所', item.location));
  if (item.details) rows.push({ type: 'text', text: truncate_(item.details, 300), size: 'sm', color: '#555555', wrap: true, margin: 'md' });
  if (item.uncertain_points) rows.push({ type: 'text', text: '⚠️ ' + truncate_(item.uncertain_points, 150), size: 'xs', color: '#C26A00', wrap: true, margin: 'md' });

  return {
    type: 'bubble',
    body: { type: 'box', layout: 'vertical', spacing: 'sm', contents: rows },
    footer: {
      type: 'box', layout: 'horizontal', spacing: 'sm',
      contents: [
        { type: 'button', style: 'primary', height: 'sm', action: { type: 'postback', label: '登録する', data: 'act=ok&k=' + k, displayText: '登録する：' + truncate_(item.title, 40) } },
        { type: 'button', style: 'secondary', height: 'sm', action: { type: 'postback', label: 'やめる', data: 'act=ng&k=' + k, displayText: 'やめる：' + truncate_(item.title, 40) } }
      ]
    }
  };
}

function row_(label, value) {
  return {
    type: 'box', layout: 'baseline', spacing: 'sm',
    contents: [
      { type: 'text', text: label, size: 'sm', color: '#888888', flex: 1 },
      { type: 'text', text: truncate_(value, 200) || '-', size: 'sm', wrap: true, flex: 4 }
    ]
  };
}

function safeWhen_(item) {
  try { return whenText_(item); } catch (e) { return '日時を読めませんでした（' + item.start + '）'; }
}

// ───────────────────────── ボタンが押されたとき ─────────────────────────

function handlePostback_(ev) {
  const userId = ev.source.userId;
  if (!isAllowed_(userId)) return;
  const params = parseQuery_(ev.postback.data);
  const cacheKey = 'p_' + params.k;

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  let pending;
  try {
    const cache = CacheService.getScriptCache();
    const raw = cache.get(cacheKey);
    if (!raw) return safeReply_(ev, [text_('この確認は処理済みか、期限（6時間）が切れています。もう一度送ってください。')]);
    cache.remove(cacheKey); // 二度押し防止
    pending = JSON.parse(raw);
  } finally {
    lock.releaseLock();
  }

  if (params.act === 'ng') return safeReply_(ev, [text_('登録をやめました：' + pending.ev.title)]);

  const cal = getCalendar_();
  const ctx = pending.ctx;
  ctx.registeredBy = ctx.registeredBy || displayName_(ev.source);
  const r = createEvent_(cal, pending.ev, ctx);
  if (r.duplicate) return safeReply_(ev, [text_('⏭ 同じ予定がすでにあるので登録しませんでした\n' + r.when + ' ' + r.title)]);

  pushUndo_(userId, { id: r.id, title: r.title, when: r.when });
  return safeReply_(ev, [text_('✅ 登録しました\n' + r.when + '\n' + r.title + '\n' + r.url + '\n\n間違えたら「取り消し」と送ってください。')]);
}

// ───────────────────────── 取り消し・一覧 ─────────────────────────

function pushUndo_(userId, entry) {
  const props = PropertiesService.getScriptProperties();
  const k = 'undo_' + userId;
  const stack = JSON.parse(props.getProperty(k) || '[]');
  stack.push(entry);
  props.setProperty(k, JSON.stringify(stack.slice(-UNDO_STACK_SIZE)));
}

function undoLast_(userId) {
  const props = PropertiesService.getScriptProperties();
  const k = 'undo_' + userId;
  const stack = JSON.parse(props.getProperty(k) || '[]');
  const last = stack.pop();
  props.setProperty(k, JSON.stringify(stack));
  if (!last) return '取り消せる予定がありません。';
  const e = getCalendar_().getEventById(last.id);
  if (!e) return 'すでに削除されています：' + last.title;
  e.deleteEvent();
  return '🗑 取り消しました\n' + last.when + ' ' + last.title;
}

function listEvents_(offsetDays, days, label) {
  const today = parseLocal_(Utilities.formatDate(new Date(), TIMEZONE, 'yyyy-MM-dd'));
  const start = new Date(today.getTime() + offsetDays * 24 * 3600 * 1000);
  const end = new Date(start.getTime() + days * 24 * 3600 * 1000);
  const events = getCalendar_().getEvents(start, end);
  if (!events.length) return '📅 ' + label + 'の予定はありません。';
  const lines = events.slice(0, 40).map(e => {
    const day = Utilities.formatDate(e.getStartTime(), TIMEZONE, 'M/d(E)');
    const time = e.isAllDayEvent() ? '終日' : Utilities.formatDate(e.getStartTime(), TIMEZONE, 'HH:mm');
    return (days > 1 ? day + ' ' : '') + time + ' ' + e.getTitle();
  });
  return '📅 ' + label + 'の予定\n' + lines.join('\n');
}

function helpText_() {
  return [
    '📅 予定登録ボットの使い方',
    '',
    '・予定が書かれた文章や画像を送る',
    '・他のトークのメッセージを長押し→「転送」でもOK',
    '→ 内容を読み取って「登録しますか？」と聞くので［登録する］を押してください',
    '',
    '・「取り消し」… 最後に登録した予定を削除',
    '・「今日」「明日」「今週」… 予定の一覧',
    '・グループでは「予定 〜」で始めて送ってください'
  ].join('\n');
}

// ───────────────────────── LINE API ─────────────────────────

function props_() {
  return PropertiesService.getScriptProperties();
}

function isAllowed_(userId) {
  const list = (props_().getProperty('LINE_ALLOWED_USER_IDS') || '').split(',').map(s => s.trim()).filter(Boolean);
  return !!userId && list.indexOf(userId) >= 0;
}

function lineFetch_(url, method, payload) {
  const token = props_().getProperty('LINE_CHANNEL_ACCESS_TOKEN');
  if (!token) throw new Error('LINE_CHANNEL_ACCESS_TOKEN が未設定です');
  const opts = { method: method, headers: { Authorization: 'Bearer ' + token }, muteHttpExceptions: true };
  if (payload) {
    opts.contentType = 'application/json';
    opts.payload = JSON.stringify(payload);
  }
  return UrlFetchApp.fetch(url, opts);
}

/** 返信（無料）。返信トークンが期限切れなどで失敗したらプッシュ（無料枠を消費）で送る。 */
function safeReply_(ev, messages) {
  if (ev.replyToken) {
    const res = lineFetch_(LINE_API + '/message/reply', 'post', { replyToken: ev.replyToken, messages: messages });
    if (res.getResponseCode() === 200) return;
    console.warn('reply 失敗: ' + res.getResponseCode() + ' ' + res.getContentText());
  }
  const to = ev.source && (ev.source.groupId || ev.source.roomId || ev.source.userId);
  if (!to) return;
  const res = lineFetch_(LINE_API + '/message/push', 'post', { to: to, messages: messages });
  if (res.getResponseCode() !== 200) console.error('push 失敗: ' + res.getResponseCode() + ' ' + res.getContentText());
}

/** 1対1トークで「入力中…」のアニメーションを出す（失敗しても無視）。 */
function startLoading_(userId) {
  try {
    lineFetch_(LINE_API + '/chat/loading/start', 'post', { chatId: userId, loadingSeconds: 30 });
  } catch (e) { /* noop */ }
}

function fetchLineContent_(messageId) {
  const res = lineFetch_(LINE_DATA_API + '/message/' + messageId + '/content', 'get');
  if (res.getResponseCode() !== 200) throw new Error('LINE から画像を取得できませんでした (' + res.getResponseCode() + ')');
  const blob = res.getBlob();
  const h = res.getHeaders();
  const mime = (h['Content-Type'] || h['content-type'] || blob.getContentType() || 'image/jpeg').split(';')[0];
  return blob.setContentType(mime)
    .setName('line_' + Utilities.formatDate(new Date(), TIMEZONE, 'yyyyMMdd_HHmmss') + extFor_(mime));
}

/** 送信者の LINE 表示名（6時間キャッシュ）。 */
function displayName_(source) {
  const userId = source.userId;
  if (!userId) return '';
  const cache = CacheService.getScriptCache();
  const cached = cache.get('name_' + userId);
  if (cached) return cached;

  const urls = [LINE_API + '/profile/' + userId];
  if (source.groupId) urls.push(LINE_API + '/group/' + source.groupId + '/member/' + userId);
  if (source.roomId) urls.push(LINE_API + '/room/' + source.roomId + '/member/' + userId);
  for (let i = 0; i < urls.length; i++) {
    const res = lineFetch_(urls[i], 'get');
    if (res.getResponseCode() === 200) {
      const name = JSON.parse(res.getContentText()).displayName || '';
      cache.put('name_' + userId, name, 21600);
      return name;
    }
  }
  return '';
}

function text_(s) {
  return { type: 'text', text: String(s).slice(0, 5000) };
}

function truncate_(s, n) {
  s = String(s || '');
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

function parseQuery_(q) {
  const out = {};
  String(q || '').split('&').forEach(p => {
    const i = p.indexOf('=');
    if (i > 0) out[decodeURIComponent(p.slice(0, i))] = decodeURIComponent(p.slice(i + 1));
  });
  return out;
}
