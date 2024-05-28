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
@end

@implementation AudioRecorder


- (void)startRecording {
    self.captureSession = [[AVCaptureSession alloc] init];
        
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    
    [self.captureSession beginConfiguration];
    [self.captureSession addInput:audioDeviceInput];

    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioDataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    [self.captureSession addOutput:self.audioDataOutput];

    [self.captureSession commitConfiguration];
    [self.captureSession startRunning];
    
    [self createAssetWriter];
    
    [self createFile];
    
//    [self createThread];
    self.isRecording = YES;
}

- (void)createFile {
    
    _file = fopen([[self writePath] UTF8String], "wb+");
    if (!_file) {
        NSLog(@"Could not open file for writing");
        return;
    }
}

- (NSString *)writePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES);
    NSString *downloadsDirectory = [paths objectAtIndex:0];
    NSString *path = [downloadsDirectory stringByAppendingPathComponent:@"output.pcm"];
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
    FILE *file = fopen([rewritePath UTF8String], "wb+");
    if (!file) {
        NSLog(@"Could not open file for rewriting");
        return;
    }
    
    long lastReadPosition = 0;
    while (self.isRecording) {
        fseek(_file, 0, SEEK_END);
        long fileSize = ftell(_file);
        NSLog(@"fileSize = %ld", fileSize);
        if (fileSize > lastReadPosition) {
            fseek(_file, lastReadPosition, SEEK_SET);
            long newBytes = fileSize - lastReadPosition;
            void *buffer = malloc(newBytes);
            fread(buffer, newBytes, 1, _file);
            // Process the new data...
            NSLog(@"newBytes = %ld", newBytes);
            // 重新写入到文件中
            fwrite(buffer, newBytes, 1, file);
            
            free(buffer);
            ftruncate(fileno(_file), 0); // 清空文件
//            lastReadPosition = fileSize;
            lastReadPosition = 0;
        }
        [NSThread sleepForTimeInterval:0.1];  // Adjust this value as needed
    }
    fclose(file);
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // TODO:
    [self resample:sampleBuffer];
//    [self useAssetWriter:sampleBuffer];
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
        AVAudioFormat *destinationFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:48000 channels:1 interleaved:NO];
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
    if (_file) {
        fwrite(destAudioBuffer, destAudioBufferSizeInBytes, 1, _file); // 在X86_64上崩溃
    }
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
    [self.captureSession stopRunning];
    [self.assetWriterInput markAsFinished];
    [self.assetWriter finishWritingWithCompletionHandler:^{}];
    self.isRecording = NO;
    fclose(_file);
}


@end
