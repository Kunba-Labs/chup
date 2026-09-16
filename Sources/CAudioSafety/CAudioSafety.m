#import "CAudioSafety.h"

static BOOL CHInputFormatMatches(AVAudioEngine *engine, AudioDeviceID device,
                                double rate, AVAudioChannelCount channels);

static AudioDeviceID CHResolvePhysicalDevice(AudioObjectID subdevice) {
    // AudioSubDevice objects have no I/O streams. Translate their UID back to
    // the real AudioDevice before inspecting which input streams are present.
    AudioObjectPropertyAddress uidAddress = {kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef uid = NULL; UInt32 size = sizeof(uid);
    if (AudioObjectGetPropertyData(subdevice, &uidAddress, 0, NULL, &size, &uid) != noErr || !uid) return 0;
    AudioObjectPropertyAddress translate = {kAudioHardwarePropertyTranslateUIDToDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioDeviceID device = 0; size = sizeof(device);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &translate,
        sizeof(uid), &uid, &size, &device);
    CFRelease(uid);
    return status == noErr ? device : 0;
}

// AVAudioEngine can wrap separate input/output devices in a private aggregate.
// Membership alone is not proof: accept only one input-bearing subdevice.
static BOOL CHDeviceUsesInput(AudioDeviceID actual, AudioDeviceID expected) {
    if (!actual || !expected) return NO;
    if (actual == expected) return YES;
    AudioObjectPropertyAddress address = {kAudioAggregateDevicePropertyActiveSubDeviceList,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioDeviceID devices[32]; UInt32 size = sizeof(devices);
    if (AudioObjectGetPropertyData(actual, &address, 0, NULL, &size, devices) != noErr ||
        size == 0 || size > sizeof(devices) || size % sizeof(AudioDeviceID)) return NO;
    UInt32 inputCount = 0; AudioDeviceID input = 0;
    for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); i++) {
        AudioDeviceID physical = CHResolvePhysicalDevice(devices[i]);
        if (!physical) return NO;
        AudioObjectPropertyAddress streams = {kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain};
        UInt32 bytes = 0;
        if (AudioObjectGetPropertyDataSize(physical, &streams, 0, NULL, &bytes) != noErr) return NO;
        if (bytes > 0) { inputCount++; input = physical; }
    }
    return inputCount == 1 && input == expected;
}

static NSError *CHInputError(NSInteger code, NSString *detail) {
    return [NSError errorWithDomain:@"com.chup.audio.input" code:code userInfo:@{
        NSLocalizedDescriptionKey: @"The microphone could not start. Check the device in Audio settings and try again.",
        NSLocalizedFailureReasonErrorKey: detail
    }];
}

void CHStopInput(AVAudioEngine *engine, BOOL tapInstalled) {
    @try { [engine stop]; }
    @catch (NSException *exception) { NSLog(@"Chup input stop exception: %@", exception.name); }
    if (tapInstalled) {
        @try { [engine.inputNode removeTapOnBus:0]; }
        @catch (NSException *exception) { NSLog(@"Chup input tap teardown exception: %@", exception.name); }
    }
}

BOOL CHStartInput(AVAudioEngine *engine, AudioDeviceID device, AVAudioNodeTapBlock tap,
                  BOOL *tapInstalled, double *rate, AVAudioChannelCount *channels,
                  NSError **error) {
    *tapInstalled = NO;
    @try {
        AVAudioInputNode *input = engine.inputNode;
        AudioUnit unit = input.audioUnit;
        if (!unit || (device && AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &device, sizeof(device)) != noErr)) {
            if (error) *error = CHInputError(1, @"Could not bind the requested input device.");
            return NO;
        }
        // Hardware input scope is authoritative. The output scope can retain an
        // old device's format, and AVAudioInputNode cannot convert hardware input.
        AVAudioFormat *hardware = [input inputFormatForBus:0];
        if (hardware.sampleRate <= 0 || hardware.channelCount == 0) {
            if (error) *error = CHInputError(2, @"Input device has no usable hardware format.");
            return NO;
        }
        [input installTapOnBus:0 bufferSize:2048 format:hardware block:tap];
        *tapInstalled = YES;
        NSError *startError = nil;
        if (![engine startAndReturnError:&startError]) {
            if (error) *error = startError ?: CHInputError(3, @"Audio engine did not start.");
            CHStopInput(engine, *tapInstalled); *tapInstalled = NO;
            return NO;
        }
        *rate = hardware.sampleRate; *channels = hardware.channelCount;
        // A stopped but correctly bound graph can settle via the caller's
        // bounded startup recovery. A different device/format cannot.
        if (!CHInputFormatMatches(engine, device, *rate, *channels)) {
            if (error) *error = CHInputError(4, @"Input device or format changed during startup.");
            CHStopInput(engine, *tapInstalled); *tapInstalled = NO;
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        // Catch directly around AVFAudio calls, before unwinding through Swift.
        if (error) *error = CHInputError(5, exception.reason ?: exception.name);
        CHStopInput(engine, *tapInstalled); *tapInstalled = NO;
        return NO;
    }
}

AudioDeviceID CHInputDevice(AVAudioEngine *engine) {
    @try {
        AudioUnit unit = engine.inputNode.audioUnit;
        AudioDeviceID actual = 0; UInt32 size = sizeof(actual);
        if (unit && AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &actual, &size) == noErr) return actual;
    } @catch (NSException *exception) {}
    return 0;
}

BOOL CHInputUsesDevice(AVAudioEngine *engine, AudioDeviceID device) {
    return CHDeviceUsesInput(CHInputDevice(engine), device);
}

static BOOL CHInputFormatMatches(AVAudioEngine *engine, AudioDeviceID device,
                                double rate, AVAudioChannelCount channels) {
    @try {
        AVAudioInputNode *input = engine.inputNode;
        AVAudioFormat *hardware = [input inputFormatForBus:0];
        AudioDeviceID actual = CHInputDevice(engine);
        return actual && (!device || CHDeviceUsesInput(actual, device)) && hardware.sampleRate == rate &&
            hardware.channelCount == channels;
    } @catch (NSException *exception) { return NO; }
}

BOOL CHInputMatchesConfiguration(AVAudioEngine *engine, AudioDeviceID device,
                                 double rate, AVAudioChannelCount channels) {
    return engine.isRunning && CHInputFormatMatches(engine, device, rate, channels);
}

BOOL CHResumeMatchingInput(AVAudioEngine *engine, AudioDeviceID device,
                           double rate, AVAudioChannelCount channels, NSError **error) {
    @try {
        // A late startup notification can stop a correctly bound graph. Reuse
        // that graph only while BOTH the physical input and format still match.
        if (!CHInputFormatMatches(engine, device, rate, channels)) {
            if (error) *error = CHInputError(6, @"Input device or format changed while opening the microphone.");
            return NO;
        }
        if (!engine.isRunning && ![engine startAndReturnError:error]) return NO;
        return CHInputMatchesConfiguration(engine, device, rate, channels);
    } @catch (NSException *exception) {
        if (error) *error = CHInputError(5, exception.reason ?: exception.name);
        return NO;
    }
}

// Fault injection opens no hardware. Exercise the same boundary as production.
@interface CHFailingInputEngine : AVAudioEngine @end
@implementation CHFailingInputEngine
- (AVAudioInputNode *)inputNode {
    @throw [NSException exceptionWithName:@"com.apple.coreaudio.avfaudio"
                                 reason:@"Synthetic input format mismatch" userInfo:nil];
}
@end
BOOL CHValidateInputExceptionBoundary(void) {
    AVAudioEngine *engine = [CHFailingInputEngine new];
    BOOL installed = NO; double rate = 0; AVAudioChannelCount channels = 0; NSError *error = nil;
    BOOL started = CHStartInput(engine, 0, ^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {},
                               &installed, &rate, &channels, &error);
    return !started && !installed && error.code == 5 &&
        [error.domain isEqualToString:@"com.chup.audio.input"];
}
