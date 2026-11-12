import { HttpError } from "../http";
import { hmac, sameText } from "./crypto";
import type { LicenceStore } from "./store";

const provider = "paddle";
const maxSkew = 5 * 60;

interface PaddleEvent {
  event_type: string;
  data: {
    id: string;
    status?: string;
    action?: string;
    customer_id?: string;
    transaction_id?: string;
    items?: { price?: { id?: string }; price_id?: string }[];
  };
}

export interface PaddleConfig {
  webhookSecret: string;
  apiKey: string;
  priceId: string;
  sandbox: boolean;
}

/** Turns Paddle's webhooks into licences: a completed purchase adds one, a refund or chargeback revokes it. */
export class PaddleWebhook {
  constructor(
    private readonly config: PaddleConfig,
    private readonly store: LicenceStore,
  ) {}

  async handle(request: Request, now: number): Promise<Response> {
    const body = await request.text();
    await this.verify(request.headers.get("Paddle-Signature") ?? "", body, now);

    const event = JSON.parse(body) as PaddleEvent;
    switch (event.event_type) {
      case "transaction.completed":
        await this.purchased(event, now);
        break;
      case "adjustment.created":
      case "adjustment.updated":
        await this.adjusted(event);
        break;
    }

    return new Response(null, { status: 204 });
  }

  private async purchased(event: PaddleEvent, now: number): Promise<void> {
    const { id, customer_id: customerId, items = [] } = event.data;
    if (!customerId || !items.some((item) => (item.price?.id ?? item.price_id) === this.config.priceId)) return;

    const account = await this.store.accountFor(await this.email(customerId), now);
    await this.store.addLicence(account.id, provider, id, now);
  }

  private async adjusted(event: PaddleEvent): Promise<void> {
    const { action, status, transaction_id: transactionId } = event.data;
    if (!transactionId || status !== "approved" || (action !== "refund" && action !== "chargeback")) return;

    await this.store.setLicenceStatus(provider, transactionId, "revoked");
  }

  private async email(customerId: string): Promise<string> {
    const host = this.config.sandbox ? "https://sandbox-api.paddle.com" : "https://api.paddle.com";
    const response = await fetch(`${host}/customers/${customerId}`, { headers: { Authorization: `Bearer ${this.config.apiKey}` } });
    if (!response.ok) throw new Error(`Paddle answered ${response.status} for customer ${customerId}`);

    const { data } = (await response.json()) as { data: { email: string } };

    return data.email.trim().toLowerCase();
  }

  private async verify(header: string, body: string, now: number): Promise<void> {
    const parts = Object.fromEntries(header.split(";").map((part) => part.split("=") as [string, string]));
    const timestamp = Number(parts.ts);
    if (!parts.h1 || !Number.isFinite(timestamp) || Math.abs(now - timestamp) > maxSkew) throw new HttpError(401, "bad_signature");

    const expected = await hmac(this.config.webhookSecret, `${parts.ts}:${body}`);
    if (!sameText(expected, parts.h1)) throw new HttpError(401, "bad_signature");
  }
}
