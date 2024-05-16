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
    
    AVCaptureDeviceType deviceType = AVCaptureDeviceTypeMicrophone;
    AVCaptureDeviceDiscoverySession *session = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[deviceType] mediaType:AVMediaTypeAudio position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in session.devices) {
        NSLog(@"%@ manufacturer: %@", device.localizedName, device.manufacturer);
    }
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSLog(@"default device name: %@, manufacturer: %@", audioDevice.localizedName, audioDevice.manufacturer);
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
