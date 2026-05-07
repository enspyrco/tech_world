async function digest(data) {
  var _a;
  if ((_a = globalThis.crypto) == null ? void 0 : _a.subtle) {
    const encoder = new TextEncoder();
    return crypto.subtle.digest("SHA-256", encoder.encode(data));
  } else {
    const nodeCrypto = await import("node:crypto");
    return nodeCrypto.createHash("sha256").update(data).digest();
  }
}
export {
  digest
};
//# sourceMappingURL=digest.js.map