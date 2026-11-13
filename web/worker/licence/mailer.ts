import nodemailer, { type Transporter } from "nodemailer";
import { SendPulseTransport } from "nodemailer-sendpulse-transport";

export interface Mailer {
  send(to: string, subject: string, text: string): Promise<void>;
}

/**
 * Sends mail with Nodemailer through SendPulse's SMTP API. The transport is made on the first send,
 * because it throws without a key and the worker builds this for every request, downloads included.
 */
export class SendPulseMailer implements Mailer {
  private transport?: Transporter;

  constructor(
    private readonly apiKey: string | undefined,
    private readonly from: string,
  ) {}

  async send(to: string, subject: string, text: string): Promise<void> {
    if (!this.apiKey) throw new Error("SENDPULSE_API_KEY is not set");

    this.transport ??= nodemailer.createTransport(new SendPulseTransport({ apiKey: this.apiKey }));
    await this.transport.sendMail({ from: this.from, to, subject, text });
  }
}

/** Prints mail to the log instead of sending it, for local development. */
export class LogMailer implements Mailer {
  async send(to: string, subject: string, text: string): Promise<void> {
    console.log(`Mail to ${to}: ${subject}\n${text}`);
  }
}
