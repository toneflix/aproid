import { Downloads } from "./downloads";
import { HttpError } from "./http";
import { LicenceApi } from "./licence/api";
import { SignInCodes } from "./licence/codes";
import { Emails } from "./licence/emails";
import { Licensing } from "./licence/licensing";
import { LogMailer, SendPulseMailer } from "./licence/mailer";
import { PaddleWebhook } from "./licence/paddle";
import { Sessions } from "./licence/sessions";
import { TokenSigner } from "./licence/signer";
import { LicenceStore } from "./licence/store";
import { Router } from "./router";

export interface Env {
  ASSETS: Fetcher;
  RELEASES: R2Bucket;
  LICENCES: D1Database;

  PADDLE_CLIENT_TOKEN?: string;
  PADDLE_PRICE_ID?: string;
  PADDLE_SANDBOX?: string;
  /** Trial length in days, set in the dashboard. */
  TRIAL_DAYS?: string;
  MAIL_FROM: string;
  /** The site's address, for links and images in emails. */
  SITE_URL: string;
  /** Set to "log" in .dev.vars to print sign-in codes instead of emailing them. */
  MAIL_MODE?: string;

  LICENCE_SIGNING_KEY: string;
  CODE_SECRET: string;
  PADDLE_WEBHOOK_SECRET: string;
  PADDLE_API_KEY: string;
  SENDPULSE_API_KEY: string;
}

function router(env: Env): Router {
  const router = new Router();
  const store = new LicenceStore(env.LICENCES);
  const sandbox = env.PADDLE_SANDBOX === "true";
  const mailer = env.MAIL_MODE === "log" ? new LogMailer() : new SendPulseMailer(env.SENDPULSE_API_KEY, env.MAIL_FROM);

  new Downloads(env.RELEASES).register(router);
  new LicenceApi(
    store,
    new Licensing(store, new TokenSigner(env.LICENCE_SIGNING_KEY), Number(env.TRIAL_DAYS) || undefined),
    new SignInCodes(env.LICENCES, mailer, new Emails(env.SITE_URL), env.CODE_SECRET),
    new Sessions(env.LICENCES, store),
    new PaddleWebhook({ webhookSecret: env.PADDLE_WEBHOOK_SECRET, apiKey: env.PADDLE_API_KEY, priceId: env.PADDLE_PRICE_ID ?? "", sandbox }, store),
    { clientToken: env.PADDLE_CLIENT_TOKEN ?? "", priceId: env.PADDLE_PRICE_ID ?? "", sandbox },
  ).register(router);

  return router;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await router(env).handle(request, () => env.ASSETS.fetch(request));
    } catch (error) {
      if (error instanceof HttpError) return error.toResponse();

      console.error(error);

      return Response.json({ error: "server_error" }, { status: 500 });
    }
  },
} satisfies ExportedHandler<Env>;
