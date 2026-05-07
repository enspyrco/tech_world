import type { RoomConfiguration } from '@livekit/protocol';
import { TrackSource } from '@livekit/protocol';
import type { JWTPayload } from 'jose';
export declare function trackSourceToString(source: TrackSource): "camera" | "microphone" | "screen_share" | "screen_share_audio";
export declare function claimsToJwtPayload(grant: ClaimGrants): JWTPayload & {
    video?: Record<string, unknown>;
};
export interface VideoGrant {
    /** permission to create a room */
    roomCreate?: boolean;
    /** permission to join a room as a participant, room must be set */
    roomJoin?: boolean;
    /** permission to list rooms */
    roomList?: boolean;
    /** permission to start a recording */
    roomRecord?: boolean;
    /** permission to control a specific room, room must be set */
    roomAdmin?: boolean;
    /** name of the room, must be set for admin or join permissions */
    room?: string;
    /** permissions to control ingress, not specific to any room or ingress */
    ingressAdmin?: boolean;
    /**
     * allow participant to publish. If neither canPublish or canSubscribe is set,
     * both publish and subscribe are enabled
     */
    canPublish?: boolean;
    /**
     * TrackSource types that the participant is allowed to publish
     * When set, it supersedes CanPublish. Only sources explicitly set here can be published
     */
    canPublishSources?: TrackSource[];
    /** allow participant to subscribe to other tracks */
    canSubscribe?: boolean;
    /**
     * allow participants to publish data, defaults to true if not set
     */
    canPublishData?: boolean;
    /**
     * by default, a participant is not allowed to update its own metadata
     */
    canUpdateOwnMetadata?: boolean;
    /** participant isn't visible to others */
    hidden?: boolean;
    /** participant is recording the room, when set, allows room to indicate it's being recorded */
    recorder?: boolean;
    /** participant allowed to connect to LiveKit as Agent Framework worker */
    agent?: boolean;
    /** allow participant to subscribe to metrics */
    canSubscribeMetrics?: boolean;
    /** destination room which this participant can forward to */
    destinationRoom?: string;
}
export interface SIPGrant {
    /** manage sip resources */
    admin?: boolean;
    /** make outbound calls */
    call?: boolean;
}
export interface InferenceGrant {
    /** perform inference */
    perform?: boolean;
}
/** @internal */
export interface ClaimGrants extends JWTPayload {
    name?: string;
    video?: VideoGrant;
    sip?: SIPGrant;
    inference?: InferenceGrant;
    kind?: string;
    metadata?: string;
    attributes?: Record<string, string>;
    sha256?: string;
    roomPreset?: string;
    roomConfig?: RoomConfiguration;
}
//# sourceMappingURL=grants.d.ts.map