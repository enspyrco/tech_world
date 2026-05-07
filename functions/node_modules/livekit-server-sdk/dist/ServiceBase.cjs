"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
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
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
var ServiceBase_exports = {};
__export(ServiceBase_exports, {
  ServiceBase: () => ServiceBase
});
module.exports = __toCommonJS(ServiceBase_exports);
var import_AccessToken = require("./AccessToken.cjs");
class ServiceBase {
  /**
   * @param apiKey - API Key.
   * @param secret - API Secret.
   * @param ttl - token TTL
   */
  constructor(apiKey, secret, ttl) {
    this.apiKey = apiKey;
    this.secret = secret;
    this.ttl = ttl || "10m";
  }
  async authHeader(grant, sip) {
    const at = new import_AccessToken.AccessToken(this.apiKey, this.secret, { ttl: this.ttl });
    if (grant) {
      at.addGrant(grant);
    }
    if (sip) {
      at.addSIPGrant(sip);
    }
    return {
      Authorization: `Bearer ${await at.toJwt()}`
    };
  }
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  ServiceBase
});
//# sourceMappingURL=ServiceBase.cjs.map