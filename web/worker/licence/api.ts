import { HttpError, readJson, requireString } from "../http";
import type { Router } from "../router";
import { SignInCodes } from "./codes";
import { Licensing, type Machine } from "./licensing";
import type { PaddleWebhook } from "./paddle";
import type { Sessions } from "./sessions";
import type { LicenceStore } from "./store";

export interface CheckoutConfig {
  clientToken: string;
  priceId: string;
  sandbox: boolean;
}

const now = () => Math.floor(Date.now() / 1000);
const platforms = ["mac", "windows"];

/** The licence endpoints the computer apps and the website's buy and account pages call. */
export class LicenceApi {
  constructor(
    private readonly store: LicenceStore,
    private readonly licensing: Licensing,
    private readonly codes: SignInCodes,
    private readonly sessions: Sessions,
    private readonly paddle: PaddleWebhook,
    private readonly checkout: CheckoutConfig,
  ) {}

  register(router: Router): void {
    router
      .get("/api/checkout", () => this.checkoutConfig())
      .post("/api/paddle/webhook", (request) => this.paddle.handle(request, now()))
      .post("/api/code", (request) => this.sendCode(request))
      .post("/api/activate", (request) => this.activate(request))
      .post("/api/refresh", (request) => this.refresh(request))
      .post("/api/trial", (request) => this.trial(request))
      .post("/api/session", (request) => this.signIn(request))
      .post("/api/session/end", (request) => this.signOut(request))
      .get("/api/account", (request) => this.account(request))
      .post("/api/account/computers/:machine/remove", (request, { machine }) => this.remove(request, machine));
  }

  private checkoutConfig(): Response {
    if (!this.checkout.clientToken || !this.checkout.priceId) throw new HttpError(503, "not_open");

    return Response.json(this.checkout);
  }

  private async sendCode(request: Request): Promise<Response> {
    const { email } = await readJson<{ email?: unknown }>(request);
    await this.codes.send(SignInCodes.normalise(requireString(email, "email")), now());

    return new Response(null, { status: 204 });
  }

  private async activate(request: Request): Promise<Response> {
    const body = await readJson<{ email?: unknown; code?: unknown; machine?: unknown }>(request);
    const account = await this.verify(body.email, body.code);

    return Response.json(await this.licensing.activate(account, LicenceApi.machine(body.machine), now()));
  }

  private async refresh(request: Request): Promise<Response> {
    const { machine, secret } = await readJson<{ machine?: unknown; secret?: unknown }>(request);
    const token = await this.licensing.refresh(requireString(machine, "machine", 128), requireString(secret, "secret"), now());

    return Response.json({ token });
  }

  private async trial(request: Request): Promise<Response> {
    const { machine } = await readJson<{ machine?: unknown }>(request);

    return Response.json({ token: await this.licensing.trial(requireString(machine, "machine", 128), now()) });
  }

  private async signIn(request: Request): Promise<Response> {
    const { email, code } = await readJson<{ email?: unknown; code?: unknown }>(request);
    const account = await this.verify(email, code);

    return new Response(null, { status: 204, headers: { "Set-Cookie": await this.sessions.start(account, now()) } });
  }

  private async signOut(request: Request): Promise<Response> {
    return new Response(null, { status: 204, headers: { "Set-Cookie": await this.sessions.end(request) } });
  }

  private async account(request: Request): Promise<Response> {
    const account = await this.sessions.account(request, now());

    return Response.json({
      email: account.email,
      licensed: await this.store.hasActiveLicence(account.id),
      computers: await this.licensing.computers(account),
      limit: Licensing.maxComputers,
      removalsLeft: await this.licensing.removalsLeft(account, now()),
    });
  }

  private async remove(request: Request, machine: string): Promise<Response> {
    const account = await this.sessions.account(request, now());
    await this.licensing.remove(account, machine, now());

    return new Response(null, { status: 204 });
  }

  /** Checks the emailed code; an email that never bought anything still gets an account to sign in to. */
  private async verify(email: unknown, code: unknown) {
    const address = SignInCodes.normalise(requireString(email, "email"));
    await this.codes.verify(address, requireString(code, "code", 12), now());

    return this.store.accountFor(address, now());
  }

  private static machine(value: unknown): Machine {
    const machine = (value ?? {}) as Record<string, unknown>;
    const platform = requireString(machine.platform, "platform", 16);
    if (!platforms.includes(platform)) throw new HttpError(400, "bad_request", { field: "platform" });

    return { id: requireString(machine.id, "machine", 128), name: requireString(machine.name, "name", 100), platform };
  }
}
