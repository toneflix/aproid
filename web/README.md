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
- **Licences** live in the `aproid-licences` D1 database (`migrations/`). People buy through Paddle; its webhook (`/api/paddle/webhook`, events `transaction.completed`, `adjustment.created`, `adjustment.updated`) adds or revokes the licence. They sign in with a code emailed through SendPulse (Nodemailer with `nodemailer-sendpulse-transport`), on the site and in the computer apps.
- A computer that signs in gets a token signed with `LICENCE_SIGNING_KEY`, which the app checks offline and renews every day. Rules (5 computers, 3 removals a month, 14-day trial, 30 days offline plus 7 of grace) are in `worker/licence/licensing.ts`.

Setup, once (run the `wrangler` commands from `web/`):

1. **Licence keys.** Run `node scripts/licence-keys.mjs`. Put the private key in the worker with `npx wrangler secret put LICENCE_SIGNING_KEY`, and add the public key as the `LICENCE_PUBLIC_KEY` variable under GitHub > Settings > Secrets and variables > Actions > Variables. Release builds of the Mac and Windows apps only check licences when this variable is set.
2. **Paddle.** Under Catalog, add a product with one one-time price, and put its `pri_…` ID in `PADDLE_PRICE_ID` in `wrangler.jsonc`. Under Developer tools:
   - Authentication: make a client-side token for `PADDLE_CLIENT_TOKEN` in `wrangler.jsonc`, and an API key with customer read access for `npx wrangler secret put PADDLE_API_KEY`.
   - Notifications: add a destination for `https://aproid.toneflix.com/api/paddle/webhook` with the events `transaction.completed`, `adjustment.created` and `adjustment.updated`. Put its secret key in `npx wrangler secret put PADDLE_WEBHOOK_SECRET`.
   - Checkout settings: approve `aproid.toneflix.com` as a website, and set the default payment link to `https://aproid.toneflix.com/buy`.
   - Start with a sandbox account (`PADDLE_SANDBOX` set to `"true"`). When going live, repeat the steps in the live account and set it to `"false"`.
3. **SendPulse.** Under Settings > API, copy the ID and secret into `npx wrangler secret put SENDPULSE_CLIENT_ID` and `SENDPULSE_CLIENT_SECRET`. Under SMTP, verify the `MAIL_FROM` sender in `wrangler.jsonc`.
4. **Sign-in codes.** `npx wrangler secret put CODE_SECRET` with any long random text.
5. **Cloudflare deploys.** In the worker's Settings > Build, set the deploy command to `npx wrangler d1 migrations apply aproid-licences --remote && npx wrangler deploy` so new migrations run before each deploy.
6. **Release uploads.** Make a Cloudflare API token with Workers R2 Storage edit access, and add it with your account ID as the `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets under GitHub > Settings > Secrets and variables > Actions.

Going live, in this order:

1. Merge the licence PRs and let Cloudflare deploy the site.
2. Buy a licence in the Paddle sandbox and sign in on a Mac and a PC to check the whole flow.
3. Switch Paddle to live (step 2 above).
4. Tag a release. It uploads to R2 and builds the apps with the licence key, and installed copies update from the website from then on.
5. Make the GitHub repo private. Copies installed before step 4 can no longer update after this.

For local work, copy `.dev.vars.example` to `.dev.vars`; sign-in codes are printed instead of emailed.
