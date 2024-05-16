//
//  Rsampler.m
//  AudioUnitDemo
//
//  Created by zhouzihao on 2024/5/15.
//

#import "Rsampler.h"
#import <AVFoundation/AVFoundation.h>
@interface Rsampler ()

@property (nonatomic, strong) AVAudioConverter *converter;
@property (nonatomic, strong) AVAudioPCMBuffer *sourceBuffer;

@end

@implementation Rsampler

- (instancetype)initWithSourceFormat:(AVAudioFormat *)sourceFormat destinationFormat:(AVAudioFormat *)destinationFormat {
    if (self = [super init]) {
        self.converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:destinationFormat];
        self.sourceBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:sourceFormat frameCapacity:4096];
    }
    return self;
}

- (AVAudioPCMBuffer *)refillInNumberOfPackets:(AVAudioPacketCount)numberOfPackets {
    float *sourceData = self.sourceBuffer.floatChannelData[0];
//    for (int frameIndex = 0; frameIndex < numberOfPackets; frameIndex++) {
//        // 填充数据
//        sourceData[frameIndex] = 
//    }
    self.sourceBuffer.frameLength = numberOfPackets;
    return self.sourceBuffer;
}

- (void)resample:(AudioBufferList *)ioData {
    AVAudioPCMBuffer *destinationBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self.converter.outputFormat bufferListNoCopy:ioData deallocator:^(const AudioBufferList * _Nonnull list) {}];
    if (!destinationBuffer) { return; }
    NSError *error = nil;
    AVAudioConverterOutputStatus outputStatus = [self.converter convertToBuffer:destinationBuffer error:&error withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return [self refillInNumberOfPackets:inNumberOfPackets];
    }];
    
    if (outputStatus == AVAudioConverterOutputStatus_Error) {
        if (error) {
            NSLog(@"%@",error.localizedDescription);
        }
    }
}

@end
