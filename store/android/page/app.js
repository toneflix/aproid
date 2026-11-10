/** Builds the Aproid Android screens as HTML, mirroring the Compose layouts in android/app. */
class AndroidApp {
  constructor(assets, { dark = false, time = '19:31' } = {}) {
    this.assets = assets;
    this.dark = dark;
    this.time = time;
  }

  icon(name) {
    return `<span class="ic">${this.assets.icons[name]}</span>`;
  }

  screen(content, overlay = '') {
    return `<div class="app ${this.dark ? 'dark' : ''}">${this.statusBar()}${content}${overlay}</div>`;
  }

  statusBar() {
    const bars = [5, 7, 9, 12].map((h) => `<i style="height:${h}px"></i>`).join('');

    return `<div class="status"><span class="time">${this.time}</span><span class="icons">${this.icon('wifi')}<span class="signal">${bars}</span><span class="battery"></span></span></div>`;
  }

  home(sections) {
    return `<div class="home">${this.header()}${sections.join('')}</div>`;
  }

  header() {
    return `<div class="header"><img src="${this.assets.mark}"><span class="name">Aproid</span>${this.icon('settings')}</div>`;
  }

  laptop(width, menu = false) {
    const pad = width * 0.028;

    return `<div class="laptop">
      <div class="lid" style="width:${width}px;height:${width * 0.63}px;padding:${pad}px;border-radius:${width * 0.06}px">
        <div class="glass" style="border-radius:${width * 0.035}px">${menu ? '<div class="menu"></div>' : ''}</div>
      </div>
      <div class="base" style="width:${width * 1.17}px;height:${width * 0.055}px;border-radius:0 0 ${width * 0.05}px ${width * 0.05}px"></div>
    </div>`;
  }

  hero(name, text, extraClass = '') {
    return `<div class="hero ${extraClass}">
      <div class="row"><span class="pill"><span class="dot"></span>Connected</span>${this.icon('wifi')}</div>
      <div class="laptop">${this.laptop(180, true)}</div>
      <div><div class="title">${name}</div><div class="text">${text}</div></div>
    </div>`;
  }

  carousel(names) {
    const text = 'Notifications and clipboard go to all your computers';

    return `<div class="carousel">${this.hero(names[0], text)}${this.hero(names[1], text, 'peek')}</div>`;
  }

  tiles() {
    const tiles = [['file-up', 'Send files'], ['clipboard', 'Clipboard'], ['link', 'Open link'], ['cast', 'Mirror']];

    return `<div class="tiles">${tiles.map(([icon, label]) => `<div class="tile"><span class="chip">${this.icon(icon)}</span><span class="label">${label}</span></div>`).join('')}</div>`;
  }

  setupCard(icon, title, hint) {
    return `<div class="setup"><span class="chip">${this.icon(icon)}</span><div class="body"><div class="title">${title}</div><div class="hint">${hint}</div></div><span class="button">Allow</span></div>`;
  }

  recent(items) {
    const rows = items.map((item) => {
      const progress = item.progress != null;
      const bar = progress ? `<div class="progress"><i style="width:${item.progress}%"></i></div>` : '';
      const trailing = progress ? `<span class="percent">${item.progress}%</span>` : `<span class="when">${item.when}</span>`;

      return `<div class="recent"><span class="chip">${this.icon(item.icon)}</span><div class="body"><div class="title">${item.title}</div>${bar}<div class="detail">${item.detail}</div></div>${trailing}</div>`;
    });

    return `<div><div class="section"><span>Recent</span><span class="action">Clear</span></div><div class="list">${rows.join('')}</div></div>`;
  }

  footnote(phone) {
    return `<div class="footnote">This phone: ${phone}</div>`;
  }

  sheet(content) {
    return `<div class="scrim"></div><div class="sheet"><div class="handle"></div>${content}</div>`;
  }

  shareSheet({ title, size, targets }) {
    const rows = targets.map((target) => {
      if (target.progress == null) {
        return `<div class="target">${this.laptop(44)}<div class="body"><div class="row"><span class="name">${target.name}</span></div><div class="detail">Tap to send</div></div></div>`;
      }

      return `<div class="target active">${this.laptop(44)}<div class="body">
        <div class="row"><span class="name">${target.name}</span><span class="percent">${target.progress}%</span></div>
        <div class="progress"><i style="width:${target.progress}%"></i></div>
        <div class="detail">${target.detail}</div>
      </div></div>`;
    });

    return this.sheet(`<div class="share">
      <div class="summary"><span class="chip">${this.icon('image')}</span><div><div class="title">${title}</div><div class="sub">${size}</div></div></div>
      <div class="section" style="padding:0"><span>Send to</span>${targets.some((t) => t.progress == null) ? '<span class="action">Send to all</span>' : ''}</div>
      ${rows.join('')}
      <div class="outlined">Hide</div>
    </div>`);
  }

  pairSheet(name, code) {
    const half = Math.ceil(code.length / 2);
    const digits = [...code].map((c, i) => `${i === half ? '<span class="gap"></span>' : ''}<b>${c}</b>`).join('');

    return this.sheet(`<div class="pair">
      ${this.laptop(150)}
      <div><div class="title">Pair with ${name}?</div><div class="hint">Make sure your computer shows the same code.</div></div>
      <div class="digits">${digits}</div>
      <div class="buttons"><div class="filled">Pair</div><div class="outlined">Not now</div></div>
      <div class="private">${this.icon('lock')}Encrypted, and never leaves your network</div>
    </div>`);
  }

  toast(text) {
    return `<div class="toast"><img src="${this.assets.appIcon}">${text}</div>`;
  }
}
