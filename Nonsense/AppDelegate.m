//
//  AppDelegate.m
//  Nonsense
//
//  Created by Delisa Mason on 6/12/15.
//  Copyright (c) 2015 Hello. All rights reserved.
//

#import "AppDelegate.h"

typedef void (^InputBlock)(NSFileHandle*);

@interface AppDelegate () <NSNetServiceDelegate>

@property (weak) IBOutlet NSWindow* window;
@property (weak) IBOutlet NSTextField* addressField;
@property (assign) IBOutlet NSTextView* logView;
@property (strong) NSTask* serverTask;
@property (strong) NSNetService* netService;
@end

@implementation AppDelegate

NSString* const serverPort = @"3000";
NSString* const serviceType = @"_http._tcp.";
NSString* const serviceName = @"nonsense-server";

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    if ([self.window respondsToSelector:@selector(setTitleVisibility:)])
        self.window.titleVisibility = NSWindowTitleHidden;
    if ([self launchWebServer]) {
        [self startNetService];
    }
    self.addressField.stringValue = [self hostNameAndPort];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    [self stopWebServer];
    [self stopNetService];
}

/**
 *  Launch the nonsense web server for hosting timeline data. The cached data is loaded from
 *  the supporting file named "timelines.txt". Other files could be substituted as needed, and
 *  a few are available in the git repo for the nonsense project:
 *  https://github.com/hello/nonsense
 */
- (BOOL)launchWebServer
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
    task.terminationHandler = ^(NSTask* task) {
        [task.standardOutput fileHandleForReading].readabilityHandler = nil;
        [task.standardError fileHandleForReading].readabilityHandler = nil;
    };
    self.serverTask = task;
    @try {
        [task launch];
    }
    @catch (NSException* exception) {
        [self.logView setString:[NSString stringWithFormat:@"The server launch failed! 🚀🔥 %@", exception]];
        return NO;
    }
    
    return YES;
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
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSString* rawContent = [[NSString alloc] initWithData:[file availableData]
                                                         encoding:NSUTF8StringEncoding];
            [weakSelf appendOutput:rawContent withTextColor:textColor];
        }];
    };
}

/**
 *  Appends a given string to the log output view using a given text color.
 *
 *  @param rawContent the content to append
 *  @param textColor the color in which to draw the text
 */
- (void)appendOutput:(NSString* __nonnull)rawContent withTextColor:(NSColor* __nonnull)textColor
{
    NSFont* font = [NSFont userFixedPitchFontOfSize:12.0];
    NSDictionary<NSString*, id>* attributes = @{ NSForegroundColorAttributeName : textColor,
                                                 NSFontAttributeName : font };
    NSAttributedString* content = [[NSAttributedString alloc] initWithString:rawContent
                                                                  attributes:attributes];
    [[self.logView textStorage] appendAttributedString:content];
    [self.logView scrollRangeToVisible:NSMakeRange([self.logView.string length], 0)];
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

#pragma mark - Net Discovery

- (void)startNetService
{
    self.netService = [[NSNetService alloc] initWithDomain:@""
                                                      type:serviceType
                                                      name:serviceName
                                                      port:serverPort.intValue];
    self.netService.delegate = self;
    [self.netService publish];
}

- (void)stopNetService
{
    [self.netService stop];
    self.netService = nil;
}

#pragma mark -

- (void)netServiceWillPublish:(NSNetService*)sender
{
    [self appendOutput:@"Preparing auto-discovery\n" withTextColor:[NSColor blueColor]];
}

- (void)netServiceDidPublish:(NSNetService*)sender
{
    NSString* output = [NSString stringWithFormat:@"Auto-discovery ready as '%@'\n", sender.name];
    [self appendOutput:output withTextColor:[NSColor blueColor]];
}

- (void)netService:(NSNetService*)sender didNotPublish:(NSDictionary<NSString*, NSNumber*>*)errorDict
{
    NSLog(@"*** Auto-discovery failed to start: %@", errorDict);
    [self appendOutput:@"Auto-discovery failed to start\n" withTextColor:[NSColor redColor]];
}

@end
