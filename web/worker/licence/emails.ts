/** One email, with the HTML version and the plain text one that goes alongside it. */
export interface Email {
  subject: string;
  text: string;
  html: string;
}

const colors = { bg: "#fbf8f1", surface: "#ffffff", text: "#17140d", muted: "#5f5a4f", line: "#e7e0cf", gold: "#f6c101" };
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
        `<p style="margin:0 0 20px;font-size:16px;line-height:24px;color:${colors.text};">Your sign-in code:</p>
        <p style="margin:0 0 20px;padding:18px 0 18px 10px;border-radius:14px;background:${colors.bg};border:1px solid ${colors.line};text-align:center;font-size:36px;line-height:40px;font-weight:700;letter-spacing:10px;color:${colors.text};font-family:${font};">${code}</p>
        <p style="margin:0;font-size:14px;line-height:22px;color:${colors.muted};">It works for ${minutes} minutes.</p>`,
      ),
    };
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
          <td style="padding:0 4px 24px;">
            <img src="${site}/email/icon.png" width="44" height="44" alt="" style="display:inline-block;vertical-align:middle;border:0;">
            <span style="display:inline-block;vertical-align:middle;margin-left:10px;font-size:20px;font-weight:700;color:${colors.text};">FlyyLink</span>
          </td>
        </tr>
        <tr>
          <td style="padding:32px;background:${colors.surface};border:1px solid ${colors.line};border-top:4px solid ${colors.gold};border-radius:22px;">
            ${body}
          </td>
        </tr>
        <tr>
          <td style="padding:24px 4px 0;font-size:12px;line-height:18px;color:${colors.muted};">
            <a href="${site}" style="color:${colors.muted};text-decoration:underline;">FlyyLink</a> by Toneflix Technologies Limited
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
