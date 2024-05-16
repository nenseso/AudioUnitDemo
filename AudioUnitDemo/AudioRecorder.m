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

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // TODO:
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
        AVAudioFormat *destinationFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:48000 channels:1 interleaved:NO];
        _converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:destinationFormat];
        if (_converter == nil) {
            NSLog(@"Error to create audio converter");
            exit(-1);
        }
    }
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    AudioBufferList bufferList;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer,
                                                            NULL,
                                                            &bufferList,
                                                            sizeof(bufferList),
                                                            NULL,
                                                            NULL,
                                                            kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                            &blockBuffer);
    int8_t *audioBuffer = (int8_t *)bufferList.mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList.mBuffers[0].mDataByteSize;
    
    CFRelease(blockBuffer);

    // source buffer
    AVAudioFormat *inputFormat = self.converter.inputFormat;
    AVAudioFrameCount sourceFrameCount = audioBufferSizeInBytes / inputFormat.streamDescription->mBytesPerFrame;
    if (!_sourceBuffer) {
        _sourceBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFormat frameCapacity:sourceFrameCount];
        _sourceBuffer.frameLength = sourceFrameCount;
    }
    
    // destination buffer
    AVAudioFormat *destFormat = self.converter.outputFormat;
    const AudioStreamBasicDescription *destAsbd = destFormat.streamDescription;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"origin samplerate = %lf, formatId = %u, AudioFormatFlags = %u, mBytesPerPacket = %u, mFramesPerPacket = %u, mBytesPerFrame = %u, mChannelsPerFrame = %u, mBitsPerChannel = %u, mReserved = %u, audioBufferSizeInBytes = %u", asbd->mSampleRate, (unsigned int)asbd->mFormatID, (unsigned int)asbd->mFormatFlags, (unsigned int)asbd->mBytesPerPacket, (unsigned int)asbd->mFramesPerPacket, (unsigned int)asbd->mBytesPerFrame, (unsigned int)asbd->mChannelsPerFrame, (unsigned int)asbd->mBitsPerChannel, (unsigned int)asbd->mReserved, bufferList.mBuffers[0].mDataByteSize);
        
        NSLog(@"dest samplerate = %lf, formatId = %u, AudioFormatFlags = %u, mBytesPerPacket = %u, mFramesPerPacket = %u, mBytesPerFrame = %u, mChannelsPerFrame = %u, mBitsPerChannel = %u, mReserved = %u", destAsbd->mSampleRate, (unsigned int)destAsbd->mFormatID, (unsigned int)destAsbd->mFormatFlags, (unsigned int)destAsbd->mBytesPerPacket, (unsigned int)destAsbd->mFramesPerPacket, (unsigned int)destAsbd->mBytesPerFrame, (unsigned int)destAsbd->mChannelsPerFrame, (unsigned int)destAsbd->mBitsPerChannel, (unsigned int)destAsbd->mReserved);
    });

    AVAudioFrameCount destFrameCount = sourceFrameCount / asbd->mSampleRate  * destAsbd->mSampleRate;
    AVAudioPCMBuffer *destBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:destFormat frameCapacity:destFrameCount];
    
    NSError *error = nil;
    AVAudioConverterOutputStatus status = [self.converter convertToBuffer:destBuffer error:&error withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
        memcpy(self.sourceBuffer.floatChannelData[0], audioBuffer, audioBufferSizeInBytes);
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return self.sourceBuffer;
    }];
    
    if (status == AVAudioConverterOutputStatus_Error) {
        NSLog(@"Error in convert audio data");
        return;
    }
    
    // 拿到dest buffer
    int8_t *destAudioBuffer = (int8_t *)destBuffer.audioBufferList->mBuffers[0].mData;
    UInt32 destAudioBufferSizeInBytes = destBuffer.audioBufferList->mBuffers[0].mDataByteSize;
    
    // 写入到本地文件
    fwrite(destAudioBuffer, destAudioBufferSizeInBytes, 1, _file);
}


- (void)stopRecording {
    [self.captureSession stopRunning];
    [self.assetWriterInput markAsFinished];
    [self.assetWriter finishWritingWithCompletionHandler:^{}];
    fclose(_file);
}


@end
