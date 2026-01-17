//
//  VideoFrameCapture.m
//  Runner
//
//  Captures video frames from WebRTC tracks for use in Flame game engine.
//

#import "VideoFrameCapture.h"
#import "FlutterWebRTCPlugin.h"
#import "LocalVideoTrack.h"

// MARK: - VideoFrameStreamer

@interface VideoFrameStreamer ()
@property (nonatomic, assign) void* buffer;
@property (nonatomic, assign) int bufferSize;
@property (nonatomic, assign) int targetFps;
@property (nonatomic, assign) CFAbsoluteTime lastFrameTime;
@property (nonatomic, assign) NSTimeInterval frameInterval;
@property (nonatomic, weak) RTCVideoTrack* videoTrack;
@property (nonatomic, strong) NSLock* lock;
@property (nonatomic, assign) BOOL active;
@end

@implementation VideoFrameStreamer

- (instancetype)initWithMaxWidth:(int)maxWidth
                       maxHeight:(int)maxHeight
                       targetFps:(int)targetFps {
    self = [super init];
    if (self) {
        _targetFps = targetFps;
        _frameInterval = 1.0 / (double)targetFps;
        _lastFrameTime = 0;
        _lock = [[NSLock alloc] init];
        _active = NO;

        // Allocate buffer for maximum frame size (BGRA = 4 bytes per pixel)
        int pixelDataSize = maxWidth * maxHeight * 4;
        _bufferSize = VIDEO_FRAME_BUFFER_HEADER_SIZE + pixelDataSize;
        _buffer = calloc(1, _bufferSize);

        if (_buffer) {
            memset(_buffer, 0, VIDEO_FRAME_BUFFER_HEADER_SIZE);
        }
    }
    return self;
}

- (void)dealloc {
    [self detach];
    if (_buffer) {
        free(_buffer);
        _buffer = NULL;
    }
}

- (BOOL)isActive {
    return _active;
}

- (void*)bufferPointer {
    return _buffer;
}

- (void)attachToTrack:(RTCVideoTrack*)track {
    [_lock lock];

    if (_videoTrack) {
        [_videoTrack removeRenderer:self];
    }

    _videoTrack = track;
    [track addRenderer:self];
    _active = YES;

    NSLog(@"VideoFrameStreamer: Attached to track %@", track.trackId);

    [_lock unlock];
}

- (void)detach {
    [_lock lock];

    if (_videoTrack) {
        [_videoTrack removeRenderer:self];
    }
    _videoTrack = nil;
    _active = NO;

    NSLog(@"VideoFrameStreamer: Detached");

    [_lock unlock];
}

- (void)markConsumed {
    [_lock lock];

    if (_buffer) {
        VideoFrameBufferHeader* header = (VideoFrameBufferHeader*)_buffer;
        header->ready = 0;
    }

    [_lock unlock];
}

// MARK: - RTCVideoRenderer

- (void)setSize:(CGSize)size {
    NSLog(@"VideoFrameStreamer: setSize %dx%d", (int)size.width, (int)size.height);
}

- (void)renderFrame:(RTCVideoFrame* _Nullable)frame {
    if (!frame) return;

    // Throttle frames based on target FPS
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _lastFrameTime < _frameInterval) {
        return;
    }
    _lastFrameTime = now;

    [_lock lock];

    if (!_buffer || !_active) {
        [_lock unlock];
        return;
    }

    // Convert frame to I420
    id<RTCI420Buffer> i420Buffer = [frame.buffer toI420];

    int32_t width = i420Buffer.width;
    int32_t height = i420Buffer.height;
    int32_t bytesPerRow = width * 4;  // BGRA

    // Check buffer size
    int requiredSize = VIDEO_FRAME_BUFFER_HEADER_SIZE + (height * bytesPerRow);
    if (requiredSize > _bufferSize) {
        NSLog(@"VideoFrameStreamer: Frame too large (%dx%d), skipping", width, height);
        VideoFrameBufferHeader* header = (VideoFrameBufferHeader*)_buffer;
        header->error = 2;
        _errorMessage = @"Frame too large";
        [_lock unlock];
        return;
    }

    // Get pixel data pointer (after header)
    uint8_t* pixelsPtr = (uint8_t*)_buffer + VIDEO_FRAME_BUFFER_HEADER_SIZE;

    // Convert I420 to BGRA (actually ARGB in WebRTC terms)
    [RTCYUVHelper I420ToARGB:i420Buffer.dataY
                  srcStrideY:i420Buffer.strideY
                        srcU:i420Buffer.dataU
                  srcStrideU:i420Buffer.strideU
                        srcV:i420Buffer.dataV
                  srcStrideV:i420Buffer.strideV
                     dstARGB:pixelsPtr
               dstStrideARGB:bytesPerRow
                       width:width
                      height:height];

    // Update header
    VideoFrameBufferHeader* header = (VideoFrameBufferHeader*)_buffer;
    header->width = (uint32_t)width;
    header->height = (uint32_t)height;
    header->bytesPerRow = (uint32_t)bytesPerRow;
    header->format = 0;  // BGRA
    header->timestamp = (uint64_t)frame.timeStampNs;
    header->frameNumber += 1;
    header->error = 0;

    // Signal frame is ready (write last for memory ordering)
    header->ready = 1;

    [_lock unlock];
}

@end

// MARK: - VideoFrameCaptureHandle

@implementation VideoFrameCaptureHandle
@end

// MARK: - Global State

static NSMutableDictionary<NSString*, VideoFrameStreamer*>* streamers = nil;
static NSMutableDictionary<NSValue*, VideoFrameCaptureHandle*>* handles = nil;

// MARK: - Helper Functions

static RTCVideoTrack* _Nullable findVideoTrack(NSString* trackId) {
    FlutterWebRTCPlugin* plugin = [FlutterWebRTCPlugin sharedSingleton];
    if (!plugin) {
        NSLog(@"VideoFrameCapture: Plugin not available");
        return nil;
    }

    // Try to get track using the plugin's method
    RTCMediaStreamTrack* track = [plugin trackForId:trackId peerConnectionId:nil];
    if (track && [track isKindOfClass:[RTCVideoTrack class]]) {
        NSLog(@"VideoFrameCapture: Found track %@ via trackForId", trackId);
        return (RTCVideoTrack*)track;
    }

    // Try local tracks directly
    NSDictionary<NSString*, id<LocalTrack>>* localTracks = plugin.localTracks;
    if (localTracks) {
        for (NSString* key in localTracks) {
            id<LocalTrack> localTrack = localTracks[key];
            if ([localTrack isKindOfClass:[LocalVideoTrack class]]) {
                LocalVideoTrack* lvt = (LocalVideoTrack*)localTrack;
                RTCVideoTrack* vt = lvt.videoTrack;
                if (vt && [vt.trackId isEqualToString:trackId]) {
                    NSLog(@"VideoFrameCapture: Found local video track %@", trackId);
                    return vt;
                }
            }
        }
    }

    // Try remote track
    RTCMediaStreamTrack* remoteTrack = [plugin remoteTrackForId:trackId];
    if (remoteTrack && [remoteTrack isKindOfClass:[RTCVideoTrack class]]) {
        NSLog(@"VideoFrameCapture: Found remote track %@", trackId);
        return (RTCVideoTrack*)remoteTrack;
    }

    // Try peer connections for remote tracks via transceivers
    NSDictionary<NSString*, RTCPeerConnection*>* peerConnections = plugin.peerConnections;
    if (peerConnections) {
        for (RTCPeerConnection* pc in peerConnections.allValues) {
            for (RTCRtpTransceiver* transceiver in pc.transceivers) {
                RTCMediaStreamTrack* t = transceiver.receiver.track;
                if (t && [t.trackId isEqualToString:trackId] && [t isKindOfClass:[RTCVideoTrack class]]) {
                    NSLog(@"VideoFrameCapture: Found track via transceiver %@", trackId);
                    return (RTCVideoTrack*)t;
                }
            }
        }
    }

    NSLog(@"VideoFrameCapture: Track %@ not found", trackId);
    return nil;
}

// MARK: - C API Implementation

void video_frame_capture_init(void) {
    NSLog(@"VideoFrameCapture: Initialized");

    if (!streamers) {
        streamers = [NSMutableDictionary new];
    }
    if (!handles) {
        handles = [NSMutableDictionary new];
    }
}

void* _Nullable video_frame_capture_create(const char* _Nullable trackId,
                                           int32_t targetFps,
                                           int32_t maxWidth,
                                           int32_t maxHeight) {
    if (!trackId) {
        NSLog(@"VideoFrameCapture: trackId is NULL");
        return NULL;
    }

    NSString* trackIdStr = [NSString stringWithUTF8String:trackId];

    // Find the video track
    RTCVideoTrack* track = findVideoTrack(trackIdStr);
    if (!track) {
        NSLog(@"VideoFrameCapture: Could not find track %@", trackIdStr);
        return NULL;
    }

    // Create streamer
    VideoFrameStreamer* streamer = [[VideoFrameStreamer alloc] initWithMaxWidth:maxWidth
                                                                      maxHeight:maxHeight
                                                                      targetFps:targetFps];

    if (!streamer.bufferPointer) {
        NSLog(@"VideoFrameCapture: Failed to create streamer");
        return NULL;
    }

    // Attach to track
    [streamer attachToTrack:track];

    // Store in global dict
    streamers[trackIdStr] = streamer;

    // Create handle
    VideoFrameCaptureHandle* handle = [VideoFrameCaptureHandle new];
    handle.streamer = streamer;
    handle.trackId = trackIdStr;

    // Use the handle object's pointer as the opaque handle
    void* handlePtr = (__bridge_retained void*)handle;
    handles[[NSValue valueWithPointer:handlePtr]] = handle;

    NSLog(@"VideoFrameCapture: Created capture for track %@", trackIdStr);

    return handlePtr;
}

void* _Nullable video_frame_capture_get_buffer(void* _Nullable capture) {
    if (!capture) return NULL;

    VideoFrameCaptureHandle* handle = (__bridge VideoFrameCaptureHandle*)capture;
    return handle.streamer.bufferPointer;
}

void video_frame_capture_mark_consumed(void* _Nullable capture) {
    if (!capture) return;

    VideoFrameCaptureHandle* handle = (__bridge VideoFrameCaptureHandle*)capture;
    [handle.streamer markConsumed];
}

int32_t video_frame_capture_is_active(void* _Nullable capture) {
    if (!capture) return 0;

    VideoFrameCaptureHandle* handle = (__bridge VideoFrameCaptureHandle*)capture;
    return handle.streamer.isActive ? 1 : 0;
}

const char* _Nullable video_frame_capture_get_error(void* _Nullable capture) {
    if (!capture) return NULL;

    VideoFrameCaptureHandle* handle = (__bridge VideoFrameCaptureHandle*)capture;
    return handle.streamer.errorMessage.UTF8String;
}

void video_frame_capture_destroy(void* _Nullable capture) {
    if (!capture) return;

    VideoFrameCaptureHandle* handle = (__bridge_transfer VideoFrameCaptureHandle*)capture;

    [handle.streamer detach];
    [streamers removeObjectForKey:handle.trackId];
    [handles removeObjectForKey:[NSValue valueWithPointer:capture]];

    NSLog(@"VideoFrameCapture: Destroyed capture");
}

int32_t video_frame_capture_list_tracks(char* _Nullable buffer, int32_t bufferSize) {
    if (!buffer || bufferSize <= 0) return 0;

    FlutterWebRTCPlugin* plugin = [FlutterWebRTCPlugin sharedSingleton];
    if (!plugin) {
        buffer[0] = 0;
        return 0;
    }

    NSMutableArray<NSString*>* trackIds = [NSMutableArray new];

    // Local tracks
    NSDictionary<NSString*, id<LocalTrack>>* localTracks = plugin.localTracks;
    if (localTracks) {
        for (NSString* key in localTracks) {
            id<LocalTrack> localTrack = localTracks[key];
            if ([localTrack isKindOfClass:[LocalVideoTrack class]]) {
                LocalVideoTrack* lvt = (LocalVideoTrack*)localTrack;
                if (lvt.videoTrack) {
                    [trackIds addObject:lvt.videoTrack.trackId];
                }
            }
        }
    }

    // Remote tracks from peer connections
    NSDictionary<NSString*, RTCPeerConnection*>* peerConnections = plugin.peerConnections;
    if (peerConnections) {
        for (RTCPeerConnection* pc in peerConnections.allValues) {
            for (RTCRtpTransceiver* transceiver in pc.transceivers) {
                RTCMediaStreamTrack* track = transceiver.receiver.track;
                if (track && [track isKindOfClass:[RTCVideoTrack class]]) {
                    [trackIds addObject:track.trackId];
                }
            }
        }
    }

    NSString* result = [trackIds componentsJoinedByString:@","];
    const char* resultCStr = result.UTF8String;

    size_t copyLength = MIN(strlen(resultCStr), (size_t)(bufferSize - 1));
    memcpy(buffer, resultCStr, copyLength);
    buffer[copyLength] = 0;

    return (int32_t)trackIds.count;
}
