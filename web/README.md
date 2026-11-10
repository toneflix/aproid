# Aproid website

The marketing site and the privacy and terms pages, built with Next.js as a static export and served by Cloudflare Workers.

```sh
npm install
npm run dev       # http://localhost:3000
npm run build     # static site in out/
npm run preview   # build and serve it with Wrangler, as Cloudflare would
npm run deploy    # build and deploy to Cloudflare (runs `wrangler login` the first time)
```

Copy lives in `content/`: `site.ts` holds links, the legal entity and contact details, and `features.ts` holds the feature list. Keep it in step with the main README.

Screenshots are in `public/screens`. The app icon is copied from `branding/app-icon.svg`.

## Deploying from GitHub

`.github/workflows/web.yml` builds the site on every pull request that touches `web/` and deploys it when `main` changes. Add these repository secrets to turn deploys on:

- `CLOUDFLARE_API_TOKEN`: a token with the "Edit Cloudflare Workers" template.
- `CLOUDFLARE_ACCOUNT_ID`: your Cloudflare account ID.

The Worker is called `aproid-web` (see `wrangler.jsonc`). Add a custom domain to it in the Cloudflare dashboard, then update `url` in `content/site.ts`.
