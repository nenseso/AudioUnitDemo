//
//  ViewController.m
//  AudioUnitDemo
//
//  Created by zhouzihao on 2024/5/13.
//

#import "ViewController.h"
#import "AudioRecorder.h"
#import <AVFoundation/AVFoundation.h>
@interface ViewController ()
@property (strong) AudioRecorder *recorder;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view.
    self.recorder = [[AudioRecorder alloc] init];
    
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)start:(id)sender {
    [self.recorder startRecording];
}

- (IBAction)stop:(id)sender {
    // 停止录音
    [self.recorder stopRecording];
}

@end
