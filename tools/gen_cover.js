#!/usr/bin/env node
// Kindle 電子書籍の表紙画像を作る：node tools/gen_cover.js → build/cover.jpg
// KDP の推奨サイズ：縦 2560 × 横 1600 px（縦横比 1.6:1）、RGB、JPEG。
// 書名・副題・著者名は下の COVER を書き換える。
const path = require('path');
const { chromium } = require('playwright');

const COVER = {
  title1: '6弦ベースのための',
  title2: 'ジャズ理論',
  sub: '〔仮〕B-E-A-D-G-C で考える和声とライン',
  author: '〔仮〕著者名',
  en: 'JAZZ THEORY FOR 6-STRING BASS',
};

const W = 1600, H = 2560;
const GOLD = '#c9a24a';

// 6本の弦：下から⑥B（太い）〜①C（細い）。左下から右上へゆるく弧を描く。
const NAMES = ['B', 'E', 'A', 'D', 'G', 'C'];
const WIDTHS = [11, 9, 7.5, 6, 4.5, 3.5];
function curve(i) {           // i = 0（⑥B）〜 5（①C）の3次ベジェ曲線の制御点
  const y0 = 2230 - i * 78, y1 = 1500 - i * 78;
  return [[-40, y0], [500, y0 - 60], [1100, y1 + 260], [W + 40, y1]];
}
function at(c, t) {
  const u = 1 - t, k = [u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t];
  return [0, 1].map(j => k.reduce((a, w, n) => a + w * c[n][j], 0));
}
function strings() {
  return NAMES.map((n, i) => {
    const c = curve(i);
    return `<path d="M ${c[0]} C ${c[1]}, ${c[2]}, ${c[3]}" stroke="url(#str)" stroke-width="${WIDTHS[i]}" fill="none" stroke-linecap="round"/>` +
           `<text x="70" y="${c[0][1] - 34}" class="sn">${n}</text>`;
  }).join('');
}

// 弦の上を下から上へ登っていく音符（ウォーキングラインのイメージ）。[弦, 位置t]
function notes() {
  const pts = [[0, .17], [1, .3], [2, .43], [3, .56], [4, .68], [5, .8], [5, .93]];
  return pts.map(([i, t], k) => {
    const [x, y] = at(curve(i), t), last = k === pts.length - 1;
    return `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${last ? 30 : 22}" fill="${GOLD}" opacity="${(0.55 + k * 0.07).toFixed(2)}"/>`;
  }).join('');
}

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;width:${W}px;height:${H}px;overflow:hidden}
  body{background:radial-gradient(ellipse at 30% 20%,#1d2d40 0%,#121c28 55%,#0b1119 100%);
       font-family:"IPAGothic",sans-serif;color:#f3efe6;position:relative}
  .en{position:absolute;top:150px;left:0;right:0;text-align:center;font-family:"Inter Display";
      font-weight:600;font-size:40px;letter-spacing:.42em;color:${GOLD}}
  .rule{position:absolute;left:640px;right:640px;height:3px;background:${GOLD}}
  .t1{position:absolute;top:400px;left:0;right:0;text-align:center;font-size:104px;letter-spacing:.12em;
      -webkit-text-stroke:2px #f3efe6}
  .t2{position:absolute;top:560px;left:0;right:0;text-align:center;font-size:250px;letter-spacing:.14em;
      -webkit-text-stroke:6px #f3efe6;padding-left:.14em}
  .sub{position:absolute;top:910px;left:0;right:0;text-align:center;font-size:54px;letter-spacing:.06em;color:#cfd6df}
  .author{position:absolute;bottom:130px;left:0;right:0;text-align:center;font-size:70px;letter-spacing:.3em;
          -webkit-text-stroke:1px #f3efe6}
  svg{position:absolute;left:0;top:0}
  .sn{font-family:"Inter Display";font-weight:600;font-size:34px;fill:#8796a8}
</style></head><body>
<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs><linearGradient id="str" x1="0" x2="1" y1="0" y2="0">
    <stop offset="0" stop-color="#6f7c8c"/><stop offset=".55" stop-color="#d9dde2"/><stop offset="1" stop-color="#8a96a5"/>
  </linearGradient></defs>
  ${strings()}${notes()}
</svg>
<div class="en">${COVER.en}</div>
<div class="rule" style="top:240px"></div>
<div class="t1">${COVER.title1}</div>
<div class="t2">${COVER.title2}</div>
<div class="rule" style="top:880px;left:560px;right:560px"></div>
<div class="sub">${COVER.sub}</div>
<div class="author">${COVER.author}</div>
</body></html>`;

(async () => {
  const out = path.join(__dirname, '..', 'build', 'cover.jpg');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.setContent(html, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: out, type: 'jpeg', quality: 92 });
  await browser.close();
  console.log('built:', out);
})();
