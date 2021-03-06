#import "PanelController.h"
#import "BackgroundView.h"
#import "StatusItemView.h"
#import "MenubarController.h"
#import <AFNetworking/AFNetworking.h>

#define OPEN_DURATION .15
#define CLOSE_DURATION .1

#define SEARCH_INSET 17

#define POPUP_HEIGHT 220
#define PANEL_WIDTH 280
#define MENU_ANIMATION_DURATION .1

#define SEARCH_TYPE_TRACK           @"track"
#define SEARCH_TYPE_ALBUM           @"album"
#define SEARCH_TYPE_ARTIST          @"artist"
#define SEARCH_TYPE_TRACKS_PLURAL   @"tracks"
#define SEARCH_TYPE_ALBUMS_PLURAL   @"albums"
#define SEARCH_TYPE_ARTISTS_PLURAL  @"artists"

#pragma mark -

@implementation PanelController

@synthesize backgroundView = _backgroundView;
@synthesize delegate = _delegate;
@synthesize searchField = _searchField;
@synthesize textField = _textField;
@synthesize responseData = _responseData;
@synthesize searchType = _searchType;
@synthesize lastSearchedURI = _lastSearchedURI;

#pragma mark -

- (id)initWithDelegate:(id<PanelControllerDelegate>)delegate
{
    self = [super initWithWindowNibName:@"Panel"];
    if (self != nil)
    {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTextDidChangeNotification object:self.searchField];
}

#pragma mark -

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // Make a fully skinned panel
    NSPanel *panel = (id)[self window];
    [panel setAcceptsMouseMovedEvents:YES];
    [panel setLevel:NSPopUpMenuWindowLevel];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
    
    self.lastSearchedURI = @"spotify:track:6nek1Nin9q48AVZcWs9e9D"; // temp default value to avoid crashing
    
    self.searchType = [self.searchTypeSegmentedControl labelForSegment:self.searchTypeSegmentedControl.selectedSegment];
    NSLog(@"%@", self.searchType);
    
    // Follow search string
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(runSearch) name:NSControlTextDidChangeNotification object:self.searchField];
}

#pragma mark - Public accessors

- (BOOL)hasActivePanel
{
    return _hasActivePanel;
}

- (void)setHasActivePanel:(BOOL)flag
{
    if (_hasActivePanel != flag)
    {
        _hasActivePanel = flag;
        
        if (_hasActivePanel)
        {
            [self openPanel];
        }
        else
        {
            [self closePanel];
        }
    }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    self.hasActivePanel = NO;
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    if ([[self window] isVisible])
    {
        self.hasActivePanel = NO;
    }
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow *panel = [self window];
    NSRect statusRect = [self statusRectForWindow:panel];
    NSRect panelRect = [panel frame];
    
    CGFloat statusX = roundf(NSMidX(statusRect));
    CGFloat panelX = statusX - NSMinX(panelRect);
    
    self.backgroundView.arrowX = panelX;
    
    NSRect searchRect = [self.searchField frame];
    searchRect.size.width = NSWidth([self.backgroundView bounds]) - SEARCH_INSET * 2;
    searchRect.origin.x = SEARCH_INSET;
    searchRect.origin.y = NSHeight([self.backgroundView bounds]) - ARROW_HEIGHT - SEARCH_INSET - NSHeight(searchRect);
    
    if (NSIsEmptyRect(searchRect))
    {
        [self.searchField setHidden:YES];
    }
    else
    {
        [self.searchField setFrame:searchRect];
        [self.searchField setHidden:NO];
    }
    
    NSRect textRect = [self.textField frame];
    textRect.size.width = NSWidth([self.backgroundView bounds]) - SEARCH_INSET * 2;
    textRect.origin.x = SEARCH_INSET;
    textRect.size.height = NSHeight([self.backgroundView bounds]) - ARROW_HEIGHT - SEARCH_INSET * 3 - NSHeight(searchRect);
    textRect.origin.y = SEARCH_INSET;
    
    if (NSIsEmptyRect(textRect))
    {
        [self.textField setHidden:YES];
    }
    else
    {
        [self.textField setFrame:textRect];
        [self.textField setHidden:NO];
    }
}

#pragma mark - Keyboard

- (void)cancelOperation:(id)sender
{
    self.hasActivePanel = NO;
}

- (void)runSearch
{
    NSString *searchFormat = @"";
    NSString *searchString = [self.searchField stringValue];
    if ([searchString length] > 0)
    {
        searchFormat = NSLocalizedString(@"Search for ‘%@’…", @"Format for search request");
    }
    NSString *searchRequest = [NSString stringWithFormat:searchFormat, searchString];
    [self.textField setStringValue:searchRequest];
}

#pragma mark - UI Interaction

- (IBAction)performSearch:(NSButton *)sender {
    
    if ([self.searchField stringValue].length == 0) {
        [self.textField setStringValue:@"Search field is empty"];
        return;
    }
    
    // 1    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    NSString *unencodedSearchString = [self.searchField stringValue];
    NSString *encodedSearchString = [self urlEncode:unencodedSearchString];
    NSString *spotifyGetURL = [NSString stringWithFormat:@"https://api.spotify.com/v1/search?q=%@&type=%@", encodedSearchString, [self getSearchType]];
//    NSString *spotifyGetURL = [NSString stringWithFormat:@"https://api.spotify.com/v1/search?q=%@&type=artist", encodedSearchString];

    NSLog(@"spotify url: %@", spotifyGetURL);
    [manager GET:spotifyGetURL parameters:nil progress:nil success:^(NSURLSessionTask *task, id responseObject) {
//        NSLog(@"JSON: %@", responseObject);
        NSDictionary *itemInfomation = [responseObject objectForKey:[self getSearchTypePlural]];
        NSArray *items = [itemInfomation objectForKey:@"items"];
        if (items.count > 0) {
            NSDictionary *firstItem = [items objectAtIndex:0];
            NSLog(@"firstItem\n\n%@", firstItem);
            NSString *URI = [firstItem objectForKey:@"uri"];
            self.lastSearchedURI = URI;
            
            NSString *infoString = [NSString stringWithFormat:@"Found %@: %@", [self getSearchType], [firstItem objectForKey:@"name"]];
            if ([self.searchType isEqualToString:@"Track"]) {
                NSString *album = [[firstItem objectForKey:@"album"] objectForKey:@"name"];
                NSArray *artists = [firstItem objectForKey:@"artists"];
                if (artists.count > 0) {
                    NSString *artist = [[artists objectAtIndex:0] objectForKey:@"name"];
                    infoString = [infoString stringByAppendingString:[NSString stringWithFormat:@"\nAlbum: %@\nArtist: %@", album, artist]];
                }
            }
            [self.textField setStringValue:infoString];
        } else {
            [self.textField setStringValue:@"Couldn't find a match"];
        }
        
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        [self.textField setStringValue:@"Error searching Spotify API"];
    }];
    
}

- (IBAction)changeSearchType:(NSSegmentedControl *)sender {
    self.searchType = [self.searchTypeSegmentedControl labelForSegment:self.searchTypeSegmentedControl.selectedSegment];
    NSLog(@"%@", self.searchType);
}

- (NSString *)getSearchType
{
    if ([self.searchType isEqualToString:@"Track"]) {
        return SEARCH_TYPE_TRACK;
    } else if ([self.searchType isEqualToString:@"Album"]) {
        return SEARCH_TYPE_ALBUM;
    } else {
        return SEARCH_TYPE_ARTIST;
    }
}

- (NSString *)getSearchTypePlural
{
    if ([self.searchType isEqualToString:@"Track"]) {
        return SEARCH_TYPE_TRACKS_PLURAL;
    } else if ([self.searchType isEqualToString:@"Album"]) {
        return SEARCH_TYPE_ALBUMS_PLURAL;
    } else {
        return SEARCH_TYPE_ARTISTS_PLURAL;
    }
}

- (NSString *)urlEncode:(NSString *)string {
    NSMutableString *output = [NSMutableString string];
    const unsigned char *source = (const unsigned char *)[string UTF8String];
    int sourceLen = (int)strlen((const char *)source);
    for (int i = 0; i < sourceLen; ++i) {
        const unsigned char thisChar = source[i];
        if (thisChar == ' '){
            [output appendString:@"+"];
        } else if (thisChar == '.' || thisChar == '-' || thisChar == '_' || thisChar == '~' ||
                   (thisChar >= 'a' && thisChar <= 'z') ||
                   (thisChar >= 'A' && thisChar <= 'Z') ||
                   (thisChar >= '0' && thisChar <= '9')) {
            [output appendFormat:@"%c", thisChar];
        } else {
            [output appendFormat:@"%%%02X", thisChar];
        }
    }
    return output;
}

- (NSString *)getSpotifyScriptPath
{
    return [[NSBundle mainBundle] pathForResource:@"SpotifyControl" ofType:@""];
}

- (IBAction)copyToPasteBoard:(NSButton *)sender {

    if (self.lastSearchedURI.length > 0) {
        NSString *terminalCommand = [NSString stringWithFormat:@"spotify play %@", self.lastSearchedURI];
        BOOL success = [self writeToPasteBoard:terminalCommand];
        NSLog(@"Successful copy? %i", success);
        [self.textField setStringValue:@"Copied command to clipboard!"];
    }
}

- (BOOL) writeToPasteBoard:(NSString *)stringToWrite
{
    [[NSPasteboard generalPasteboard] declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    return [[NSPasteboard generalPasteboard] setString:stringToWrite forType:NSStringPboardType];
}

- (IBAction)playButtonPressed:(NSButton *)sender {
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [self getSpotifyScriptPath];
    task.arguments = @[@"play", self.lastSearchedURI];
    [task launch];
    //        [task waitUntilExit];
    
}

- (IBAction)pauseButtonPressed:(NSButton *)sender {
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [self getSpotifyScriptPath];
    task.arguments = @[@"pause"];
    [task launch];
    [task waitUntilExit];
}

#pragma mark - Public methods

- (NSRect)statusRectForWindow:(NSWindow *)window
{
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = NSZeroRect;
    
    StatusItemView *statusItemView = nil;
    if ([self.delegate respondsToSelector:@selector(statusItemViewForPanelController:)])
    {
        statusItemView = [self.delegate statusItemViewForPanelController:self];
    }
    
    if (statusItemView)
    {
        statusRect = statusItemView.globalRect;
        statusRect.origin.y = NSMinY(statusRect) - NSHeight(statusRect);
    }
    else
    {
        statusRect.size = NSMakeSize(STATUS_ITEM_VIEW_WIDTH, [[NSStatusBar systemStatusBar] thickness]);
        statusRect.origin.x = roundf((NSWidth(screenRect) - NSWidth(statusRect)) / 2);
        statusRect.origin.y = NSHeight(screenRect) - NSHeight(statusRect) * 2;
    }
    return statusRect;
}

- (void)openPanel
{
    NSWindow *panel = [self window];
    
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = [self statusRectForWindow:panel];

    NSRect panelRect = [panel frame];
    panelRect.size.width = PANEL_WIDTH;
    panelRect.size.height = POPUP_HEIGHT;
    panelRect.origin.x = roundf(NSMidX(statusRect) - NSWidth(panelRect) / 2);
    panelRect.origin.y = NSMaxY(statusRect) - NSHeight(panelRect);
    
    if (NSMaxX(panelRect) > (NSMaxX(screenRect) - ARROW_HEIGHT))
        panelRect.origin.x -= NSMaxX(panelRect) - (NSMaxX(screenRect) - ARROW_HEIGHT);
    
    [NSApp activateIgnoringOtherApps:NO];
    [panel setAlphaValue:0];
    [panel setFrame:statusRect display:YES];
    [panel makeKeyAndOrderFront:nil];
    
    NSTimeInterval openDuration = OPEN_DURATION;
    
    NSEvent *currentEvent = [NSApp currentEvent];
    if ([currentEvent type] == NSLeftMouseDown)
    {
        NSUInteger clearFlags = ([currentEvent modifierFlags] & NSDeviceIndependentModifierFlagsMask);
        BOOL shiftPressed = (clearFlags == NSShiftKeyMask);
        BOOL shiftOptionPressed = (clearFlags == (NSShiftKeyMask | NSAlternateKeyMask));
        if (shiftPressed || shiftOptionPressed)
        {
            openDuration *= 10;
            
            if (shiftOptionPressed)
                NSLog(@"Icon is at %@\n\tMenu is on screen %@\n\tWill be animated to %@",
                      NSStringFromRect(statusRect), NSStringFromRect(screenRect), NSStringFromRect(panelRect));
        }
    }
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:openDuration];
    [[panel animator] setFrame:panelRect display:YES];
    [[panel animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
    
    [panel performSelector:@selector(makeFirstResponder:) withObject:self.searchField afterDelay:openDuration];
}

- (void)closePanel
{
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:CLOSE_DURATION];
    [[[self window] animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];
    
    dispatch_after(dispatch_walltime(NULL, NSEC_PER_SEC * CLOSE_DURATION * 2), dispatch_get_main_queue(), ^{
        
        [self.window orderOut:nil];
    });
}

@end
