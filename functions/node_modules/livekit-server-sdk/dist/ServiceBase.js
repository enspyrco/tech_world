import { AccessToken } from "./AccessToken.js";
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
    const at = new AccessToken(this.apiKey, this.secret, { ttl: this.ttl });
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
export {
  ServiceBase
};
//# sourceMappingURL=ServiceBase.js.map