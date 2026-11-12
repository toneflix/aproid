import type { CheckoutConfig } from "./api";

interface PaddleEvent {
  name: string;
  data?: { customer?: { email?: string } };
}

interface PaddleGlobal {
  Environment: { set(env: string): void };
  Initialize(options: { token: string; eventCallback(event: PaddleEvent): void }): void;
  Checkout: { open(options: { items: { priceId: string; quantity: number }[] }): void };
  PricePreview(request: { items: { priceId: string; quantity: number }[] }): Promise<{
    data: { details: { lineItems: { formattedTotals: { total: string } }[] } };
  }>;
}

declare global {
  interface Window {
    Paddle?: PaddleGlobal;
  }
}

let loading: Promise<PaddleGlobal> | undefined;

/** Loads Paddle.js once and opens its checkout for the lifetime price. */
export class PaddleCheckout {
  private onDone: (email?: string) => void = () => {};

  constructor(private readonly config: CheckoutConfig) {}

  async price(): Promise<string | undefined> {
    const paddle = await this.load();
    const preview = await paddle.PricePreview({ items: [{ priceId: this.config.priceId, quantity: 1 }] });

    return preview.data.details.lineItems[0]?.formattedTotals.total;
  }

  async open(onDone: (email?: string) => void): Promise<void> {
    this.onDone = onDone;
    (await this.load()).Checkout.open({ items: [{ priceId: this.config.priceId, quantity: 1 }] });
  }

  private load(): Promise<PaddleGlobal> {
    loading ??= new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "https://cdn.paddle.com/paddle/v2/paddle.js";
      script.onerror = () => reject(new Error("Paddle didn't load"));
      script.onload = () => {
        const paddle = window.Paddle!;
        if (this.config.sandbox) paddle.Environment.set("sandbox");
        paddle.Initialize({
          token: this.config.clientToken,
          eventCallback: (event) => {
            if (event.name === "checkout.completed") this.onDone(event.data?.customer?.email);
          },
        });
        resolve(paddle);
      };
      document.head.append(script);
    });

    return loading;
  }
}
