import { VideoGrant, SIPGrant } from './grants.cjs';
import '@livekit/protocol';
import 'jose';

/**
 * Utilities to handle authentication
 */
declare class ServiceBase {
    private readonly apiKey?;
    private readonly secret?;
    private readonly ttl;
    /**
     * @param apiKey - API Key.
     * @param secret - API Secret.
     * @param ttl - token TTL
     */
    constructor(apiKey?: string, secret?: string, ttl?: string);
    authHeader(grant: VideoGrant, sip?: SIPGrant): Promise<Record<string, string>>;
}

export { ServiceBase };
