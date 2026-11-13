import nodemailer, { type Transporter } from "nodemailer";
import { SendPulseTransport } from "nodemailer-sendpulse-transport";

export interface Mailer {
  send(to: string, subject: string, text: string): Promise<void>;
}

/** Sends mail with Nodemailer through SendPulse's SMTP API. */
export class SendPulseMailer implements Mailer {
  private readonly transport: Transporter;

  constructor(
    apiKey: string,
    private readonly from: string,
  ) {
    this.transport = nodemailer.createTransport(new SendPulseTransport({ apiKey }));
  }

  async send(to: string, subject: string, text: string): Promise<void> {
    await this.transport.sendMail({ from: this.from, to, subject, text });
  }
}

/** Prints mail to the log instead of sending it, for local development. */
export class LogMailer implements Mailer {
  async send(to: string, subject: string, text: string): Promise<void> {
    console.log(`Mail to ${to}: ${subject}\n${text}`);
  }
}
