import { execFile } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import worker, { type Env } from "../../worker/index";
import { testDatabase } from "../../worker/tests/d1";

const run = promisify(execFile);
const cli = path.join(import.meta.dirname, "../dist/index.js");
const config = path.join(mkdtempSync(path.join(tmpdir(), "flyylink-cli-")), "config.json");

let server: Server;
let url: string;

const env = {
  ASSETS: { fetch: async () => new Response("site") },
  LICENCES: testDatabase(),
  MAIL_FROM: "FlyyLink <hello@flyylink.test>",
  SITE_URL: "https://flyylink.test",
  MAIL_MODE: "log",
  CODE_SECRET: "test",
} as unknown as Env;

/** Runs the built CLI without a terminal, so it never asks questions. */
async function admin(...args: string[]): Promise<{ stdout: string; code: number }> {
  try {
    const { stdout } = await run(process.execPath, [cli, ...args], { env: { ...process.env, FLYYLINK_CLI_CONFIG: config, NO_COLOR: "1" } });

    return { stdout, code: 0 };
  } catch (error) {
    const failed = error as { stdout: string; stderr: string; code: number };

    return { stdout: failed.stdout + failed.stderr, code: failed.code };
  }
}

beforeAll(async () => {
  server = createServer(async (req, res) => {
    const chunks: Buffer[] = [];

    for await (const chunk of req) chunks.push(chunk as Buffer);

    const request = new Request(`http://${req.headers.host}${req.url}`, {
      method: req.method,
      headers: req.headers as Record<string, string>,
      body: req.method === "GET" || req.method === "HEAD" ? undefined : Buffer.concat(chunks),
    });
    const response = await worker.fetch(request, env);

    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(Buffer.from(await response.arrayBuffer()));
  });

  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  url = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
});

afterAll(() => server.close());

describe("flyylink-cli", () => {
  it("logs in, becomes the first operator and manages licences", async () => {
    expect((await admin("login", `--url=${url}`)).code).toBe(0);

    env.ADMIN_BOOTSTRAP_KEY = JSON.parse(readFileSync(config, "utf8")).publicKey;

    expect((await admin("operators:add", "obi", env.ADMIN_BOOTSTRAP_KEY!)).stdout).toContain("obi is an operator now");
    expect((await admin("licences:grant", "ada@example.com")).stdout).toContain("ada@example.com has a free licence.");

    const listing = await admin("users:list", "--licence=with");

    expect(listing.stdout).toMatch(/Email\s+Licensed\s+Computers\s+Joined/);
    expect(listing.stdout).toMatch(/ada@example\.com\s+yes\s+0/);

    const json = JSON.parse((await admin("licences:list", "--json")).stdout);

    expect(json.listing.rows[0]).toMatchObject({ email: "ada@example.com", provider: "manual", status: "active" });
  });

  it("refuses missing input before it reaches the server", async () => {
    const result = await admin("users:show");

    expect(result.code).toBe(1);
    expect(result.stdout).toContain("Missing <email>");
  });

  it("follows a notice's batches to the end", async () => {
    for (let i = 0; i < 22; i++) {
      await env.LICENCES.prepare("INSERT INTO accounts (id, email, created_at) VALUES (?, ?, 0)").bind(`id${i}`, `user${i}@example.com`).run();
      await env.LICENCES.prepare("INSERT INTO licences (id, account_id, provider, order_id, status, created_at) VALUES (?, ?, 'manual', ?, 'active', 0)").bind(`l${i}`, `id${i}`, `o${i}`).run();
    }

    const result = await admin("notify:send", "licensed", "--subject=Hello", "--message=Hi", "--force");

    expect(result.stdout).toContain("emailed 20 of 23");
    expect(result.stdout).toContain("emailed to 23 of 23");
  });
});
