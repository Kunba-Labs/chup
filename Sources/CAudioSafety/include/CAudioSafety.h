#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN
// No Objective-C exception may unwind through a Swift concurrency frame.
BOOL CHStartInput(AVAudioEngine *engine, AudioDeviceID device, AVAudioNodeTapBlock tap,
                  BOOL *tapInstalled, double *rate, AVAudioChannelCount *channels,
                  NSError * _Nullable * _Nullable error);
void CHStopInput(AVAudioEngine *engine, BOOL tapInstalled);
BOOL CHInputMatchesConfiguration(AVAudioEngine *engine, AudioDeviceID device,
                                 double rate, AVAudioChannelCount channels);
AudioDeviceID CHInputDevice(AVAudioEngine *engine);
BOOL CHInputUsesDevice(AVAudioEngine *engine, AudioDeviceID device);
BOOL CHResumeMatchingInput(AVAudioEngine *engine, AudioDeviceID device,
                           double rate, AVAudioChannelCount channels, NSError **error);
BOOL CHValidateInputExceptionBoundary(void);
NS_ASSUME_NONNULL_END
