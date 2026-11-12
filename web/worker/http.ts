/** An error that becomes a JSON response with its status and code. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly details: Record<string, unknown> = {},
  ) {
    super(code);
  }

  toResponse(): Response {
    return Response.json({ error: this.code, ...this.details }, { status: this.status });
  }
}

export async function readJson<T>(request: Request): Promise<T> {
  try {
    return (await request.json()) as T;
  } catch {
    throw new HttpError(400, "bad_request");
  }
}

export function requireString(value: unknown, field: string, max = 200): string {
  if (typeof value !== "string" || value.trim() === "" || value.length > max) {
    throw new HttpError(400, "bad_request", { field });
  }

  return value.trim();
}
