import { sameText } from "./crypto";

/**
 * Lets app store reviewers sign in with a fixed code instead of an emailed one. Only the emails listed in
 * `REVIEW_EMAILS` get it, and only while `REVIEW_CODE` is set and at least 8 characters long.
 */
export class ReviewAccess {
  private readonly emails: Set<string>;

  constructor(
    emails: string | undefined,
    private readonly code: string | undefined,
  ) {
    this.emails = new Set((emails ?? "").split(",").map((email) => email.trim().toLowerCase()).filter(Boolean));
  }

  covers(email: string): boolean {
    return (this.code?.length ?? 0) >= 8 && this.emails.has(email);
  }

  accepts(email: string, code: string): boolean {
    return this.covers(email) && sameText(code.trim(), this.code!);
  }
}
