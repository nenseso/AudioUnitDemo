//
//  AudioRecorder.m
//  AudioUnitDemo
//
//  Created by zhouzihao on 2024/5/13.
//

#import "AudioRecorder.h"
#import <AVFoundation/AVFoundation.h>

@interface AudioRecorder()<AVCaptureAudioDataOutputSampleBufferDelegate>
{
    FILE *_file;
}
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *assetWriterInput;
@property (nonatomic, strong) AVAudioConverter *converter;
@property (nonatomic, strong) AVAudioPCMBuffer *sourceBuffer;
@property (nonatomic, strong) NSThread *thread;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@end

@implementation AudioRecorder

float kDefaultSampleRate = 48000.0;
NSInteger kDefaultchannelCount = 1;
NSInteger kDefaultBitDepth = 16;
AVAudioCommonFormat kDefaultFormat = AVAudioPCMFormatInt16;

- (void)startRecording {
    [self useAudioRecorder];
//    [self useCaptureSession];
    
    self.isRecording = YES;
}

- (void)useCaptureSession {
    self.captureSession = [[AVCaptureSession alloc] init];
        
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    
    [self.captureSession beginConfiguration];
    [self.captureSession addInput:audioDeviceInput];

    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    dispatch_queue_t audioOutputQueue = dispatch_queue_create("com.cvte.maxhubshare.ultrasound.audiocapture", DISPATCH_QUEUE_SERIAL);
    [self.audioDataOutput setSampleBufferDelegate:self queue:audioOutputQueue];
    [self.captureSession addOutput:self.audioDataOutput];

    [self.captureSession commitConfiguration];
    [self.captureSession startRunning];
    
    [self createAssetWriter];
    
    // 文件写入类型的使用这个方法来读取PCM
//    [self createFile];
//    [self createThread];
}

- (void)useAudioRecorder {
    NSString *filePath = [self writePath];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    AudioChannelLayout channelLayout;
    memset(&channelLayout, 0, sizeof(AudioChannelLayout));
    channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVNumberOfChannelsKey: @(kDefaultchannelCount),
        AVSampleRateKey: @(kDefaultSampleRate),
        AVChannelLayoutKey: [NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)],
        AVLinearPCMBitDepthKey: @(kDefaultBitDepth),
        AVLinearPCMIsFloatKey: @(NO),
        AVLinearPCMIsBigEndianKey: @(NO),
        AVLinearPCMIsNonInterleaved: @(NO)
    };
    NSError *error = nil;
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:settings error:&error];
    if (error) {
        NSLog(@"Error to create audio recorder, %@", error.localizedDescription);
        return;
    }
    [self.audioRecorder prepareToRecord];
    [self.audioRecorder record];
    [self createFile];
    self.isRecording = YES;
    [self createThread];
}

- (void)createFile {
    
    _file = fopen([[self writePath] UTF8String], "wb+");
    if (!_file) {
        NSLog(@"Could not open file for writing");
        return;
    }
}

- (NSString *)writePath {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"output.pcm"];
    NSLog(@"path : %@", path);
    return path;
}

- (void)createAssetWriter {
    
    NSURL *audioFileURL = [NSURL fileURLWithPath: [self writePath]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self writePath]]) {
        [[NSFileManager defaultManager] removeItemAtURL:audioFileURL error:nil];
    }
    self.assetWriter = [AVAssetWriter assetWriterWithURL:audioFileURL fileType:AVFileTypeMPEG4 error:nil];
    AudioChannelLayout channelLayout;
    memset(&channelLayout, 0, sizeof(AudioChannelLayout));
    channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;

    NSDictionary *outputSettings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVNumberOfChannelsKey: @1,
        AVSampleRateKey: @44100.0,
        AVChannelLayoutKey: [NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)],
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsFloatKey: @(NO),
        AVLinearPCMIsBigEndianKey: @(NO),
        AVLinearPCMIsNonInterleaved: @(NO)
    };

    self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:outputSettings];
    [self.assetWriter addInput:self.assetWriterInput];

    [self.assetWriter startWriting];
    [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
}

- (void)createThread {
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(readLoop) object:nil];
    [thread start];
    self.thread = thread;
}

- (void)readLoop {
    NSString *rewritePath = [[[self writePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"output1.pcm"];
    NSFileHandle *rewriteFileHandle = [NSFileHandle fileHandleForWritingAtPath:rewritePath];
    if (!rewriteFileHandle) {
        NSLog(@"Could not open file for rewriting");
        return;
    }
    
    long threshold = 1024 * 1024;
    while (self.isRecording) {
        NSFileHandle *readFileHandle = [NSFileHandle fileHandleForReadingAtPath:[self writePath]];
        NSData *fileData = [readFileHandle readDataToEndOfFile];
        long fileSize = [fileData length];
        if (fileSize > threshold) {
            NSData *dataToProcess = [fileData subdataWithRange:NSMakeRange(0, fileSize)];
            // Process the new data...
            // 重新写入到文件中
            [rewriteFileHandle writeData:dataToProcess];
            [readFileHandle truncateFileAtOffset:0]; // 清空文件
        }
        [NSThread sleepForTimeInterval:0.1];  // Adjust this value as needed
    }
    [rewriteFileHandle closeFile];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // 使用assetWriter写入文件
//    [self useAssetWriter:sampleBuffer];
    // 冲采样并写入文件
    [self resample:sampleBuffer];
}

- (void)useAssetWriter:(CMSampleBufferRef)sampleBuffer {
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {return;}
    
    if (self.assetWriter.status == AVAssetWriterStatusUnknown) {
        CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        [self.assetWriter startSessionAtSourceTime:startTime];
    }
    
    if (self.assetWriter.status == AVAssetWriterStatusFailed) {
        NSLog(@"Writer error: %@", self.assetWriter.error.localizedDescription);
        return;
    }
    
    if (self.assetWriter.status == AVAssetWriterStatusWriting) {
        if (self.assetWriterInput.isReadyForMoreMediaData) {
            if (![self.assetWriterInput appendSampleBuffer:sampleBuffer]) {
                NSLog(@"Append buffer error.");
            }
        }
    }
}

- (void)resample:(CMSampleBufferRef)sampleBuffer {
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {return;}
    // 将采集到的音频数据重采样为48k,SInt16,单通道的PCM数据
    // 创建converter
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
    if (!_converter) {
        AVAudioFormat *sourceFormat = [[AVAudioFormat alloc] initWithStreamDescription:asbd];
        AVAudioFormat *destinationFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:kDefaultSampleRate channels:kDefaultchannelCount interleaved:NO];
        _converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:destinationFormat];
        if (_converter == nil) {
            NSLog(@"[Error] rror to create audio converter");
            [self stopRecording];
            return;
        }
    }

    _sourceBuffer = [self toAudioPcmBuffer:sampleBuffer];
    // calculate sourceBuffer data size
    const AudioBufferList *bufferList = _sourceBuffer.audioBufferList;
    // create destination buffer
    AVAudioFormat *destFormat = self.converter.outputFormat;
    const AudioStreamBasicDescription *destAsbd = destFormat.streamDescription;

    AVAudioFrameCount destFrameCount = _sourceBuffer.frameLength / asbd->mSampleRate  * destAsbd->mSampleRate;
    AVAudioPCMBuffer *destBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:destFormat frameCapacity:destFrameCount];
    if (!destBuffer) {
        NSLog(@"Error to create destBuffer");
        [self stopRecording];
        return;
    }
    NSError *error = nil;

    AudioRecorder* __weak weakSelf = self;
    AVAudioConverterOutputStatus status = [self.converter convertToBuffer:destBuffer error:&error withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount count, AVAudioConverterInputStatus * _Nonnull outStatus) {
        AudioRecorder* __strong strongSelf = weakSelf;
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return strongSelf.sourceBuffer;
    }];
    
    if (status == AVAudioConverterOutputStatus_Error) {
        NSString *errmsg = @"";
        if (error) {
            errmsg = error.localizedDescription;
        }
        NSLog(@"Error in convert audio data, %@", errmsg);
        [self stopRecording];
        return;
    }
    // 拿到dest buffer
    int8_t *destAudioBuffer = (int8_t *)destBuffer.audioBufferList->mBuffers[0].mData;
    UInt32 destAudioBufferSizeInBytes = destBuffer.frameLength * destFormat.streamDescription->mBytesPerFrame;
    
    // 传入上层
    // 写入到本地文件
    [self writeBufferToFile:destAudioBuffer size:destAudioBufferSizeInBytes];
}

- (void)writeBufferToFile:(int8_t *)buffer size:(UInt32)size {
    // Convert buffer to NSData
    NSData *data = [NSData dataWithBytes:buffer length:size];

    // Get file path
    NSString *filePath = [self writePath];

    // Write data to file
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) {
        // If file doesn't exist, create it first
        [fileManager createFileAtPath:filePath contents:nil attributes:nil];
    }

    // Append data to file
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    [fileHandle seekToEndOfFile];
    [fileHandle writeData:data];
}

- (AVAudioPCMBuffer *)toAudioPcmBuffer:(CMSampleBufferRef)sampleBufferRef {
    CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBufferRef);
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCMAudioFormatDescription:CMSampleBufferGetFormatDescription(sampleBufferRef)];
    AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)numSamples];
    pcmBuffer.frameLength = (AVAudioFrameCount)numSamples;
    
    CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBufferRef, 0, (int32_t)numSamples, pcmBuffer.mutableAudioBufferList);
    return pcmBuffer;
}


- (void)stopRecording {
    [self.audioRecorder stop];
    [self.audioRecorder deleteRecording];
    [self.captureSession stopRunning];
    [self.assetWriterInput markAsFinished];
    [self.assetWriter finishWritingWithCompletionHandler:^{}];
    self.isRecording = NO;
    fclose(_file);
    NSString *filePath = [self writePath];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    [fileHandle closeFile];
}


@end
