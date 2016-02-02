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

@property (nonatomic, readwrite) BOOL running;

@end

@implementation AppDelegate

NSString* const javaPath = @"/usr/bin/java";
NSString* const javaMinVersion = @"1.8";

NSString* const serverPort = @"3000";
NSString* const serviceType = @"_http._tcp.";
NSString* const serviceName = @"nonsense-server";

#pragma mark - Application Lifecycle

- (void)awakeFromNib
{
    if ([self.window respondsToSelector:@selector(setTitleVisibility:)]) {
        self.window.titleVisibility = NSWindowTitleHidden;
    }
    
    self.addressField.stringValue = [self hostNameAndPort];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    if (![self isJavaInstalled]) {
        [self runNoJavaInstallationModal];
        [NSApp terminate:nil];
    } else if (![self isJavaVersionNewEnough]) {
        [self runOldJavaInstallationModal];
        [NSApp terminate:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    [self stopWebServer];
    [self stopNetService];
}

#pragma mark - Java Sanity Check

/**
 *  Checks for the existence of Java on the user's computer.
 */
- (BOOL)isJavaInstalled
{
    return [[NSFileManager defaultManager] fileExistsAtPath:javaPath];
}

/**
 *  Invokes the `java` command on the user's computer with the `-version`
 *  option, and attempts to pull the version name out of the output.
 *  Returns nil if the version name cannot be found.
 */
- (nullable NSString*)installedJavaVersion
{
    NSTask* task = [NSTask new];
    task.launchPath = javaPath;
    task.arguments = @[@"-version"];
    
    // For some inexplicable reason, the java command prints out the version info
    // to stderr instead of stdout. On the off chance this is a bug, and it gets
    // fixed in the future, we send both stderr and stdout to the same pipe.
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    
    [task launch];
    [task waitUntilExit];
    
    NSData* rawOutput = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString* output = [[NSString alloc] initWithData:rawOutput encoding:NSUTF8StringEncoding];
    
    // The output should include a line in this format:
    // java version "1.8.0_81"
    NSRange startOfVersion = [output rangeOfString:@"java version \""];
    if (startOfVersion.location == NSNotFound) {
        NSLog(@"Cannot find start of version in output");
        return nil;
    }
    
    NSRange endOfVersion = [output rangeOfString:@"\""
                                         options:kNilOptions
                                           range:NSMakeRange(NSMaxRange(startOfVersion),
                                                             output.length - NSMaxRange(startOfVersion))];
    if (endOfVersion.location == NSNotFound) {
        NSLog(@"Cannot find end of version in output");
        return nil;
    }
    
    return [output substringWithRange:NSMakeRange(NSMaxRange(startOfVersion),
                                                  endOfVersion.location - NSMaxRange(startOfVersion))];
}

/**
 *  Attempts to fetch the version of the installed copy of Java, and if successful,
 *  checks that it meets the minimum version requirements of `nonsense.jar`.
 *  Returns NO if the version cannot be resolved.
 */
- (BOOL)isJavaVersionNewEnough
{
    NSString* version = [self installedJavaVersion];
    NSLog(@"Detected Java version %@", version);
    
    // We only care about the first portion of the version
    if (version.length >= 3) {
        NSString* majorVersion = [version substringToIndex:3];
        return [majorVersion compare:javaMinVersion options:NSNumericSearch] > NSOrderedAscending;
    } else {
        NSLog(@"Unexpected Java version %@, cannot perform comparison", version);
        return NO;
    }
}

#pragma mark -

/**
 *  Displays a modal alert explaining to the user that a copy of Java is
 *  required to run the Nonsense server contained in this application.
 */
- (void)runNoJavaInstallationModal
{
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Java Not Installed";
    alert.informativeText = (@"Nonsense requires a copy of Java to be installed on your computer. "
                             @"Download it from Oracle's Java website to continue.");
    [alert addButtonWithTitle:@"Quit"];
    [alert runModal];
}

/**
 *  Displays a modal alert explaining to the user that their copy of Java is
 *  too old to be able to run the Nonsense server contained in this application.
 */
- (void)runOldJavaInstallationModal
{
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Java Installation Too Old";
    alert.informativeText = (@"Nonsense requires Java 8 to be able to run its server. "
                             @"Download it from Oracle's Java website to continue.");
    [alert addButtonWithTitle:@"Quit"];
    [alert runModal];
}

#pragma mark - Server Task

/**
 *  Creates and returns the arguments to run the nonsense server,
 *  including any data caches chosen by the user.
 */
- (nonnull NSArray*)serverArguments {
    NSMutableArray<NSString*>* arguments = [NSMutableArray array];
    
    NSString* serverJarPath = [[NSBundle mainBundle] pathForResource:@"nonsense" ofType:@"jar"];
    [arguments addObject:@"-jar"];
    [arguments addObject:serverJarPath];
    
    if (self.timelineCachePath.length > 0) {
        [arguments addObject:@"--timeline-cache"];
        [arguments addObject:self.timelineCachePath];
    }
    
    if (self.trendsCachePath.length > 0) {
        [arguments addObject:@"--trends-cache"];
        [arguments addObject:self.trendsCachePath];
    }
    
    return [arguments copy];
}

/**
 *  Starts the nonsense web server with the options selected by the user.
 */
- (BOOL)launchWebServer
{
    NSTask* task = [NSTask new];
    task.launchPath = javaPath;
    task.arguments = [self serverArguments];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    [task.standardOutput fileHandleForReading].readabilityHandler = [self inputBlockWithTextColor:[NSColor blackColor]];
    [task.standardError fileHandleForReading].readabilityHandler = [self inputBlockWithTextColor:[NSColor redColor]];
    
    __weak __typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask* task) {
        [task.standardOutput fileHandleForReading].readabilityHandler = nil;
        [task.standardError fileHandleForReading].readabilityHandler = nil;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [weakSelf appendOutput:@"Server stopped\n" withTextColor:[NSColor blueColor]];
        }];
    };
    self.serverTask = task;
    @try {
        [task launch];
    }
    @catch (NSException* exception) {
        [self.logView setString:[NSString stringWithFormat:@"The server launch failed! 🚀🔥 %@", exception]];
        return NO;
    }
    
    self.running = YES;
    
    return YES;
}

/**
 *  Shut down the web server
 */
- (void)stopWebServer
{
    [self.serverTask interrupt];
    self.serverTask = nil;
    self.running = NO;
}

#pragma mark - Output

/**
 *  Creates a block which when executed will write to the log view of the main window
 *  the contents of the input file handle in the specified color
 *
 *  @param textColor the color in which to draw the text
 *
 *  @return the block for handling text input from a file handle
 */
- (InputBlock)inputBlockWithTextColor:(nonnull NSColor*)textColor
{
    __weak typeof(self) weakSelf = self;
    return ^(NSFileHandle* file) {
        NSString* rawContent = [[NSString alloc] initWithData:[file availableData]
                                                     encoding:NSUTF8StringEncoding];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
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
- (void)appendOutput:(nonnull NSString*)rawContent withTextColor:(nonnull NSColor*)textColor
{
    NSFont* font = [NSFont userFixedPitchFontOfSize:12.0];
    NSDictionary<NSString*, id>* attributes = @{ NSForegroundColorAttributeName : textColor,
                                                 NSFontAttributeName : font };
    NSAttributedString* content = [[NSAttributedString alloc] initWithString:rawContent
                                                                  attributes:attributes];
    [[self.logView textStorage] appendAttributedString:content];
    [self.logView scrollRangeToVisible:NSMakeRange([self.logView.string length], 0)];
}

#pragma mark - Utilities

/**
 *  Computes the host name and port of the web server to display in the window bar
 *
 *  @return host name and port delimited by a colon
 */
- (nullable NSString*)hostNameAndPort
{
    NSString* const localhostAddressIPv4 = @"127.0.0.1";
    NSString* const IPv4Matcher = @"^\\d+\\.\\d+\\.\\d+\\.\\d+$";
    
    NSError* error = nil;
    NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:IPv4Matcher
                                                                      options:kNilOptions
                                                                        error:&error];
    if (error) {
        return nil;
    }
    
    for (NSString* address in [[NSHost currentHost] addresses]) {
        if ([address isEqualToString:localhostAddressIPv4]) {
            continue;
        }
        
        NSRange range = [regex rangeOfFirstMatchInString:address
                                                 options:kNilOptions
                                                   range:NSMakeRange(0, address.length)];
        if (range.location != NSNotFound) {
            return [NSString stringWithFormat:@"%@:%@", address, serverPort];
        }
    }
    
    return nil;
}

#pragma mark - Net Discovery

/**
 *  Begins broadcasting the availability of the nonsense server over zero-conf/bonjour.
 */
- (void)startNetService
{
    self.netService = [[NSNetService alloc] initWithDomain:@""
                                                      type:serviceType
                                                      name:serviceName
                                                      port:serverPort.intValue];
    self.netService.delegate = self;
    [self.netService publish];
}

/**
 *  Stops broadcasting the availability of the nonsense server over zero-conf/bonjour.
 */
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

- (void)netServiceDidStop:(NSNetService *)sender {
    [self appendOutput:@"Auto-discovery stopped\n" withTextColor:[NSColor blueColor]];
}

- (void)netService:(NSNetService*)sender didNotPublish:(NSDictionary<NSString*, NSNumber*>*)errorDict
{
    NSLog(@"*** Auto-discovery failed to start: %@", errorDict);
    [self appendOutput:@"Auto-discovery failed to start\n" withTextColor:[NSColor redColor]];
}

#pragma mark - Bindings

+ (NSSet *)keyPathsForValuesAffectingRunTitle
{
    return [NSSet setWithObjects:@"running", nil];
}

- (NSString *)runTitle
{
    if (self.running) {
        return @"Stop Server";
    } else {
        return @"Start Server";
    }
}

#pragma mark - Actions

- (IBAction)toggleRunning:(id)sender
{
    if (self.running) {
        [self stopWebServer];
        [self stopNetService];
    } else {
        if ([self launchWebServer]) {
            [self startNetService];
        }
    }
}

- (IBAction)chooseTimelineCache:(id)sender
{
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Choose Timeline Cache";
    openPanel.prompt = @"Choose";
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedFileTypes = @[(id)kUTTypeText];
    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            self.timelineCachePath = openPanel.URL.path;
        }
    }];
}

- (IBAction)chooseTrendsCache:(id)sender
{
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Choose Trends Cache";
    openPanel.prompt = @"Choose";
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedFileTypes = @[(id)kUTTypeText];
    if ([openPanel runModal] == NSFileHandlingPanelOKButton) {
        self.trendsCachePath = openPanel.URL.path;
    }
}

@end
