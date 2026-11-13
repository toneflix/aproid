// Renders the Google Play feature graphic and phone screenshots from page/.
// Run from this folder: npm install && npm run generate
import { readFileSync, readdirSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '../..');
const { chromium } = createRequire(import.meta.url)('playwright');

/** The logo, app icon and Lucide icons the app uses, read from the repo so they stay in sync. */
class Assets {
  constructor(root) {
    this.root = root;
  }

  load() {
    return {
      mark: this.dataUrl(join(this.root, 'branding/flyylink-mark.svg'), 'image/svg+xml'),
      appIcon: this.dataUrl(join(this.root, 'branding/play-store-icon.png'), 'image/png'),
      icons: this.lucideIcons(join(this.root, 'android/app/src/main/res/drawable')),
    };
  }

  dataUrl(path, type) {
    return `data:${type};base64,${readFileSync(path).toString('base64')}`;
  }

  lucideIcons(folder) {
    const icons = {};

    for (const file of readdirSync(folder).filter((name) => name.startsWith('lucide_'))) {
      const name = file.slice('lucide_'.length, -'.xml'.length).replaceAll('_', '-');
      icons[name] = this.vectorToSvg(readFileSync(join(folder, file), 'utf8'));
    }

    return icons;
  }

  /** Turns an Android vector drawable of stroked or filled paths into inline SVG. */
  vectorToSvg(xml) {
    const paths = [...xml.matchAll(/<path([\s\S]*?)\/>/g)].map(([, attrs]) => {
      const d = attrs.match(/android:pathData="([^"]+)"/)[1];
      const stroked = attrs.includes('android:strokeColor');
      const filled = attrs.includes('android:fillColor');

      return `<path d="${d}" fill="${filled ? 'currentColor' : 'none'}" stroke="${stroked ? 'currentColor' : 'none'}"/>`;
    });

    return `<svg viewBox="0 0 24 24" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${paths.join('')}</svg>`;
  }
}

/** Screenshots each graphic in page/index.html at its canvas size. */
class Renderer {
  constructor(assets, outputs) {
    this.assets = assets;
    this.outputs = outputs;
  }

  async run() {
    const browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
    const index = pathToFileURL(join(HERE, 'page/index.html'));

    await page.addInitScript((assets) => { window.ASSETS = assets; }, this.assets);
    await page.goto(index.href);
    const ids = await page.evaluate(() => GRAPHICS.map((graphic) => graphic.id));

    for (const id of ids) {
      await page.goto(`${index}?graphic=${id}`);
      await page.evaluate(() => document.fonts.ready);

      const out = this.outputs(id);
      await page.locator('.canvas').screenshot({ path: out });
      console.log(`wrote ${out}`);
    }

    await browser.close();
  }
}

const assets = new Assets(ROOT).load();

mkdirSync(join(HERE, 'screenshots'), { recursive: true });

await new Renderer(assets, (id) => join(HERE, id === 'feature-graphic' ? 'feature-graphic.png' : `screenshots/${id}.png`)).run();
