//
//  VideoFrameCapture.h
//  Runner
//
//  Captures video frames from WebRTC tracks for use in Flame game engine.
//

#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

NS_ASSUME_NONNULL_BEGIN

/// Frame buffer header structure - must match Dart FFI struct exactly (40 bytes)
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t bytesPerRow;
    uint32_t format;        // 0 = BGRA, 1 = RGBA
    uint64_t timestamp;
    uint32_t frameNumber;
    uint32_t ready;         // 1 = new frame available
    uint32_t error;
    uint32_t reserved;
} VideoFrameBufferHeader;

#define VIDEO_FRAME_BUFFER_HEADER_SIZE 40

/// Captures frames from an RTCVideoTrack and writes to shared memory buffer.
@interface VideoFrameStreamer : NSObject <RTCVideoRenderer>

@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic, readonly, nullable) void* bufferPointer;
@property (nonatomic, strong, nullable) NSString* errorMessage;

- (instancetype)initWithMaxWidth:(int)maxWidth
                       maxHeight:(int)maxHeight
                       targetFps:(int)targetFps;

- (void)attachToTrack:(RTCVideoTrack*)track;
- (void)detach;
- (void)markConsumed;

@end

/// Handle for a capture session
@interface VideoFrameCaptureHandle : NSObject

@property (nonatomic, strong) VideoFrameStreamer* streamer;
@property (nonatomic, strong) NSString* trackId;

@end

// MARK: - C API (exposed to Dart FFI)

void video_frame_capture_init(void);
void* _Nullable video_frame_capture_create(const char* _Nullable trackId,
                                           int32_t targetFps,
                                           int32_t maxWidth,
                                           int32_t maxHeight);
void* _Nullable video_frame_capture_get_buffer(void* _Nullable capture);
void video_frame_capture_mark_consumed(void* _Nullable capture);
int32_t video_frame_capture_is_active(void* _Nullable capture);
const char* _Nullable video_frame_capture_get_error(void* _Nullable capture);
void video_frame_capture_destroy(void* _Nullable capture);
int32_t video_frame_capture_list_tracks(char* _Nullable buffer, int32_t bufferSize);

NS_ASSUME_NONNULL_END
