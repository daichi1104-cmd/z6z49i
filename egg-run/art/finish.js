// Gemini で作った絵に タイトルの文字をのせて、Roblox の大きさにそろえる：node art/finish.js
// 元の絵は art/gemini/ に置く。できあがりは art/final/
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'gemini');
const OUT = path.join(__dirname, 'final');
const FONT = "'Mochiy Pop One', 'IPAGothic', sans-serif";
const INK = '#1c2340';

const DEFS = `<defs>
  <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff7a8"/><stop offset="0.55" stop-color="#ffd02a"/><stop offset="1" stop-color="#ff8a1a"/></linearGradient>
  <linearGradient id="red" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffd0c0"/><stop offset="0.5" stop-color="#ff4a3a"/><stop offset="1" stop-color="#b0101a"/></linearGradient>
</defs>`;

// 太いふちどりの文字（かげ → 白いふち → 黒いふち → 中の色）
function title(x, y, size, text, fill = 'url(#gold)', anchor = 'start', rot = 0) {
  return `<g transform="rotate(${rot} ${x} ${y})" font-family="${FONT}" font-size="${size}" text-anchor="${anchor}">
    <text x="${x}" y="${y + size * 0.08}" fill="${INK}" stroke="${INK}" stroke-width="${size * 0.32}" stroke-linejoin="round" opacity="0.45">${text}</text>
    <text x="${x}" y="${y}" fill="${fill}" stroke="#fff" stroke-width="${size * 0.3}" stroke-linejoin="round" paint-order="stroke">${text}</text>
    <text x="${x}" y="${y}" fill="${fill}" stroke="${INK}" stroke-width="${size * 0.14}" stroke-linejoin="round" paint-order="stroke">${text}</text>
  </g>`;
}
function badge(cx, cy, w, h, size, text, color = '#ff3a3a', rot = 0) {
  return `<g transform="rotate(${rot} ${cx} ${cy})" font-family="${FONT}">
    <rect x="${cx - w / 2}" y="${cy - h / 2}" width="${w}" height="${h}" rx="${h / 2}" fill="${color}" stroke="${INK}" stroke-width="7"/>
    <text x="${cx}" y="${cy + size * 0.36}" font-size="${size}" text-anchor="middle" fill="#fff">${text}</text>
  </g>`;
}

const W = 1920, H = 1080;
const jobs = [
  // アイコンは 文字をのせず、512×512 のまま
  { name: 'icon', src: 'icon.jpg', w: 512, h: 512, overlay: '' },
  { name: 'thumb1_title', src: 'thumb1.jpg', w: W, h: H, overlay: `
      ${title(60, 230, 150, '爆速', 'url(#gold)', 'start', -5)}
      ${title(80, 400, 120, 'ドラゴニック', 'url(#gold)', 'start', -5)}
      ${title(100, 560, 136, '卵ゲーム', 'url(#gold)', 'start', -5)}
      ${badge(380, 680, 540, 92, 50, 'たまごを運べ！', '#ff3a3a', -5)}` },
  { name: 'thumb2_boss', src: 'thumb2.jpg', w: W, h: H, overlay: `
      ${title(70, 170, 110, 'みんなで たおせ！', '#ffffff', 'start', -3)}
      ${title(100, 380, 190, '大魔竜', 'url(#red)', 'start', -3)}` },
  { name: 'thumb3_collect', src: 'thumb3.jpg', w: W, h: H, overlay: `
      ${title(960, 190, 130, 'ドラゴン 100種類！', 'url(#gold)', 'middle', -2)}` },
];

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const job of jobs) {
    const img = fs.readFileSync(path.join(SRC, job.src)).toString('base64');
    await page.setViewportSize({ width: job.w, height: job.h });
    // 絵は 大きさに合わせて引きのばし、はみ出たところは まん中で切る
    await page.setContent(`<!doctype html><html><head><meta charset="utf-8">
      <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Mochiy+Pop+One&display=block">
      <style>html,body{margin:0;overflow:hidden}
        .bg{position:absolute;inset:0;background:url(data:image/jpeg;base64,${img}) center/cover no-repeat;
            filter:contrast(1.04) saturate(1.05)}
        svg{position:absolute;inset:0}</style></head><body><div class="bg"></div>
      <svg xmlns="http://www.w3.org/2000/svg" width="${job.w}" height="${job.h}">${DEFS}${job.overlay}</svg></body></html>`);
    await page.evaluate(async () => {
      const text = [...document.querySelectorAll('text')].map((t) => t.textContent).join('') || 'あ';
      await document.fonts.load('80px "Mochiy Pop One"', text);
      await document.fonts.ready;
    });
    await page.screenshot({ path: path.join(OUT, `${job.name}.png`) });
    console.log('wrote', job.name);
  }
  await browser.close();
})();
