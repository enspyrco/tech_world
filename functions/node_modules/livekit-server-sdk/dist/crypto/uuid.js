async function getRandomBytes(size = 16) {
  if (globalThis.crypto) {
    return crypto.getRandomValues(new Uint8Array(size));
  } else {
    const nodeCrypto = await import("node:crypto");
    return nodeCrypto.getRandomValues(new Uint8Array(size));
  }
}
export {
  getRandomBytes
};
//# sourceMappingURL=uuid.js.map