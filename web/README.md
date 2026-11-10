# Aproid website

The marketing site and the privacy and terms pages, built with Next.js as a static export and served by Cloudflare Workers.

```sh
npm install
npm run dev       # http://localhost:3000
npm run build     # static site in out/
npm run preview   # build and serve it with Wrangler, as Cloudflare would
npm run deploy    # build and deploy from this machine (runs `wrangler login` the first time)
```

Copy lives in `content/`: `site.ts` holds links, the legal entity and contact details, and `features.ts` holds the feature list. Keep it in step with the main README.

Screenshots are in `public/screens`. The app icon is copied from `branding/app-icon.svg`.

## Deploying with Cloudflare

Cloudflare builds and deploys the site on every push to `main`. To set it up, open **Workers & Pages > Create > Import a repository** in the Cloudflare dashboard, pick `toneflix/aproid`, and fill in:

| Setting | Value |
| --- | --- |
| Project name | `aproid-web` (must match `name` in `wrangler.jsonc`) |
| Build command | `npm run build` |
| Deploy command | `npx wrangler deploy` |
| Root directory | `web` |

Under **Advanced settings**, set **Build watch paths** to `web/*` so changes to the apps don't rebuild the site. Pull requests get a preview build automatically.

When it's live, add a custom domain under the Worker's **Settings > Domains & Routes**, then update `url` in `content/site.ts`.
