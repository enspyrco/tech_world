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
var __reExport = (target, mod, secondTarget) => (__copyProps(target, mod, "default"), secondTarget && __copyProps(secondTarget, mod, "default"));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
var index_exports = {};
__export(index_exports, {
  AliOSSUpload: () => import_protocol.AliOSSUpload,
  AudioCodec: () => import_protocol.AudioCodec,
  AutoParticipantEgress: () => import_protocol.AutoParticipantEgress,
  AutoTrackEgress: () => import_protocol.AutoTrackEgress,
  AzureBlobUpload: () => import_protocol.AzureBlobUpload,
  DataPacket_Kind: () => import_protocol.DataPacket_Kind,
  DirectFileOutput: () => import_protocol.DirectFileOutput,
  EgressInfo: () => import_protocol.EgressInfo,
  EgressStatus: () => import_protocol.EgressStatus,
  EncodedFileOutput: () => import_protocol.EncodedFileOutput,
  EncodedFileType: () => import_protocol.EncodedFileType,
  EncodingOptions: () => import_protocol.EncodingOptions,
  EncodingOptionsPreset: () => import_protocol.EncodingOptionsPreset,
  GCPUpload: () => import_protocol.GCPUpload,
  ImageCodec: () => import_protocol.ImageCodec,
  ImageFileSuffix: () => import_protocol.ImageFileSuffix,
  ImageOutput: () => import_protocol.ImageOutput,
  IngressAudioEncodingOptions: () => import_protocol.IngressAudioEncodingOptions,
  IngressAudioEncodingPreset: () => import_protocol.IngressAudioEncodingPreset,
  IngressAudioOptions: () => import_protocol.IngressAudioOptions,
  IngressInfo: () => import_protocol.IngressInfo,
  IngressInput: () => import_protocol.IngressInput,
  IngressState: () => import_protocol.IngressState,
  IngressVideoEncodingOptions: () => import_protocol.IngressVideoEncodingOptions,
  IngressVideoEncodingPreset: () => import_protocol.IngressVideoEncodingPreset,
  IngressVideoOptions: () => import_protocol.IngressVideoOptions,
  ParticipantEgressRequest: () => import_protocol.ParticipantEgressRequest,
  ParticipantInfo: () => import_protocol.ParticipantInfo,
  ParticipantInfo_State: () => import_protocol.ParticipantInfo_State,
  ParticipantPermission: () => import_protocol.ParticipantPermission,
  Room: () => import_protocol.Room,
  RoomAgentDispatch: () => import_protocol.RoomAgentDispatch,
  RoomCompositeEgressRequest: () => import_protocol.RoomCompositeEgressRequest,
  RoomEgress: () => import_protocol.RoomEgress,
  S3Upload: () => import_protocol.S3Upload,
  SIPDispatchRuleInfo: () => import_protocol.SIPDispatchRuleInfo,
  SIPParticipantInfo: () => import_protocol.SIPParticipantInfo,
  SIPTrunkInfo: () => import_protocol.SIPTrunkInfo,
  SegmentedFileOutput: () => import_protocol.SegmentedFileOutput,
  SegmentedFileProtocol: () => import_protocol.SegmentedFileProtocol,
  StreamOutput: () => import_protocol.StreamOutput,
  StreamProtocol: () => import_protocol.StreamProtocol,
  TrackCompositeEgressRequest: () => import_protocol.TrackCompositeEgressRequest,
  TrackEgressRequest: () => import_protocol.TrackEgressRequest,
  TrackInfo: () => import_protocol.TrackInfo,
  TrackSource: () => import_protocol.TrackSource,
  TrackType: () => import_protocol.TrackType,
  VideoCodec: () => import_protocol.VideoCodec,
  WebEgressRequest: () => import_protocol.WebEgressRequest,
  WebhookConfig: () => import_protocol.WebhookConfig
});
module.exports = __toCommonJS(index_exports);
var import_protocol = require("@livekit/protocol");
__reExport(index_exports, require("./AccessToken.cjs"), module.exports);
__reExport(index_exports, require("./AgentDispatchClient.cjs"), module.exports);
__reExport(index_exports, require("./EgressClient.cjs"), module.exports);
__reExport(index_exports, require("./grants.cjs"), module.exports);
__reExport(index_exports, require("./IngressClient.cjs"), module.exports);
__reExport(index_exports, require("./RoomServiceClient.cjs"), module.exports);
__reExport(index_exports, require("./SipClient.cjs"), module.exports);
__reExport(index_exports, require("./WebhookReceiver.cjs"), module.exports);
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  AliOSSUpload,
  AudioCodec,
  AutoParticipantEgress,
  AutoTrackEgress,
  AzureBlobUpload,
  DataPacket_Kind,
  DirectFileOutput,
  EgressInfo,
  EgressStatus,
  EncodedFileOutput,
  EncodedFileType,
  EncodingOptions,
  EncodingOptionsPreset,
  GCPUpload,
  ImageCodec,
  ImageFileSuffix,
  ImageOutput,
  IngressAudioEncodingOptions,
  IngressAudioEncodingPreset,
  IngressAudioOptions,
  IngressInfo,
  IngressInput,
  IngressState,
  IngressVideoEncodingOptions,
  IngressVideoEncodingPreset,
  IngressVideoOptions,
  ParticipantEgressRequest,
  ParticipantInfo,
  ParticipantInfo_State,
  ParticipantPermission,
  Room,
  RoomAgentDispatch,
  RoomCompositeEgressRequest,
  RoomEgress,
  S3Upload,
  SIPDispatchRuleInfo,
  SIPParticipantInfo,
  SIPTrunkInfo,
  SegmentedFileOutput,
  SegmentedFileProtocol,
  StreamOutput,
  StreamProtocol,
  TrackCompositeEgressRequest,
  TrackEgressRequest,
  TrackInfo,
  TrackSource,
  TrackType,
  VideoCodec,
  WebEgressRequest,
  WebhookConfig,
  ...require("./AccessToken.cjs"),
  ...require("./AgentDispatchClient.cjs"),
  ...require("./EgressClient.cjs"),
  ...require("./grants.cjs"),
  ...require("./IngressClient.cjs"),
  ...require("./RoomServiceClient.cjs"),
  ...require("./SipClient.cjs"),
  ...require("./WebhookReceiver.cjs")
});
//# sourceMappingURL=index.cjs.map