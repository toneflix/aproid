/** A phone frame holding one app screen, scaled from dp to canvas pixels. */
class Phone {
  constructor(screenWidth, screenHeight) {
    this.screenWidth = screenWidth;
    this.screenHeight = screenHeight;
  }

  get scale() {
    return this.screenWidth / 412;
  }

  render(appHtml) {
    const height = this.screenHeight / this.scale;
    const app = appHtml.replace('class="app', `style="height:${height}px;transform:scale(${this.scale})" class="app`);

    const frame = this.screenWidth / 800;

    return `<div class="phone" style="--k:${frame}"><div class="screen" style="width:${this.screenWidth}px;height:${this.screenHeight}px"><div class="camera"></div>${app}</div></div>`;
  }
}

/** One 1080x1920 store screenshot: logo, two-line headline, and the app in a phone. */
class StoreShot {
  constructor({ id, lines, dark = false, screen, extra = () => '' }) {
    this.id = id;
    this.lines = lines;
    this.dark = dark;
    this.screen = screen;
    this.extra = extra;
  }

  render(assets) {
    const app = new AndroidApp(assets, { dark: this.dark });
    const phone = new Phone(800, 1456);

    return `<div class="canvas shot">
      <img class="mark" src="${assets.mark}">
      <div class="headline">${this.lines[0]}<br><span class="accent">${this.lines[1]}</span></div>
      <div class="device">${phone.render(this.screen(app))}</div>
      ${this.extra(assets)}
    </div>`;
  }
}

/** The 1024x500 feature graphic. */
class FeatureGraphic {
  constructor() {
    this.id = 'feature-graphic';
  }

  render(assets) {
    const app = new AndroidApp(assets);
    const phone = new Phone(232, 520);
    const screen = app.screen(app.home([app.hero('MacBook Pro', 'Notifications, clipboard and files are flowing'), app.tiles(), app.flyyDropCard()]));

    return `<div class="canvas feature">
      <div class="glow"></div>
      <div class="laptop-wrap app" style="width:auto;height:auto;background:none">${app.laptop(270, true)}</div>
      <div class="device">${phone.render(screen)}</div>
      <div class="copy">
        <div class="brand"><img src="${assets.mark}"><span>Aproid</span></div>
        <div class="headline">Your Android phone,<br><span class="accent">on your Mac and PC</span></div>
        <div class="sub">FlyyDrop files to anyone nearby, plus<br>texts, calls and notifications.</div>
      </div>
    </div>`;
  }
}

const FLOWING = 'Notifications, clipboard and files are flowing';

const SHOTS = [
  new StoreShot({
    id: '01-home',
    lines: ['Android meets', 'your Mac and PC'],
    screen: (app) => app.screen(app.home([
      app.hero('MacBook Pro', FLOWING),
      app.tiles(),
      app.recent([
        { icon: 'file-text', title: 'Invoice-March.pdf', progress: 72, detail: '3.1 MB of 4.3 MB · 38 MB/s · about 1 second left' },
        { icon: 'image', title: 'IMG_2041.jpg', detail: 'From MacBook Pro · Saved to Downloads', when: '2 min. ago' },
        { icon: 'link', title: 'Link from MacBook Pro', detail: 'From MacBook Pro · Tap to open', when: '5 min. ago' },
      ]),
    ])),
  }),
  new StoreShot({
    id: '02-flyydrop',
    lines: ['FlyyDrop to anyone', 'nearby, no pairing'],
    screen: (app) => app.screen(
      app.home([app.hero('MacBook Pro', FLOWING), app.tiles(), app.flyyDropCard()]),
      app.flyyDropSheet("Ada's Pixel 8", { title: '3 photos · 12.4 MB', detail: 'IMG_2207.jpg, IMG_2208.jpg, IMG_2210.jpg' }),
    ),
  }),
  new StoreShot({
    id: '03-send-files',
    lines: ['Send files', 'without the cable'],
    screen: (app) => app.screen(
      app.home([app.hero('MacBook Pro', FLOWING), app.tiles()]),
      app.shareSheet({
        title: '12 photos',
        size: '48.6 MB',
        targets: [
          { name: 'MacBook Pro', progress: 64, detail: '8 of 12 · 41 MB/s · about 1 second left' },
          { name: 'Work PC' },
        ],
      }),
    ),
  }),
  new StoreShot({
    id: '04-notifications',
    lines: ['Never miss a text', 'while you work'],
    dark: true,
    screen: (app) => app.screen(app.home([
      app.hero('MacBook Pro', FLOWING),
      app.tiles(),
      app.recent([
        { icon: 'image', title: 'Boarding-pass.png', detail: 'From MacBook Pro · Saved to Downloads', when: '12 min. ago' },
        { icon: 'clipboard', title: 'Copied from MacBook Pro', detail: 'Meeting moved to 3pm, same room', when: '20 min. ago' },
      ]),
    ])),
    extra: (assets) => `<div class="banner" style="top:600px;left:390px">
      <span class="icon"><img src="${assets.appIcon}"></span>
      <div class="body"><div class="top"><span>MESSAGES</span><span>now</span></div><div class="title">Mum</div><div class="text">On my way home</div></div>
      <span class="reply">Reply</span>
    </div>`,
  }),
  new StoreShot({
    id: '05-clipboard',
    lines: ['Copy here,', 'paste there'],
    screen: (app) => app.screen(
      app.home([
        app.hero('Work PC', FLOWING),
        app.tiles(),
        app.recent([
          { icon: 'clipboard', title: 'Copied from Work PC', detail: 'Wi-Fi password: blue-lagoon-42', when: '1 min. ago' },
        ]),
      ]),
      app.toast('Clipboard sent to your computer'),
    ),
  }),
  new StoreShot({
    id: '06-many-computers',
    lines: ['One phone,', 'all your computers'],
    dark: true,
    screen: (app) => app.screen(app.home([
      app.carousel(['MacBook Pro', 'Work PC']),
      app.tiles(),
      app.recent([
        { icon: 'file-text', title: 'Q3-report.xlsx', detail: 'From Work PC · Saved to Downloads', when: '3 min. ago' },
        { icon: 'image', title: 'Screenshot 2026-11-10.png', detail: 'From MacBook Pro · Saved to Downloads', when: '8 min. ago' },
      ]),
    ])),
  }),
  new StoreShot({
    id: '07-pair',
    lines: ['Pair once,', 'stay connected'],
    screen: (app) => app.screen(
      app.home([app.hero('Work PC', FLOWING), app.tiles()]),
      app.pairSheet('Work PC', '4F7A2C91'),
    ),
  }),
];

const GRAPHICS = [new FeatureGraphic(), ...SHOTS];
