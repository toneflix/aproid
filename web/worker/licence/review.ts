import type { Settings } from "../settings";
import { sameText } from "./crypto";

/**
 * Lets app store reviewers sign in with a fixed code instead of an emailed one. Only the emails in the
 * `review_emails` setting get it, and only while `REVIEW_CODE` is set and at least 8 characters long.
 */
export class ReviewAccess {
  constructor(
    private readonly settings: Settings,
    private readonly code: string | undefined,
  ) {}

  async covers(email: string): Promise<boolean> {
    return (this.code?.length ?? 0) >= 8 && (await this.settings.list("review_emails")).includes(email);
  }

  async accepts(email: string, code: string): Promise<boolean> {
    return (await this.covers(email)) && sameText(code.trim(), this.code!);
  }
}
