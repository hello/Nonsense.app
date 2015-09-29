//
//  AppDelegate.m
//  Nonsense
//
//  Created by Delisa Mason on 6/12/15.
//  Copyright (c) 2015 Hello. All rights reserved.
//

#import "AppDelegate.h"

typedef void (^InputBlock)(NSFileHandle*);

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow* window;
@property (weak) IBOutlet NSTextField* addressField;
@property (assign) IBOutlet NSTextView* logView;
@property (strong) NSTask* serverTask;
@end

@implementation AppDelegate

NSString* const serverPort = @"3000";

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    if ([self.window respondsToSelector:@selector(setTitleVisibility:)])
        self.window.titleVisibility = NSWindowTitleHidden;
    [self launchWebServer];
    self.addressField.stringValue = [self hostNameAndPort];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    [self stopWebServer];
}

/**
 *  Launch the nonsense web server for hosting timeline data. The cached data is loaded from
 *  the supporting file named "timelines.txt". Other files could be substituted as needed, and
 *  a few are available in the git repo for the nonsense project:
 *  https://github.com/hello/nonsense
 */
- (void)launchWebServer
{
    NSString* serverPath = [[NSBundle mainBundle] pathForResource:@"nonsense" ofType:nil];
    NSString* dataPath = [[NSBundle mainBundle] pathForResource:@"timelines" ofType:@"txt"];
    NSTask* task = [NSTask new];
    [task setLaunchPath:serverPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:dataPath])
        [task setArguments:@[ @"--timeline-cache", dataPath ]];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    [task.standardOutput fileHandleForReading].readabilityHandler = [self inputBlockWithTextColor:[NSColor blackColor]];
    [task.standardError fileHandleForReading].readabilityHandler = [self inputBlockWithTextColor:[NSColor redColor]];
    [task setTerminationHandler:^(NSTask* task) {
        [task.standardOutput fileHandleForReading].readabilityHandler = nil;
        [task.standardError fileHandleForReading].readabilityHandler = nil;
    }];
    self.serverTask = task;
    @try {
        [task launch];
    }
    @catch (NSException* exception) {
        [self.logView setString:[NSString stringWithFormat:@"The server launch failed! 🚀🔥 %@", exception]];
    }
}

/**
 *  Shut down the web server
 */
- (void)stopWebServer
{
    [self.serverTask interrupt];
}

/**
 *  Creates a block which when executed will write to the log view of the main window
 *  the contents of the input file handle in the specified color
 *
 *  @param textColor the color in which to draw the text
 *
 *  @return the block for handling text input from a file handle
 */
- (InputBlock)inputBlockWithTextColor:(NSColor* __nonnull)textColor
{
    __weak typeof(self) weakSelf = self;
    return ^(NSFileHandle* file) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString* rawContent = [[NSString alloc] initWithData:[file availableData] encoding:NSUTF8StringEncoding];
        NSAttributedString* content = [[NSAttributedString alloc] initWithString:rawContent attributes:@{ NSForegroundColorAttributeName : textColor }];
        [[strongSelf.logView textStorage] appendAttributedString:content];
        [strongSelf.logView scrollRangeToVisible:NSMakeRange([strongSelf.logView.string length], 0)];
    };
}

/**
 *  Computes the host name and port of the web server to display in the window bar
 *
 *  @return host name and port delimited by a colon
 */
- (NSString*)hostNameAndPort
{
    NSString* const localhostAddressIPv4 = @"127.0.0.1";
    NSString* const IPv4Matcher = @"^\\d+\\.\\d+\\.\\d+\\.\\d+$";
    NSError* error = nil;
    NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:IPv4Matcher options:0 error:&error];
    if (error)
        return nil;
    for (NSString* address in [[NSHost currentHost] addresses]) {
        if ([address isEqualToString:localhostAddressIPv4])
            continue;
        NSRange range = [regex rangeOfFirstMatchInString:address options:0 range:NSMakeRange(0, address.length)];
        if (range.location != NSNotFound) {
            return [NSString stringWithFormat:@"%@:%@", address, serverPort];
        }
    }
    return nil;
}

@end
