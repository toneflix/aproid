# FlyyLink website

The marketing site and the privacy and terms pages, built with Next.js as a static export and served by Cloudflare Workers.

```sh
npm install
npm run dev       # http://localhost:3000
npm run build     # static site in out/
npm run preview   # build and serve it with Wrangler, as Cloudflare would
npm run deploy    # build and deploy from this machine (runs `wrangler login` the first time)
```

Copy lives in `content/`: `site.ts` holds links, the legal entity and contact details, and `features.ts` holds the feature list. Keep it in step with the main README.

Screenshots are in `public/screens`. The Mac ones (`mac-panel.png`, `mac-overview.png`) are drawn by `screens/generate.mjs` (`node screens/generate.mjs` after `npm install`, with Playwright installed); the Android ones come from `store/android`. The app icon is copied from `branding/app-icon.svg`.

For local licence testing, copy `.dev.vars.example` to `.dev.vars`; sign-in codes are printed instead of emailed.

## More

- [docs/WEBSITE.md](../docs/WEBSITE.md): Cloudflare hosting and the worker.
- [docs/LICENCES.md](../docs/LICENCES.md): selling licences, setup and going live.
- [docs/RELEASING.md](../docs/RELEASING.md): how releases reach the site.
