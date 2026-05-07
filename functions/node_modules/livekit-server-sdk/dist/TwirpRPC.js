const defaultPrefix = "/twirp";
const livekitPackage = "livekit";
class TwirpError extends Error {
  constructor(name, message, status, code, metadata) {
    super(message);
    this.name = name;
    this.status = status;
    this.code = code;
    this.metadata = metadata;
  }
}
class TwirpRpc {
  constructor(host, pkg, prefix) {
    if (host.startsWith("ws")) {
      host = host.replace("ws", "http");
    }
    this.host = host;
    this.pkg = pkg;
    this.prefix = prefix || defaultPrefix;
  }
  async request(service, method, data, headers, timeout = 60) {
    const path = `${this.prefix}/${this.pkg}.${service}/${method}`;
    const url = new URL(path, this.host);
    const init = {
      method: "POST",
      headers: {
        "Content-Type": "application/json;charset=UTF-8",
        ...headers
      },
      body: JSON.stringify(data)
    };
    if (timeout) {
      init.signal = AbortSignal.timeout(timeout * 1e3);
    }
    const response = await fetch(url, init);
    if (!response.ok) {
      const isJson = response.headers.get("content-type") === "application/json";
      let errorMessage = "Unknown internal error";
      let errorCode = void 0;
      let metadata = void 0;
      try {
        if (isJson) {
          const parsedError = await response.json();
          if ("msg" in parsedError) {
            errorMessage = parsedError.msg;
          }
          if ("code" in parsedError) {
            errorCode = parsedError.code;
          }
          if ("meta" in parsedError) {
            metadata = parsedError.meta;
          }
        } else {
          errorMessage = await response.text();
        }
      } catch (e) {
        console.debug(`Error when trying to parse error message, using defaults`, e);
      }
      throw new TwirpError(response.statusText, errorMessage, response.status, errorCode, metadata);
    }
    const parsedResp = await response.json();
    const camelcaseKeys = await import("camelcase-keys").then((mod) => mod.default);
    return camelcaseKeys(parsedResp, { deep: true });
  }
}
export {
  TwirpError,
  TwirpRpc,
  livekitPackage
};
//# sourceMappingURL=TwirpRPC.js.map