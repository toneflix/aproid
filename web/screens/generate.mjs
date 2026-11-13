// Renders the Mac screenshots in ../public/screens from panel.css.
// Run from web/ after npm install, with Playwright installed: node screens/generate.mjs
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import * as lucide from 'lucide-react';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '../public/screens');
const { chromium } = createRequire(import.meta.url)('playwright');

/** The Mac menu bar panel, built from the same parts and copy as macos/Sources/FlyyLink/Views. */
class MacPanel {
  constructor(appIcon) {
    this.appIcon = appIcon;
  }

  icon(name) {
    return renderToStaticMarkup(createElement(lucide[name], { className: 'i' }));
  }

  tile(icon, title, subtitle, extra = '', chip = '') {
    const sub = subtitle ? `<div class="s">${subtitle}</div>` : '';

    return `<div class="card tile"><span class="chip ${chip}">${this.icon(icon)}</span><div><div class="t">${title}</div>${sub}</div>${extra}</div>`;
  }

  ring(charge) {
    const length = 2 * Math.PI * 23.5;

    return `<div class="ring"><svg viewBox="0 0 52 52"><circle cx="26" cy="26" r="23.5" fill="none" stroke="rgba(0,0,0,0.1)" stroke-width="5"/><circle cx="26" cy="26" r="23.5" fill="none" stroke="#127A4E" stroke-width="5" stroke-linecap="round" stroke-dasharray="${length * charge / 100} ${length}"/></svg>${charge}%</div>`;
  }

  render() {
    return `<div class="panel">
      <div class="header"><img src="${this.appIcon}"><b>FlyyLink</b>${this.icon('Settings')}</div>
      <div class="carousel">
        <div class="hero">
          <div class="phone-art"><div></div></div>
          <div class="info">
            <div class="name">Tecno Camon 30</div>
            <div class="pill"><span class="dot"></span>Connected${this.icon('Wifi')}</div>
            <div class="status"><span>${this.icon('Bell')}</span><span>${this.icon('Clipboard')}</span></div>
          </div>
          ${this.ring(82)}
        </div>
        <div class="peek"></div>
      </div>
      <div class="grid">
        ${this.tile('Volume2', 'Ring phone')}
        ${this.tile('FileUp', 'Send file')}
        ${this.tile('Clipboard', 'Clipboard', 'Synced 1 min ago')}
        ${this.tile('BellRing', 'Notifications', '14 today')}
        ${this.tile('MessageSquare', 'Messages', '3 unread')}
        ${this.tile('Phone', 'Call')}
        ${this.tile('Cast', 'Mirror')}
        ${this.tile('Images', 'Photos')}
      </div>
      ${this.tile('Headphones', 'Call audio', 'Calls play on this Mac', '<span class="toggle"></span>', 'green')}
      <div class="drop">${this.icon('Download')}Drop files to send</div>
      <div class="label">ALSO NEARBY</div>
      <div class="card nearby"><span class="tablet"></span><div class="t">Galaxy Tab S9<div class="s">Not paired</div></div><span class="pair">Pair</span></div>
      <div class="footer"><span>This Mac: MacBook Pro</span><a>Quit</a></div>
    </div>`;
  }
}

const dataUrl = (path, type) => `data:${type};base64,${readFileSync(path).toString('base64')}`;
const panel = new MacPanel(dataUrl(join(HERE, '../../branding/app-icon.svg'), 'image/svg+xml')).render();
const css = readFileSync(join(HERE, 'panel.css'), 'utf8');
const font = '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">';

const overview = `<div class="overview">${panel}<div class="side">
  <img src="${dataUrl(join(OUT, 'call-card.png'), 'image/png')}" width="570">
  <img src="${dataUrl(join(OUT, 'messages.png'), 'image/png')}" width="780">
</div></div>`;

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });

for (const [file, html, selector, scale] of [['mac-panel.png', panel, '.panel', 2], ['mac-overview.png', overview, '.overview', 1]]) {
  await page.setViewportSize({ width: 1700, height: 1300 });
  await page.setContent(`<html><head>${font}<style>${css}</style></head><body>${html}</body></html>`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.locator(selector).screenshot({ path: join(OUT, file), omitBackground: true, scale: scale === 1 ? 'css' : 'device' });
  console.log(`wrote ${file}`);
}

await browser.close();
