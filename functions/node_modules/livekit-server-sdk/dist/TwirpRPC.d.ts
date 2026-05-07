import type { JsonValue } from '@bufbuild/protobuf';
export declare const livekitPackage = "livekit";
export interface Rpc {
    request(service: string, method: string, data: JsonValue, headers: any, // eslint-disable-line @typescript-eslint/no-explicit-any
    timeout?: number): Promise<string>;
}
export declare class TwirpError extends Error {
    status: number;
    code?: string;
    metadata?: Record<string, string>;
    constructor(name: string, message: string, status: number, code?: string, metadata?: Record<string, string>);
}
/**
 * JSON based Twirp V7 RPC
 */
export declare class TwirpRpc {
    host: string;
    pkg: string;
    prefix: string;
    constructor(host: string, pkg: string, prefix?: string);
    request(service: string, method: string, data: any, // eslint-disable-line @typescript-eslint/no-explicit-any
    headers: any, // eslint-disable-line @typescript-eslint/no-explicit-any
    timeout?: number): Promise<any>;
}
//# sourceMappingURL=TwirpRPC.d.ts.map