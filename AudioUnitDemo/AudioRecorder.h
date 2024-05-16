//
//  AudioRecorder.h
//  AudioUnitDemo
//
//  Created by zhouzihao on 2024/5/13.
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface AudioRecorder : NSObject
- (void)startRecording;
- (void)stopRecording;
@end

NS_ASSUME_NONNULL_END
