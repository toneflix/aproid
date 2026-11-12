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

Screenshots are in `public/screens`. The Mac ones (`mac-panel.png`, `mac-overview.png`) are drawn by `screens/generate.mjs` (`node screens/generate.mjs` after `npm install`, with Playwright installed); the Android ones come from `store/android`. The app icon is copied from `branding/app-icon.svg`.

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

## Downloads and licences

The worker in `worker/` runs before the static files for `/download/*`, `/releases/*`, `/updates/*` and `/api/*`.

- **Downloads** come from the `aproid-releases` R2 bucket, which the release workflow fills.
- **Licences** live in the `aproid-licences` D1 database (`migrations/`). People buy through Paddle; its webhook (`/api/paddle/webhook`, events `transaction.completed`, `adjustment.created`, `adjustment.updated`) adds or revokes the licence. They sign in with a code sent by email, on the site and in the computer apps.
- A computer that signs in gets a token signed with `LICENCE_SIGNING_KEY`, which the app checks offline and renews every day. Rules (5 computers, 3 removals a month, 14-day trial, 30 days offline plus 7 of grace) are in `worker/licence/licensing.ts`.

Setup, once:

1. `node scripts/licence-keys.mjs`, then `npx wrangler secret put LICENCE_SIGNING_KEY` with the private key, and add the public key as the `LICENCE_PUBLIC_KEY` variable in the GitHub repo settings.
2. `npx wrangler secret put` for `CODE_SECRET` (any long random text), `PADDLE_WEBHOOK_SECRET`, `PADDLE_API_KEY` and `RESEND_API_KEY`.
3. Fill `PADDLE_CLIENT_TOKEN` and `PADDLE_PRICE_ID` in `wrangler.jsonc`, and set `PADDLE_SANDBOX` to `"false"` when going live.
4. Set the Cloudflare deploy command to `npx wrangler d1 migrations apply aproid-licences --remote && npx wrangler deploy` so new migrations run before each deploy.

For local work, copy `.dev.vars.example` to `.dev.vars`; sign-in codes are printed instead of emailed.
