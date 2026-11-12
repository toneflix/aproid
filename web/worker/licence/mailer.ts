export interface Mailer {
  send(to: string, subject: string, text: string): Promise<void>;
}

/** Sends mail through Resend's HTTP API. */
export class ResendMailer implements Mailer {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
  ) {}

  async send(to: string, subject: string, text: string): Promise<void> {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: this.from, to, subject, text }),
    });

    if (!response.ok) throw new Error(`Resend answered ${response.status}: ${await response.text()}`);
  }
}

/** Prints mail to the log instead of sending it, for local development. */
export class LogMailer implements Mailer {
  async send(to: string, subject: string, text: string): Promise<void> {
    console.log(`Mail to ${to}: ${subject}\n${text}`);
  }
}
