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
var SipClient_exports = {};
__export(SipClient_exports, {
  SipClient: () => SipClient
});
module.exports = __toCommonJS(SipClient_exports);
var import_protobuf = require("@bufbuild/protobuf");
var import_protocol = require("@livekit/protocol");
var import_ServiceBase = require("./ServiceBase.cjs");
var import_TwirpRPC = require("./TwirpRPC.cjs");
const svc = "SIP";
class SipClient extends import_ServiceBase.ServiceBase {
  /**
   * @param host - hostname including protocol. i.e. 'https://<project>.livekit.cloud'
   * @param apiKey - API Key, can be set in env var LIVEKIT_API_KEY
   * @param secret - API Secret, can be set in env var LIVEKIT_API_SECRET
   */
  constructor(host, apiKey, secret) {
    super(apiKey, secret);
    this.rpc = new import_TwirpRPC.TwirpRpc(host, import_TwirpRPC.livekitPackage);
  }
  /**
   * @param number - phone number of the trunk
   * @param opts - CreateSipTrunkOptions
   * @deprecated use `createSipInboundTrunk` or `createSipOutboundTrunk`
   */
  async createSipTrunk(number, opts) {
    let inboundAddresses;
    let inboundNumbers;
    let inboundUsername = "";
    let inboundPassword = "";
    let outboundAddress = "";
    let outboundUsername = "";
    let outboundPassword = "";
    let name = "";
    let metadata = "";
    if (opts !== void 0) {
      inboundAddresses = opts.inbound_addresses;
      inboundNumbers = opts.inbound_numbers;
      inboundUsername = opts.inbound_username || "";
      inboundPassword = opts.inbound_password || "";
      outboundAddress = opts.outbound_address || "";
      outboundUsername = opts.outbound_username || "";
      outboundPassword = opts.outbound_password || "";
      name = opts.name || "";
      metadata = opts.metadata || "";
    }
    const req = new import_protocol.CreateSIPTrunkRequest({
      name,
      metadata,
      inboundAddresses,
      inboundNumbers,
      inboundUsername,
      inboundPassword,
      outboundNumber: number,
      outboundAddress,
      outboundUsername,
      outboundPassword
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "CreateSIPTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Create a new SIP inbound trunk.
   *
   * @param name - human-readable name of the trunk
   * @param numbers - phone numbers of the trunk
   * @param opts - CreateSipTrunkOptions
   * @returns Created SIP inbound trunk
   */
  async createSipInboundTrunk(name, numbers, opts) {
    if (opts === void 0) {
      opts = {};
    }
    const req = new import_protocol.CreateSIPInboundTrunkRequest({
      trunk: new import_protocol.SIPInboundTrunkInfo({
        name,
        numbers,
        metadata: opts == null ? void 0 : opts.metadata,
        allowedAddresses: opts.allowedAddresses ?? opts.allowed_addresses,
        allowedNumbers: opts.allowedNumbers ?? opts.allowed_numbers,
        authUsername: opts.authUsername ?? opts.auth_username,
        authPassword: opts.authPassword ?? opts.auth_password,
        headers: opts.headers,
        headersToAttributes: opts.headersToAttributes,
        includeHeaders: opts.includeHeaders,
        krispEnabled: opts.krispEnabled
      })
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "CreateSIPInboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPInboundTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Create a new SIP outbound trunk.
   *
   * @param name - human-readable name of the trunk
   * @param address - hostname and port of the SIP server to dial
   * @param numbers - phone numbers of the trunk
   * @param opts - CreateSipTrunkOptions
   * @returns Created SIP outbound trunk
   */
  async createSipOutboundTrunk(name, address, numbers, opts) {
    if (opts === void 0) {
      opts = {
        transport: import_protocol.SIPTransport.SIP_TRANSPORT_AUTO
      };
    }
    const req = new import_protocol.CreateSIPOutboundTrunkRequest({
      trunk: new import_protocol.SIPOutboundTrunkInfo({
        name,
        address,
        numbers,
        metadata: opts.metadata,
        transport: opts.transport,
        authUsername: opts.authUsername ?? opts.auth_username,
        authPassword: opts.authPassword ?? opts.auth_password,
        headers: opts.headers,
        headersToAttributes: opts.headersToAttributes,
        includeHeaders: opts.includeHeaders,
        destinationCountry: opts.destinationCountry
      })
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "CreateSIPOutboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPOutboundTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * @deprecated use `listSipInboundTrunk` or `listSipOutboundTrunk`
   */
  async listSipTrunk() {
    const req = {};
    const data = await this.rpc.request(
      svc,
      "ListSIPTrunk",
      new import_protocol.ListSIPTrunkRequest(req).toJson(),
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.ListSIPTrunkResponse.fromJson(data, { ignoreUnknownFields: true }).items ?? [];
  }
  /**
   * List SIP inbound trunks with optional filtering.
   *
   * @param list - Request with optional filtering parameters
   * @returns Response containing list of SIP inbound trunks
   */
  async listSipInboundTrunk(list = {}) {
    const req = new import_protocol.ListSIPInboundTrunkRequest(list).toJson();
    const data = await this.rpc.request(
      svc,
      "ListSIPInboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.ListSIPInboundTrunkResponse.fromJson(data, { ignoreUnknownFields: true }).items ?? [];
  }
  /**
   * List SIP outbound trunks with optional filtering.
   *
   * @param list - Request with optional filtering parameters
   * @returns Response containing list of SIP outbound trunks
   */
  async listSipOutboundTrunk(list = {}) {
    const req = new import_protocol.ListSIPOutboundTrunkRequest(list).toJson();
    const data = await this.rpc.request(
      svc,
      "ListSIPOutboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.ListSIPOutboundTrunkResponse.fromJson(data, { ignoreUnknownFields: true }).items ?? [];
  }
  /**
   * Delete a SIP trunk.
   *
   * @param sipTrunkId - ID of the SIP trunk to delete
   * @returns Deleted trunk information
   */
  async deleteSipTrunk(sipTrunkId) {
    const data = await this.rpc.request(
      svc,
      "DeleteSIPTrunk",
      new import_protocol.DeleteSIPTrunkRequest({ sipTrunkId }).toJson(),
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Create a new SIP dispatch rule.
   *
   * @param rule - SIP dispatch rule to create
   * @param opts - CreateSipDispatchRuleOptions
   * @returns Created SIP dispatch rule
   */
  async createSipDispatchRule(rule, opts) {
    if (opts === void 0) {
      opts = {};
    }
    let ruleProto = void 0;
    if (rule.type == "direct") {
      ruleProto = new import_protocol.SIPDispatchRule({
        rule: {
          case: "dispatchRuleDirect",
          value: new import_protocol.SIPDispatchRuleDirect({
            roomName: rule.roomName,
            pin: rule.pin || ""
          })
        }
      });
    } else if (rule.type == "individual") {
      ruleProto = new import_protocol.SIPDispatchRule({
        rule: {
          case: "dispatchRuleIndividual",
          value: new import_protocol.SIPDispatchRuleIndividual({
            roomPrefix: rule.roomPrefix,
            pin: rule.pin || ""
          })
        }
      });
    }
    const req = new import_protocol.CreateSIPDispatchRuleRequest({
      rule: ruleProto,
      trunkIds: opts.trunkIds,
      hidePhoneNumber: opts.hidePhoneNumber,
      name: opts.name,
      metadata: opts.metadata,
      attributes: opts.attributes,
      roomPreset: opts.roomPreset,
      roomConfig: opts.roomConfig
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "CreateSIPDispatchRule",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPDispatchRuleInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Updates an existing SIP dispatch rule by replacing it entirely.
   *
   * @param sipDispatchRuleId - ID of the SIP dispatch rule to update
   * @param rule - new SIP dispatch rule
   * @returns Updated SIP dispatch rule
   */
  async updateSipDispatchRule(sipDispatchRuleId, rule) {
    const req = new import_protocol.UpdateSIPDispatchRuleRequest({
      sipDispatchRuleId,
      action: {
        case: "replace",
        value: rule
      }
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "UpdateSIPDispatchRule",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPDispatchRuleInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Updates specific fields of an existing SIP dispatch rule.
   * Only provided fields will be updated.
   *
   * @param sipDispatchRuleId - ID of the SIP dispatch rule to update
   * @param fields - Fields of the dispatch rule to update
   * @returns Updated SIP dispatch rule
   */
  async updateSipDispatchRuleFields(sipDispatchRuleId, fields = {}) {
    const req = new import_protocol.UpdateSIPDispatchRuleRequest({
      sipDispatchRuleId,
      action: {
        case: "update",
        value: fields
      }
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "UpdateSIPDispatchRule",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPDispatchRuleInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Updates an existing SIP inbound trunk by replacing it entirely.
   *
   * @param sipTrunkId - ID of the SIP inbound trunk to update
   * @param trunk - SIP inbound trunk to update with
   * @returns Updated SIP inbound trunk
   */
  async updateSipInboundTrunk(sipTrunkId, trunk) {
    const req = new import_protocol.UpdateSIPInboundTrunkRequest({
      sipTrunkId,
      action: {
        case: "replace",
        value: trunk
      }
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "UpdateSIPInboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPInboundTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Updates specific fields of an existing SIP inbound trunk.
   * Only provided fields will be updated.
   *
   * @param sipTrunkId - ID of the SIP inbound trunk to update
   * @param fields - Fields of the inbound trunk to update
   * @returns Updated SIP inbound trunk
   */
  async updateSipInboundTrunkFields(sipTrunkId, fields) {
    const req = new import_protocol.UpdateSIPInboundTrunkRequest({
      sipTrunkId,
      action: {
        case: "update",
        value: fields
      }
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "UpdateSIPInboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPInboundTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Updates an existing SIP outbound trunk by replacing it entirely.
   *
   * @param sipTrunkId - ID of the SIP outbound trunk to update
   * @param trunk - SIP outbound trunk to update with
   * @returns Updated SIP outbound trunk
   */
  async updateSipOutboundTrunk(sipTrunkId, trunk) {
    const req = new import_protocol.UpdateSIPOutboundTrunkRequest({
      sipTrunkId,
      action: {
        case: "replace",
        value: trunk
      }
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "UpdateSIPOutboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPOutboundTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Updates specific fields of an existing SIP outbound trunk.
   * Only provided fields will be updated.
   *
   * @param sipTrunkId - ID of the SIP outbound trunk to update
   * @param fields - Fields of the outbound trunk to update
   * @returns Updated SIP outbound trunk
   */
  async updateSipOutboundTrunkFields(sipTrunkId, fields) {
    const req = new import_protocol.UpdateSIPOutboundTrunkRequest({
      sipTrunkId,
      action: {
        case: "update",
        value: fields
      }
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "UpdateSIPOutboundTrunk",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPOutboundTrunkInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * List SIP dispatch rules with optional filtering.
   *
   * @param list - Request with optional filtering parameters
   * @returns Response containing list of SIP dispatch rules
   */
  async listSipDispatchRule(list = {}) {
    const req = new import_protocol.ListSIPDispatchRuleRequest(list).toJson();
    const data = await this.rpc.request(
      svc,
      "ListSIPDispatchRule",
      req,
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.ListSIPDispatchRuleResponse.fromJson(data, { ignoreUnknownFields: true }).items ?? [];
  }
  /**
   * Delete a SIP dispatch rule.
   *
   * @param sipDispatchRuleId - ID of the SIP dispatch rule to delete
   * @returns Deleted rule information
   */
  async deleteSipDispatchRule(sipDispatchRuleId) {
    const data = await this.rpc.request(
      svc,
      "DeleteSIPDispatchRule",
      new import_protocol.DeleteSIPDispatchRuleRequest({ sipDispatchRuleId }).toJson(),
      await this.authHeader({}, { admin: true })
    );
    return import_protocol.SIPDispatchRuleInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Create a new SIP participant.
   *
   * @param sipTrunkId - sip trunk to use for the call
   * @param number - number to dial
   * @param roomName - room to attach the call to
   * @param opts - CreateSipParticipantOptions
   * @returns Created SIP participant
   */
  async createSipParticipant(sipTrunkId, number, roomName, opts) {
    if (opts === void 0) {
      opts = {};
    }
    if (opts.timeout === void 0) {
      opts.timeout = opts.waitUntilAnswered ? 60 : 10;
    }
    const req = new import_protocol.CreateSIPParticipantRequest({
      sipTrunkId,
      sipCallTo: number,
      sipNumber: opts.fromNumber,
      roomName,
      participantIdentity: opts.participantIdentity || "sip-participant",
      participantName: opts.participantName,
      displayName: opts.displayName,
      participantMetadata: opts.participantMetadata,
      participantAttributes: opts.participantAttributes,
      dtmf: opts.dtmf,
      playDialtone: opts.playDialtone ?? opts.playRingtone,
      headers: opts.headers,
      hidePhoneNumber: opts.hidePhoneNumber,
      includeHeaders: opts.includeHeaders,
      ringingTimeout: opts.ringingTimeout ? new import_protobuf.Duration({ seconds: BigInt(opts.ringingTimeout) }) : void 0,
      maxCallDuration: opts.maxCallDuration ? new import_protobuf.Duration({ seconds: BigInt(opts.maxCallDuration) }) : void 0,
      krispEnabled: opts.krispEnabled,
      waitUntilAnswered: opts.waitUntilAnswered
    }).toJson();
    const data = await this.rpc.request(
      svc,
      "CreateSIPParticipant",
      req,
      await this.authHeader({}, { call: true }),
      opts.timeout
    );
    return import_protocol.SIPParticipantInfo.fromJson(data, { ignoreUnknownFields: true });
  }
  /**
   * Transfer a SIP participant to a different room.
   *
   * @param roomName - room the SIP participant to transfer is connectd to
   * @param participantIdentity - identity of the SIP participant to transfer
   * @param transferTo - SIP URL to transfer the participant to
   * @param opts - TransferSipParticipantOptions
   */
  async transferSipParticipant(roomName, participantIdentity, transferTo, opts) {
    if (opts === void 0) {
      opts = {};
    }
    const req = new import_protocol.TransferSIPParticipantRequest({
      participantIdentity,
      roomName,
      transferTo,
      playDialtone: opts.playDialtone,
      headers: opts.headers
    }).toJson();
    await this.rpc.request(
      svc,
      "TransferSIPParticipant",
      req,
      await this.authHeader({ roomAdmin: true, room: roomName }, { call: true })
    );
  }
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  SipClient
});
//# sourceMappingURL=SipClient.cjs.map