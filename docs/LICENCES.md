# Licences

The Android app is free. The Mac and Windows apps need a lifetime licence after a 14-day trial. How the apps check it is in [ARCHITECTURE.md](ARCHITECTURE.md#licence).

## How it works

- **Licences** live in the `flyylink-licences` D1 database (`web/migrations/`). People buy through Paddle; its webhook (`/api/paddle/webhook`, events `transaction.completed`, `adjustment.created`, `adjustment.updated`) adds or revokes the licence.
- **Sign-in** uses a code emailed through SendPulse (Nodemailer with `nodemailer-sendpulse-transport`), on the site and in the computer apps.
- **Computers** that sign in get a token signed with `LICENCE_SIGNING_KEY`, which the app checks offline and renews every few hours.
- **Rules** (5 computers, 3 removals a month, 14-day trial, 30 days offline plus 7 of grace) are in `web/worker/licence/licensing.ts`.

## Setup, once

Run the `wrangler` commands from `web/`.

1. **Licence keys.** Run `node scripts/licence-keys.mjs`. Put the private key in the worker with `npx wrangler secret put LICENCE_SIGNING_KEY`, and add the public key as the `LICENCE_PUBLIC_KEY` variable under GitHub > Settings > Secrets and variables > Actions > Variables. Release builds of the Mac and Windows apps only check licences when this variable is set.
2. **Paddle.** Under Catalog, add a product with one one-time price, and add its `pri_…` ID as the `PADDLE_PRICE_ID` variable under the worker's Settings > Variables and Secrets. Under Developer tools:
   - Authentication: make a client-side token and add it as the `PADDLE_CLIENT_TOKEN` variable the same way, and an API key with customer read access for `npx wrangler secret put PADDLE_API_KEY`.
   - Notifications: add a destination for `https://flyylink.toneflix.net/api/paddle/webhook` with the events `transaction.completed`, `adjustment.created` and `adjustment.updated`. Put its secret key in `npx wrangler secret put PADDLE_WEBHOOK_SECRET`.
   - Checkout settings: approve `flyylink.toneflix.net` as a website, and set the default payment link to `https://flyylink.toneflix.net/buy`.
   - Start with a sandbox account (`PADDLE_SANDBOX` set to `"true"`). When going live, repeat the steps in the live account and set it to `"false"`.
3. **SendPulse.** Under Settings > API, make an API key and put it in `npx wrangler secret put SENDPULSE_API_KEY`. Under SMTP, verify the `MAIL_FROM` sender in `wrangler.jsonc`.
4. **Trial length (optional).** Add a `TRIAL_DAYS` variable under the worker's Settings > Variables and Secrets to change the 14 days. It applies to computers that start a trial after the change; trials already running keep their end date. The apps only use their own 14 days until they first reach the server.
5. **Sign-in codes.** `npx wrangler secret put CODE_SECRET` with any long random text.
6. **Cloudflare deploys.** Use the deploy command in [WEBSITE.md](WEBSITE.md) so new migrations run before each deploy.
7. **Release uploads.** Add the Cloudflare secrets listed in [RELEASING.md](RELEASING.md).

## Going live, in this order

1. Let Cloudflare deploy the site with the licence server.
2. Buy a licence in the Paddle sandbox and sign in on a Mac and a PC to check the whole flow.
3. Switch Paddle to live (step 2 above).
4. Tag a release. It uploads to R2 and builds the apps with the licence key, and installed copies update from the website from then on.
5. Make the GitHub repo private. Copies installed before step 4 can no longer update after this.

## Local testing

Copy `web/.dev.vars.example` to `web/.dev.vars` and run `npm run preview`. Sign-in codes are printed instead of emailed.
