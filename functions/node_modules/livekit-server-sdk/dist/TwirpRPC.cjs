"use strict";
var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
var TwirpRPC_exports = {};
__export(TwirpRPC_exports, {
  TwirpError: () => TwirpError,
  TwirpRpc: () => TwirpRpc,
  livekitPackage: () => livekitPackage
});
module.exports = __toCommonJS(TwirpRPC_exports);
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
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  TwirpError,
  TwirpRpc,
  livekitPackage
});
//# sourceMappingURL=TwirpRPC.cjs.map