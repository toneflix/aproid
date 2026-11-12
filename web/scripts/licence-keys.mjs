// Makes the key pair that signs licence tokens. The private key goes to the worker as the
// LICENCE_SIGNING_KEY secret; the public key goes to GitHub as the LICENCE_PUBLIC_KEY variable,
// which the release workflow builds into the Mac and Windows apps.
const { privateKey, publicKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const base64 = async (format, key) => Buffer.from(await crypto.subtle.exportKey(format, key)).toString("base64");

console.log(`LICENCE_SIGNING_KEY (secret, keep private):\n${await base64("pkcs8", privateKey)}\n`);
console.log(`LICENCE_PUBLIC_KEY (public):\n${await base64("spki", publicKey)}`);
