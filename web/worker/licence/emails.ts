/** One email, with the HTML version and the plain text one that goes alongside it. */
export interface Email {
  subject: string;
  text: string;
  html: string;
}

const colors = {
  bg: "#fbf8f1",
  surface: "#ffffff",
  text: "#17140d",
  muted: "#5f5a4f",
  line: "#e7e0cf",
  cyan: "#00afff",
  cyanInk: "#0077b6",
  cyanTint: "#e8f8ff",
  gold: "#f6c101",
  gold2: "#bb8c01",
  goldText: "#1d1500",
};
const font = "'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

/** Builds the emails the site sends, in the site's colours, with inline styles and tables so mail apps keep the layout. */
export class Emails {
  constructor(private readonly siteUrl: string) {}

  signInCode(code: string, minutes: number): Email {
    return {
      subject: `${code} is your FlyyLink code`,
      text: `Your FlyyLink sign-in code is ${code}.\n\nIt works for ${minutes} minutes.`,
      html: this.layout(
        `Your code is ${code}`,
        `<p style="margin:0 0 6px;font-size:22px;line-height:30px;font-weight:800;color:${colors.text};">Your sign-in code</p>
        <p style="margin:0 0 24px;font-size:15px;line-height:22px;color:${colors.muted};">It works for ${minutes} minutes.</p>
        <p style="margin:0;padding:20px 0 20px 12px;border-radius:16px;background:${colors.cyanTint};border:2px solid ${colors.cyan};text-align:center;font-size:38px;line-height:44px;font-weight:800;letter-spacing:12px;color:${colors.cyanInk};font-family:${font};">${code}</p>`,
      ),
    };
  }

  /** A message from the FlyyLink team, with paragraphs and an optional button. */
  notice(subject: string, paragraphs: string[], link?: { url: string; text: string }): Email {
    const button = link
      ? `<p style="margin:8px 0 0;"><a href="${Emails.escape(link.url)}" style="display:inline-block;padding:12px 22px;border-radius:12px;background:${colors.cyan};color:${colors.surface};font-size:15px;font-weight:700;text-decoration:none;">${Emails.escape(link.text)}</a></p>`
      : "";
    const text = [...paragraphs, ...(link ? [`${link.text}: ${link.url}`] : [])].join("\n\n");

    return {
      subject,
      text,
      html: this.layout(
        Emails.escape(paragraphs[0] ?? subject),
        `<p style="margin:0 0 16px;font-size:22px;line-height:30px;font-weight:800;color:${colors.text};">${Emails.escape(subject)}</p>
        ${paragraphs.map((paragraph) => `<p style="margin:0 0 16px;font-size:15px;line-height:24px;color:${colors.muted};">${Emails.escape(paragraph)}</p>`).join("\n        ")}
        ${button}`,
      ),
    };
  }

  private static escape(text: string): string {
    return text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
  }

  private layout(preview: string, body: string): string {
    const site = this.siteUrl.replace(/\/$/, "");

    return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light only">
<title>FlyyLink</title>
</head>
<body style="margin:0;padding:0;background:${colors.bg};font-family:${font};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${preview}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${colors.bg};">
  <tr>
    <td align="center" style="padding:40px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
        <tr>
          <td bgcolor="${colors.gold}" style="padding:22px 28px;border-radius:22px 22px 0 0;background:${colors.gold};background-image:linear-gradient(180deg, ${colors.gold}, ${colors.gold2});">
            <span style="display:inline-block;vertical-align:middle;width:44px;height:44px;border-radius:12px;background:${colors.surface};text-align:center;line-height:44px;"><img src="${site}/email/mark.png" width="30" height="30" alt="" style="display:inline-block;vertical-align:middle;border:0;"></span>
            <span style="display:inline-block;vertical-align:middle;margin-left:12px;font-size:20px;font-weight:800;letter-spacing:0.5px;color:${colors.goldText};">FlyyLink</span>
          </td>
        </tr>
        <tr>
          <td style="padding:32px 28px;background:${colors.surface};border:1px solid ${colors.line};border-top:0;border-radius:0 0 22px 22px;">
            ${body}
          </td>
        </tr>
        <tr>
          <td style="padding:24px 4px 0;font-size:12px;line-height:18px;color:${colors.muted};">
            <a href="${site}" style="color:${colors.cyanInk};text-decoration:none;font-weight:600;">FlyyLink</a> by Toneflix Technologies Limited
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
  }
}
