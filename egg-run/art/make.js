// アイコンとサムネイルを作る：node art/make.js（Chromium で SVG を描いて PNG にする）
// 絵は全部ここで描いている（ほかの画像は使っていない）
const { chromium } = require('playwright');
const path = require('path');

const OUT = __dirname;
const FONT = "'Mochiy Pop One', 'IPAGothic', sans-serif";
const INK = '#1c2340';

// ドラゴン（右向き、200×200）。色は CSS の変数で変える
const DEFS = `
<defs>
  <symbol id="dragon" viewBox="0 0 200 200" overflow="visible">
    <g stroke="${INK}" stroke-width="4.5" stroke-linejoin="round" stroke-linecap="round">
      <path d="M72,122 C42,140 14,130 18,98 L6,86 L30,86 C28,110 44,118 66,108 Z" fill="var(--c)"/>
      <path d="M86,98 C72,56 52,44 30,36 C46,58 42,68 36,76 C54,72 60,84 54,94 C70,88 76,100 86,108 Z" fill="var(--w)"/>
      <path d="M60,100 L54,88 L68,94 Z M70,90 L68,76 L80,86 Z" fill="var(--w)"/>
      <ellipse cx="78" cy="152" rx="15" ry="11" fill="var(--c)"/>
      <ellipse cx="95" cy="120" rx="38" ry="34" fill="var(--c)"/>
      <ellipse cx="106" cy="128" rx="21" ry="23" fill="var(--b)"/>
      <path d="M98,116 Q106,112 114,116 M96,128 Q106,124 116,128 M98,140 Q106,136 114,140" fill="none" stroke-width="2.5" opacity="0.45"/>
      <ellipse cx="114" cy="154" rx="15" ry="11" fill="var(--c)"/>
      <path d="M104,52 L94,20 L118,44 Z" fill="var(--h)"/>
      <path d="M126,44 L130,10 L144,44 Z" fill="var(--h)"/>
      <circle cx="124" cy="80" r="36" fill="var(--c)"/>
      <path d="M92,70 L84,62 L94,62 Z" fill="var(--w)"/>
      <ellipse cx="154" cy="92" rx="22" ry="16" fill="var(--c)"/>
      <ellipse cx="128" cy="124" rx="9" ry="8" fill="var(--c)"/>
      <ellipse cx="135" cy="73" rx="12" ry="14" fill="#fff"/>
      <ellipse cx="139" cy="75" rx="7" ry="10" fill="var(--p, ${INK})" stroke="none"/>
      <circle cx="142" cy="69" r="3.4" fill="#fff" stroke="none"/>
      <circle cx="137" cy="81" r="1.6" fill="#fff" stroke="none"/>
      <path d="M150,100 Q160,106 170,98" fill="none" stroke-width="3.5"/>
      <circle cx="165" cy="86" r="2.2" fill="${INK}" stroke="none"/>
      <g style="opacity:var(--angry, 0)">
        <path d="M118,50 L154,64" fill="none" stroke-width="8"/>
        <path d="M153,101 L158,113 L163,100 Z M163,99 L167,109 L170,97 Z" fill="#fff" stroke-width="2.5"/>
      </g>
    </g>
    <ellipse cx="122" cy="96" rx="8" ry="5" fill="#ff8fa8" style="opacity:calc(0.6 - 0.6 * var(--angry, 0))"/>
  </symbol>
  <symbol id="egg" viewBox="0 0 100 120" overflow="visible">
    <path d="M50,4 C80,4 96,56 96,76 C96,102 76,116 50,116 C24,116 4,102 4,76 C4,56 20,4 50,4 Z"
      fill="var(--e)" stroke="${INK}" stroke-width="4.5"/>
    <path d="M22,70 L36,58 L50,72 L64,58 L78,70" fill="none" stroke="var(--s)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="34" cy="94" r="6" fill="var(--s)"/><circle cx="66" cy="92" r="8" fill="var(--s)"/>
    <ellipse cx="34" cy="34" rx="9" ry="15" fill="#fff" opacity="0.65" transform="rotate(25 34 34)"/>
  </symbol>
  <radialGradient id="glow"><stop offset="0" stop-color="#fff6b0" stop-opacity="0.95"/><stop offset="1" stop-color="#ffd84a" stop-opacity="0"/></radialGradient>
  <linearGradient id="titleFill" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff7a8"/><stop offset="0.55" stop-color="#ffd02a"/><stop offset="1" stop-color="#ff8a1a"/>
  </linearGradient>
  <linearGradient id="redFill" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffd0c0"/><stop offset="0.5" stop-color="#ff4a3a"/><stop offset="1" stop-color="#b0101a"/>
  </linearGradient>
</defs>`;

const BLUE = '--c:#5cc8ff;--b:#fff1c9;--w:#2f8fe0;--h:#fffbe8';
const GOLD_EGG = '--e:#ffd23a;--s:#ff9a1a';
const DRAGONS = [
  ['#5cc8ff', '#fff1c9', '#2f8fe0'], ['#ff6a4a', '#ffe0a0', '#c43a2a'], ['#6ad86a', '#f4ffc0', '#2f9a40'],
  ['#b07cff', '#f0e4ff', '#7a4ad8'], ['#ffd23a', '#fff6d0', '#e0a010'], ['#4ad8c8', '#e0fff8', '#1a9a90'],
  ['#ff8fd0', '#fff0f8', '#d04a9a'], ['#c0c8d8', '#ffffff', '#7a8498'], ['#3a4a7a', '#a0b0e0', '#1a2450'],
  ['#ff9a3a', '#fff0c0', '#d0601a'],
];
const dragonStyle = (d) => `--c:${d[0]};--b:${d[1]};--w:${d[2]};--h:#fffbe8`;

// 太いふちどりの文字
function title(x, y, size, text, fill = 'url(#titleFill)', anchor = 'start', rot = 0) {
  return `<g transform="rotate(${rot} ${x} ${y})" font-family="${FONT}" font-size="${size}" text-anchor="${anchor}">
    <text x="${x}" y="${y + size * 0.08}" fill="${INK}" stroke="${INK}" stroke-width="${size * 0.32}" stroke-linejoin="round" opacity="0.35">${text}</text>
    <text x="${x}" y="${y}" fill="${fill}" stroke="#fff" stroke-width="${size * 0.3}" stroke-linejoin="round" paint-order="stroke">${text}</text>
    <text x="${x}" y="${y}" fill="${fill}" stroke="${INK}" stroke-width="${size * 0.14}" stroke-linejoin="round" paint-order="stroke">${text}</text>
  </g>`;
}

function rays(cx, cy, n, color, opacity, len = 2400) {
  let s = '';
  for (let i = 0; i < n; i++) {
    const a0 = (i / n) * Math.PI * 2, a1 = a0 + Math.PI / n;
    s += `<path d="M${cx},${cy} L${cx + Math.cos(a0) * len},${cy + Math.sin(a0) * len} L${cx + Math.cos(a1) * len},${cy + Math.sin(a1) * len} Z"/>`;
  }
  return `<g fill="${color}" opacity="${opacity}">${s}</g>`;
}

// 速さの線（左へ流れる）
function speed(x, y, w, h, n, seed = 1, color = '#fff') {
  let s = '', r = seed;
  const rnd = () => ((r = (r * 9301 + 49297) % 233280) / 233280);
  for (let i = 0; i < n; i++) {
    const ly = y + rnd() * h, len = w * (0.3 + rnd() * 0.7), lx = x + rnd() * (w - len);
    s += `<line x1="${lx}" y1="${ly}" x2="${lx + len}" y2="${ly}" stroke-width="${4 + rnd() * 10}" opacity="${0.4 + rnd() * 0.5}"/>`;
  }
  return `<g stroke="${color}" stroke-linecap="round">${s}</g>`;
}

const use = (id, x, y, w, style, extra = '') =>
  `<use href="#${id}" x="${x}" y="${y}" width="${w}" height="${id === 'egg' ? w * 1.2 : w}" style="${style}" ${extra}/>`;

function cloud(x, y, s, o = 1) {
  return `<g fill="#fff" opacity="${o}" transform="translate(${x} ${y}) scale(${s})">
    <circle cx="0" cy="0" r="40"/><circle cx="45" cy="-15" r="50"/><circle cx="95" cy="0" r="38"/><rect x="0" y="0" width="95" height="38"/></g>`;
}

const scenes = {
  // アイコン：大きなドラゴンと 黄金のたまご
  icon: [512, 512, `
    <rect width="512" height="512" fill="#ff9a2a"/>
    <circle cx="300" cy="230" r="420" fill="#ffc23a"/>
    ${rays(300, 230, 18, '#fff3a0', 0.45)}
    <circle cx="300" cy="230" r="200" fill="url(#glow)"/>
    ${speed(-40, 120, 230, 300, 14, 3)}
    <g transform="rotate(-6 280 260)">${use('dragon', 50, 20, 460, BLUE)}</g>
    <circle cx="112" cy="400" r="110" fill="url(#glow)"/>
    <g transform="rotate(-14 110 400)">${use('egg', 40, 300, 140, GOLD_EGG)}</g>
    <g font-family="${FONT}" transform="rotate(-10 120 70)">
      <rect x="22" y="22" width="196" height="90" rx="26" fill="#ff3a3a" stroke="${INK}" stroke-width="7"/>
      <text x="120" y="88" font-size="60" text-anchor="middle" fill="#fff" stroke="${INK}" stroke-width="5" paint-order="stroke">爆速!</text>
    </g>
  `],

  // サムネイル1：タイトルと 走るドラゴン
  thumb1_title: [1920, 1080, `
    <linearGradient id="sky1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2f8fff"/><stop offset="1" stop-color="#bfeaff"/></linearGradient>
    <rect width="1920" height="1080" fill="url(#sky1)"/>
    ${rays(1320, 520, 24, '#ffffff', 0.13)}
    ${cloud(140, 600, 1.4, 0.9)}${cloud(1500, 150, 1.1, 0.8)}${cloud(900, 90, 0.8, 0.7)}
    <path d="M0,640 C300,560 600,600 960,630 C1300,600 1600,560 1920,620 L1920,1080 L0,1080 Z" fill="#7ad65a"/>
    <path d="M0,700 C400,650 800,690 1920,680 L1920,1080 L0,1080 Z" fill="#5cc04a"/>
    <path d="M900,640 L1020,640 L1500,1080 L420,1080 Z" fill="#e9c98a" stroke="#c9a060" stroke-width="6"/>
    <path d="M960,650 L960,1080" stroke="#fff" stroke-width="10" stroke-dasharray="40 40" opacity="0.8"/>
    ${use('egg', 900, 610, 40, '--e:#ff8fd0;--s:#d04a9a')}${use('egg', 1000, 660, 56, '--e:#6ad86a;--s:#2f9a40')}
    ${use('egg', 560, 900, 90, '--e:#b07cff;--s:#7a4ad8')}
    <circle cx="1330" cy="560" r="330" fill="url(#glow)" opacity="0.8"/>
    ${speed(560, 330, 640, 520, 22, 7)}
    <g fill="#fff" opacity="0.85"><circle cx="1150" cy="800" r="44"/><circle cx="1080" cy="830" r="32"/><circle cx="1200" cy="840" r="36"/><circle cx="1010" cy="850" r="22"/></g>
    <g transform="rotate(-8 1330 600)">${use('dragon', 980, 240, 720, BLUE)}</g>
    <circle cx="1530" cy="680" r="140" fill="url(#glow)"/>
    <g transform="rotate(12 1530 690)">${use('egg', 1465, 600, 130, GOLD_EGG)}</g>
    ${title(70, 250, 168, '爆速', 'url(#titleFill)', 'start', -6)}
    ${title(90, 440, 132, 'ドラゴニック', 'url(#titleFill)', 'start', -6)}
    ${title(120, 610, 150, '卵ゲーム', 'url(#titleFill)', 'start', -6)}
    <g font-family="${FONT}" transform="rotate(-6 400 760)">
      <rect x="110" y="680" width="600" height="96" rx="48" fill="#ff3a3a" stroke="${INK}" stroke-width="7"/>
      <text x="410" y="748" font-size="52" text-anchor="middle" fill="#fff">たまごを運べ！</text>
    </g>
  `],

  // サムネイル2：みんなで 大魔竜と戦う
  thumb2_boss: [1920, 1080, `
    <linearGradient id="sky2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a0a2a"/><stop offset="0.7" stop-color="#8a1a2a"/><stop offset="1" stop-color="#ff6a3a"/></linearGradient>
    <rect width="1920" height="1080" fill="url(#sky2)"/>
    ${rays(1350, 450, 20, '#ff9a6a', 0.12)}
    <ellipse cx="1000" cy="930" rx="1100" ry="230" fill="#4a3030"/>
    <ellipse cx="1000" cy="930" rx="800" ry="160" fill="none" stroke="#ff6a3a" stroke-width="16" opacity="0.85"/>
    <circle cx="1380" cy="480" r="460" fill="#ff3a1a" opacity="0.25"/>
    <g transform="translate(1920 0) scale(-1 1)">
      ${use('dragon', 40, -40, 980, '--c:#5a1830;--b:#c06070;--w:#2a0818;--h:#ffd060;--p:#ff2a1a;--angry:1')}
    </g>
    <g stroke-linecap="round">
      <line x1="430" y1="640" x2="1150" y2="430" stroke="#9ae8ff" stroke-width="26" opacity="0.9"/>
      <line x1="360" y1="840" x2="1180" y2="560" stroke="#ffe46a" stroke-width="22" opacity="0.9"/>
      <line x1="620" y1="900" x2="1220" y2="640" stroke="#9aff8a" stroke-width="20" opacity="0.9"/>
    </g>
    <circle cx="1180" cy="530" r="150" fill="url(#glow)"/>
    ${use('dragon', 180, 470, 300, BLUE)}
    ${use('dragon', 90, 700, 280, dragonStyle(DRAGONS[4]))}
    ${use('dragon', 420, 760, 260, dragonStyle(DRAGONS[2]))}
    ${title(80, 190, 130, 'みんなで たおせ！', '#ffffff', 'start', -4)}
    ${title(110, 400, 210, '大魔竜', 'url(#redFill)', 'start', -4)}
  `],

  // サムネイル3：ドラゴン 100種類
  thumb3_collect: [1920, 1080, `
    <linearGradient id="sky3" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffe0f4"/><stop offset="1" stop-color="#c9e8ff"/></linearGradient>
    <rect width="1920" height="1080" fill="url(#sky3)"/>
    ${rays(960, 560, 28, '#ffffff', 0.5)}
    ${DRAGONS.map((d, i) => {
      const col = i % 5, row = Math.floor(i / 5);
      const x = 190 + col * 320, y = 330 + row * 330, stars = 1 + Math.floor(i / 2);
      return `<rect x="${x - 20}" y="${y}" width="270" height="300" rx="34" fill="#fff" stroke="${INK}" stroke-width="6"/>
        <path d="M${x - 20},${y + 238} h270 v28 a34,34 0 0 1 -34,34 h-202 a34,34 0 0 1 -34,-34 Z" fill="${d[2]}" opacity="0.9"/>
        <rect x="${x - 20}" y="${y}" width="270" height="300" rx="34" fill="none" stroke="${INK}" stroke-width="6"/>
        ${use('dragon', x + 8, y + 18, 220, dragonStyle(d))}
        <text x="${x + 115}" y="${y + 284}" font-family="${FONT}" font-size="40" text-anchor="middle" fill="#ffe14a" stroke="${INK}" stroke-width="5" paint-order="stroke">${'★'.repeat(Math.min(stars, 5))}</text>`;
    }).join('')}
    ${title(960, 210, 150, 'ドラゴン 100種類！', 'url(#titleFill)', 'middle', -2)}
  `],
};

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const [name, [w, h, body]] of Object.entries(scenes)) {
    await page.setViewportSize({ width: w, height: h });
    await page.setContent(`<!doctype html><html><head><meta charset="utf-8">
      <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Mochiy+Pop+One&display=block">
      <style>html,body{margin:0;overflow:hidden}svg{display:block}</style></head><body>
      <svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${DEFS}${body}</svg></body></html>`);
    await page.evaluate(async () => {
      const text = [...document.querySelectorAll('text')].map((t) => t.textContent).join('');
      await document.fonts.load('80px "Mochiy Pop One"', text);
      await document.fonts.ready;
    });
    await page.screenshot({ path: path.join(OUT, `${name}.png`) });
    console.log('wrote', name);
  }
  await browser.close();
})();
