/** Headers an operator request carries. */
export const AdminHeaders = {
  key: "x-flyylink-operator-key",
  timestamp: "x-flyylink-timestamp",
  nonce: "x-flyylink-nonce",
  signature: "x-flyylink-signature",
} as const;

export interface SignedParts {
  method: string;
  path: string;
  timestamp: string;
  nonce: string;
  body: string;
}

const encoder = new TextEncoder();
const ed25519 = { name: "Ed25519" };

function toBase64(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let text = "";

  for (const byte of view) text += String.fromCharCode(byte);

  return btoa(text);
}

function fromBase64(text: string): Uint8Array {
  return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
}

/**
 * The Ed25519 signature an operator puts on each request, over the method, path, timestamp, nonce and
 * body hash. Uses Web Crypto, so the CLI (Node) and the worker share it.
 */
export class AdminSignature {
  /** How far a request's timestamp may be from the server's clock, in seconds. */
  static readonly windowSeconds = 300;

  static async payload(parts: SignedParts): Promise<Uint8Array> {
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(parts.body)));
    const bodyHash = [...hash].map((byte) => byte.toString(16).padStart(2, "0")).join("");

    return encoder.encode(["flyylink-admin-v1", parts.method.toUpperCase(), parts.path, parts.timestamp, parts.nonce, bodyHash].join("\n"));
  }

  /** A new key pair: the public key as base64 of its 32 raw bytes, the private key as base64 PKCS#8. */
  static async generateKeys(): Promise<{ publicKey: string; privateKey: string }> {
    const pair = (await crypto.subtle.generateKey(ed25519, true, ["sign", "verify"])) as CryptoKeyPair;

    return {
      publicKey: toBase64((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer),
      privateKey: toBase64((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer),
    };
  }

  static async sign(privateKey: string, parts: SignedParts): Promise<string> {
    const key = await crypto.subtle.importKey("pkcs8", fromBase64(privateKey), ed25519, false, ["sign"]);

    return toBase64(await crypto.subtle.sign(ed25519, key, await AdminSignature.payload(parts)));
  }

  static async verify(publicKey: string, parts: SignedParts, signature: string): Promise<boolean> {
    try {
      const key = await crypto.subtle.importKey("raw", fromBase64(publicKey), ed25519, false, ["verify"]);

      return await crypto.subtle.verify(ed25519, key, fromBase64(signature), await AdminSignature.payload(parts));
    } catch {
      return false;
    }
  }

  /** Whether the text is a base64 Ed25519 public key. */
  static isPublicKey(text: string): boolean {
    try {
      const raw = fromBase64(text.trim());

      return raw.length === 32 && toBase64(raw) === text.trim();
    } catch {
      return false;
    }
  }

  /** A short identifier for a public key: `SHA256:` and the first 16 base64 characters of its hash. */
  static async fingerprint(publicKey: string): Promise<string> {
    const hash = await crypto.subtle.digest("SHA-256", fromBase64(publicKey));

    return `SHA256:${toBase64(hash).slice(0, 16)}`;
  }

  /** Whether the timestamp, in Unix seconds, is within the window around `now`. */
  static fresh(timestamp: string, now = Date.now()): boolean {
    return /^\d{1,12}$/.test(timestamp) && Math.abs(now / 1000 - Number(timestamp)) <= AdminSignature.windowSeconds;
  }
}
