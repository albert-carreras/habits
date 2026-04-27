import puppeteer from 'puppeteer';
import { dirname, resolve } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const W = 1242;
const H = 2688;

const browser = await puppeteer.launch({ headless: true });
const page = await browser.newPage();
await page.setViewport({ width: W, height: H * 4, deviceScaleFactor: 1 });

const filePath = `file://${resolve(__dirname, 'screenshots-en.html')}`;
await page.goto(filePath, { waitUntil: 'networkidle0' });

await page.addStyleTag({
  content: '@media screen { .page { transform: none !important; margin-bottom: 0 !important; } }',
});

await page.evaluateHandle('document.fonts.ready');

const slides = await page.$$('.page');
for (let i = 0; i < slides.length; i += 1) {
  const box = await slides[i].boundingBox();
  const out = resolve(__dirname, `screenshot-${i + 1}.png`);
  await page.screenshot({
    path: out,
    clip: { x: box.x, y: box.y, width: W, height: H },
  });
  console.log(`Saved ${out}`);
}

await page.close();
await browser.close();
