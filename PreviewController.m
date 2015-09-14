//
//  PreviewController.m
//  Notation
//
//  Created by Christian Tietze on 15.10.10.
//  Copyright 2010

#import "PreviewController.h"
#import "AppController.h" // TODO for the defines only, can you get around that?
#import "AppController_Preview.h"
#import "NSString_MultiMarkdown.h"
#import "NSString_Markdown.h"
#import "NSString_Marked.h"
#import "NSString_Textile.h"
#import "NoteObject.h"
#import "ETTransparentButtonCell.h"
#import "ETTransparentButton.h"
#import "BTTransparentScroller.h"

#define kDefaultMarkupPreviewVisible @"markupPreviewVisible"

@interface NSString (MIMEAdditions)
+ (NSString*)MIMEBoundary;
+ (NSString*)multipartMIMEStringWithDictionary:(NSDictionary*)dict;
@end

@implementation NSString (MIMEAdditions)
//this returns a unique boundary which is used in constructing the multipart MIME body of the POST request
+ (NSString*)MIMEBoundary
{
    static NSString* MIMEBoundary = nil;
    if(!MIMEBoundary)
        MIMEBoundary = [[NSString alloc] initWithFormat:@"----_=_nvALT_%@_=_----",[[NSProcessInfo processInfo] globallyUniqueString]];
    return MIMEBoundary;
}
//this create a correctly structured multipart MIME body for the POST request from a dictionary
+ (NSString*)multipartMIMEStringWithDictionary:(NSDictionary*)dict
{
    NSMutableString* result = [NSMutableString string];
    for (NSString* key in dict)
    {
        [result appendFormat:@"--%@\nContent-Disposition: form-data; name=\"%@\"\n\n%@\n",[NSString MIMEBoundary],key,[dict objectForKey:key]];
    }
    [result appendFormat:@"\n--%@--\n",[NSString MIMEBoundary]];
    return result;
}
@end

@implementation PreviewController

@synthesize preview;
@synthesize isPreviewOutdated;
@synthesize isPreviewSticky;

+(void)initialize
{
  NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO]
                                                          forKey:kDefaultMarkupPreviewVisible];

  [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
  /* Initialize webInspector. */
  [[NSUserDefaults standardUserDefaults] setBool:TRUE forKey:@"WebKitDeveloperExtras"];
  [[NSUserDefaults standardUserDefaults] synchronize];

}

-(id)init
{
    if ((self = [super initWithWindowNibName:@"MarkupPreview" owner:self])) {
        self.isPreviewOutdated = YES;
        self.isPreviewSticky = NO;
//        [[self class] createCustomFiles];
        BOOL showPreviewWindow = [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultMarkupPreviewVisible];
        if (showPreviewWindow) {
            [[self window] orderFront:self];
        }

        NSRect shCon = [[[self window] contentView]visibleRect];
        shCon.origin.x +=20;
        shCon.origin.y -= 2;
        shCon.size.width = 99;
        shCon.size.height = 28;
//        tabSwitcher = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
//        shCon.origin.x = [[[self window] contentView]visibleRect].origin.x + [[[self window] contentView]visibleRect].size.width - 80;
//        shCon.size.width = 56;
//        saveButton = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
//        shCon.origin.x -= 65;
//        shareButton = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
//        shCon.origin.x -= 65;
//        stickyPreviewButton = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
//        shCon.origin.x -= 65;
//        printPreviewButton = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
//        [tabSwitcher setTitle:@"View Source"];
//        [tabSwitcher setTarget:self];
//        [tabSwitcher setAction:@selector(switchTabs:)];
//        [tabSwitcher setAutoresizingMask:NSViewMaxXMargin];
//        [shareButton setTitle:@"Share"];
//        [shareButton setToolTip:@"Make this note available to the public on Peg.gd"];
//        [shareButton setTarget:self];
//        [shareButton setAction:@selector(shareAsk:)];
//        [shareButton setAutoresizingMask:NSViewMinXMargin];
//        [saveButton setTitle:@"Save"];
//        [saveButton setToolTip:@"Save the current preview as an HTML file"];
//        [saveButton setTarget:self];
//        [saveButton setAction:@selector(saveHTML:)];
//        [saveButton setAutoresizingMask:NSViewMinXMargin];
//        [stickyPreviewButton setTitle:@"Stick"];
//        [stickyPreviewButton setToolTip:@"Maintain current note in Preview, even if you switch to other notes."];
//        [stickyPreviewButton setTarget:self];
//        [stickyPreviewButton setAction:@selector(makePreviewSticky:)];
//        [stickyPreviewButton setAutoresizingMask:NSViewMinXMargin];
//        [printPreviewButton setTitle:@"Print"];
//        [printPreviewButton setToolTip:@"Print to Printer or PDF."];
//        [printPreviewButton setTarget:self];
//        [printPreviewButton setAction:@selector(printPreview:)];
//        [printPreviewButton setAutoresizingMask:NSViewMinXMargin];
//        [[[self window] contentView] addSubview:tabSwitcher];
//        [[[self window] contentView] addSubview:shareButton];
//        [[[self window] contentView] addSubview:saveButton];
//        [[[self window] contentView] addSubview:stickyPreviewButton];
//        [[[self window] contentView] addSubview:printPreviewButton];
        [tabView selectTabViewItem:[tabView tabViewItemAtIndex:0]];

        shCon = [shareConfirmation visibleRect];
        shCon.origin.x = shCon.size.width - 106;
        shCon.origin.y = 1;
        shCon.size.width = 81;
        shCon.size.height = 28;
        shareConfirm = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
        shCon.origin.x = [shareConfirmation visibleRect].origin.x + 25;
        shareCancel = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
        [shareConfirm setTitle:@"Yes"];
        [shareConfirm setTarget:self];
        [shareConfirm setAction:@selector(shareNote:)];
        [shareCancel setTitle:@"No, thanks"];
        [shareCancel setTarget:self];
        [shareCancel setAction:@selector(cancelShare:)];
        [shareConfirmation addSubview:shareCancel];
        [shareConfirmation addSubview:shareConfirm];

        shCon = [shareNotification visibleRect];
        shCon.size.width = 116;
        shCon.size.height = 28;
        shCon.origin.x = 70;
        viewOnWebButton = [[[ETTransparentButton alloc]initWithFrame:shCon] retain];
        [viewOnWebButton setTitle:@"View in Browser"];
        [viewOnWebButton setTarget:self];
        [viewOnWebButton setAction:@selector(openShareURL:)];
        [shareNotification addSubview:viewOnWebButton];
       // [[[self window] contentView] setNeedsDisplay:YES];

//		[preview setPolicyDelegate:self];
//		[preview setUIDelegate:self];
    }
    return self;
}

-(void)awakeFromNib
{
	cssString = [[[self class] css] retain];
    htmlString = [[[self class] html] retain];
	lastNote = [[NSApp delegate] selectedNoteObject];
    [sourceView setTextContainerInset:NSMakeSize(10.0,12.0)];
    NSScrollView *scrlView=[sourceView enclosingScrollView];
    if (!IsLionOrLater) {
    NSRect vsRect=[[scrlView verticalScroller]frame];
    BTTransparentScroller *theScroller=[[BTTransparentScroller alloc]initWithFrame:vsRect];
    [scrlView setVerticalScroller:theScroller];
    [theScroller release];
    }
    [scrlView setScrollsDynamically:YES];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if (IsLionOrLater) {
        [scrlView setHorizontalScrollElasticity:NSScrollElasticityNone];
        [scrlView setVerticalScrollElasticity:NSScrollElasticityAutomatic];
        [scrlView setScrollerStyle:NSScrollerStyleOverlay];
    }
#endif
}

//this returns a nice name for the method in the JavaScript environment
+(NSString*)webScriptNameForSelector:(SEL)sel
{
    if(sel == @selector(logJavaScriptString:))
        return @"log";
    return nil;
}

//this allows JavaScript to call the -logJavaScriptString: method
+ (BOOL)isSelectorExcludedFromWebScript:(SEL)sel
{
    if(sel == @selector(logJavaScriptString:))
        return NO;
    return YES;
}

//this is a simple log command
- (void)logJavaScriptString:(NSString*) logText
{
    NSLog(@"JavaScript: %@",logText);
}

//this is called as soon as the script environment is ready in the webview
- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowScriptObject forFrame:(WebFrame *)frame
{
    //add the controller to the script environment
    //the "Cocoa" object will now be available to JavaScript
    [windowScriptObject setValue:self forKey:@"Cocoa"];
}

// Above webView methods from <http://stackoverflow.com/questions/2288582/embedded-webkit-script-callbacks-how/2293305#2293305>

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
	NSString *targetURL = [[request URL] scheme];

    if (![[actionInformation objectForKey:@"WebActionNavigationTypeKey"] isEqualToNumber:[NSNumber numberWithInt:5]]) {
				[[NSWorkspace sharedWorkspace] openURL:[request URL]];
				[listener ignore];
		} else {
				[listener use];
		}
}

- (void)webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request newFrameName:(NSString *)frameName decisionListener:(id<WebPolicyDecisionListener>)listener {
	NSLog(@"NEW WIN ACTION SENDER: %@",sender);
    [[NSWorkspace sharedWorkspace] openURL:[actionInformation objectForKey:WebActionOriginalURLKey]];
    [listener ignore];
}

-(void)requestPreviewUpdate:(NSNotification *)notification
{
    if (![[self window] isVisible]) {
        self.isPreviewOutdated = YES;
        return;
    }

    if (self.isPreviewSticky) {
      return;
    }

    AppController *app = [notification object];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview:) object:app];

    [self performSelector:@selector(preview:) withObject:app afterDelay:0.05];
}

- (BOOL)previewIsVisible{
	return [[self window] isVisible];
}

-(void)togglePreview:(id)sender
{

    NSWindow *wnd = [self window];
    if ([wnd isVisible]) {
      if (attachedWindow) {
        [[shareButton window] removeChildWindow:attachedWindow];
        [attachedWindow orderOut:self];
        [attachedWindow release];
        attachedWindow = nil;
        [shareURL release];
      }
//      // TODO: should the "stuck" note remain stuck when preview is closed?
//      if (self.isPreviewSticky)
//        [self makePreviewNotSticky:self];
      [wnd orderOut:self];
    } else {
      if (self.isPreviewOutdated) {
          // TODO high coupling; too many assumptions on architecture:
          [self performSelector:@selector(preview:) withObject:[[NSApplication sharedApplication] delegate] afterDelay:0.0];
      }
      [tabView selectTabViewItem:[tabView tabViewItemAtIndex:0]];
      [tabSwitcher setTitle:@"View Source"];

      [wnd orderFront:self];
    }

    // save visibility to defaults
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:[wnd isVisible]]
                                              forKey:kDefaultMarkupPreviewVisible];
}

-(void)windowWillClose:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO]
                                              forKey:kDefaultMarkupPreviewVisible];
	NSMenu *previewMenu = [[[NSApp mainMenu] itemWithTitle:@"Preview"] submenu];
	[[previewMenu itemWithTitle:@"Toggle Preview Window"]setState:0];
}

+(NSString*)css {
		NSFileManager *mgr = [NSFileManager defaultManager];
		NSString *folder = [[NSFileManager defaultManager] applicationSupportDirectory];
		NSString *cssFileName = @"custom.css";
		NSString *customCSSPath = [folder stringByAppendingPathComponent: cssFileName];
		if ([mgr fileExistsAtPath:customCSSPath]) {
				return [NSString stringWithContentsOfFile:customCSSPath
																				 encoding:NSUTF8StringEncoding
																						error:NULL];
		} else {
				NSString *cssPath = [[NSBundle mainBundle] pathForResource:@"custom" ofType:@"css" inDirectory:nil];
				return [NSString stringWithContentsOfFile:cssPath encoding:NSUTF8StringEncoding error:nil];
		}

		//	if (![mgr fileExistsAtPath:customCSSPath]) {
		//		[[self class] createCustomFiles];
		//	}


}

+(NSString*)html {
		NSFileManager *mgr = [NSFileManager defaultManager];

		NSString *folder = [[NSFileManager defaultManager] applicationSupportDirectory];
		NSString *htmlFileName = @"template.html";
		NSString *customHTMLPath = [folder stringByAppendingPathComponent: htmlFileName];
	  if ([mgr fileExistsAtPath:customHTMLPath]) {
				return [NSString stringWithContentsOfFile:customHTMLPath
																				 encoding:NSUTF8StringEncoding
																						error:NULL];
		} else {
				NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"template" ofType:@"html" inDirectory:nil];
				return [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
		}
		//	if (![mgr fileExistsAtPath:customHTMLPath]) {
		//		[[self class] createCustomFiles];
		//	}
}

-(void)preview:(id)object
{
	if (self.isPreviewSticky) {
    return;
  }
		NSString *lastScrollPosition = [preview stringByEvaluatingJavaScriptFromString:@"document.getElementsByTagName('body')[0].scrollTop"];
//	NSString *lastScrollPosition = [[preview windowScriptObject] evaluateWebScript:@"document.getElementsByTagName('body')[0].scrollTop"];
	AppController *app = object;
	NSString *rawString = [app noteContent];
	SEL mode = [self markupProcessorSelector:[app currentPreviewMode]];
	NSString *processedString = [NSString performSelector:mode withObject:rawString];
  NSString *previewString = processedString;
	NSMutableString *outputString = [NSMutableString stringWithString:(NSString *)htmlString];
	NSString *noteTitle =  ([app selectedNoteObject]) ? [NSString stringWithFormat:@"%@",titleOfNote([app selectedNoteObject])] : @"";

	if (lastNote == [app selectedNoteObject]) {
		NSString *restoreScrollPosition = [NSString stringWithFormat:@"\n<script>var body = document.getElementsByTagName('body')[0],oldscroll = %@;body.scrollTop = oldscroll;</script>",lastScrollPosition];
		previewString = [processedString stringByAppendingString:restoreScrollPosition];
	} else {
		[cssString release];
		[htmlString release];
		cssString = [[[self class] css] retain];
		htmlString = [[[self class] html] retain];
		lastNote = [app selectedNoteObject];
	}
		NSString *nvSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];

	[outputString replaceOccurrencesOfString:@"{%support%}" withString:nvSupportPath options:0 range:NSMakeRange(0, [outputString length])];
	[outputString replaceOccurrencesOfString:@"{%title%}" withString:noteTitle options:0 range:NSMakeRange(0, [outputString length])];
	[outputString replaceOccurrencesOfString:@"{%content%}" withString:previewString options:0 range:NSMakeRange(0, [outputString length])];
	[outputString replaceOccurrencesOfString:@"{%style%}" withString:cssString options:0 range:NSMakeRange(0, [outputString length])];

	[[preview mainFrame] loadHTMLString:outputString baseURL:nil];
  [[self window] setTitle:noteTitle];

	[sourceView replaceCharactersInRange:NSMakeRange(0, [[sourceView string] length]) withString:processedString];
    self.isPreviewOutdated = NO;
}

-(SEL)markupProcessorSelector:(NSInteger)previewMode
{
    if (previewMode == MarkdownPreview) {
		previewMode = MultiMarkdownPreview;
        return @selector(stringWithProcessedMarked:);
    } else if (previewMode == MultiMarkdownPreview) {
        return @selector(stringWithProcessedMarked:);
    } else if (previewMode == TextilePreview) {
        return @selector(stringWithProcessedTextile:);
    }

    return nil;
}

+ (void) createCustomFiles
{
		NSFileManager *fileManager = [NSFileManager defaultManager];

		NSString *folder = [[NSFileManager defaultManager] applicationSupportDirectory];
		if ([fileManager fileExistsAtPath: folder] == NO)
		{
				[fileManager createDirectoryAtPath: folder attributes: nil];

		}

		NSString *cssFileName = @"custom.css";
		NSString *cssFile = [folder stringByAppendingPathComponent: cssFileName];

		if ([fileManager fileExistsAtPath:cssFile] == NO)
		{
				NSString *cssPath = [[NSBundle mainBundle] pathForResource:@"customclean" ofType:@"css" inDirectory:nil];
				NSString *cssString = [NSString stringWithContentsOfFile:cssPath encoding:NSUTF8StringEncoding error:nil];
				NSData *cssData = [NSData dataWithBytes:[cssString UTF8String] length:[cssString length]];
				[fileManager createFileAtPath:cssFile contents:cssData attributes:nil];
    }

		NSString *htmlFileName = @"template.html";
		NSString *htmlFile = [folder stringByAppendingPathComponent: htmlFileName];

		if ([fileManager fileExistsAtPath:htmlFile] == NO)
		{
				NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"templateclean" ofType:@"html" inDirectory:nil];
				NSString *htmlString = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
				NSData *htmlData = [NSData dataWithBytes:[htmlString UTF8String] length:[htmlString length]];
				[fileManager createFileAtPath:htmlFile contents:htmlData attributes:nil];
    }

}

- (NSString *)urlEncodeValue:(NSString *)str
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)str, NULL, CFSTR("?=&+"), kCFStringEncodingUTF8);
	return [result autorelease];
}

-(IBAction)makePreviewSticky:(id)sender
{
  self.isPreviewSticky = YES;
//  [[preview window] setTitle:@"Locked"];
  [stickyPreviewButton setState:YES];
  [stickyPreviewButton setToolTip:@"Return the preview to normal functionality."];
  [stickyPreviewButton setAction:@selector(makePreviewNotSticky:)];
  [shareButton setEnabled:NO];
  [saveButton setEnabled:NO];
  [[self window] setHidesOnDeactivate:NO];
}

-(IBAction)makePreviewNotSticky:(id)sender
{
  self.isPreviewSticky = NO;
  [[preview window] setTitle:@"Preview"];
  [stickyPreviewButton setState:NO];
  [stickyPreviewButton setToolTip:@"Maintain current note in Preview, even if you switch to other notes."];
  [stickyPreviewButton setAction:@selector(makePreviewSticky:)];
  [shareButton setEnabled:YES];
  [saveButton setEnabled:YES];
  self.isPreviewOutdated = YES;
  [self performSelector:@selector(preview:) withObject:[[NSApplication sharedApplication] delegate] afterDelay:0.0];
  [[self window] setHidesOnDeactivate:YES];
}

-(IBAction)printPreview:(id)sender
{
  NSPrintInfo* printInfo = [NSPrintInfo sharedPrintInfo];

  [printInfo setHorizontallyCentered:YES];
  [printInfo setVerticallyCentered:NO];
  [[[[preview mainFrame] frameView] documentView] print:nil];
}

-(IBAction)shareNote:(id)sender
{
  AppController *app = [NSApp delegate];
	NSString *noteTitle = [NSString stringWithFormat:@"%@",titleOfNote([app selectedNoteObject])];
  NSString *rawString = [app noteContent];
  SEL mode = [self markupProcessorSelector:[app currentPreviewMode]];
  NSString *processedString = [NSString performSelector:mode withObject:rawString];


	NSMutableURLRequest *request = [[NSMutableURLRequest alloc]
                                  initWithURL:
                                  [NSURL URLWithString:@"http://peg.gd/nvapi.php"]];
  [request setHTTPMethod:@"POST"];
  [request addValue:@"8bit" forHTTPHeaderField:@"Content-Transfer-Encoding"];
  [request addValue: [NSString stringWithFormat:@"multipart/form-data; boundary=%@",[NSString MIMEBoundary]] forHTTPHeaderField: @"Content-Type"];
  NSDictionary* postData = [NSDictionary dictionaryWithObjectsAndKeys:
                            @"8c4205ec33d8f6caeaaaa0c10a14138c", @"key",
                            noteTitle, @"title",
                            processedString, @"body",
                            nil];
  [request setHTTPBody: [[NSString multipartMIMEStringWithDictionary: postData] dataUsingEncoding: NSUTF8StringEncoding]];
	NSHTTPURLResponse * response = nil;
	NSError * error = nil;
	NSData * responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	NSString * responseString = [[[NSString alloc] initWithData:responseData encoding:NSASCIIStringEncoding] autorelease];
	NSLog(@"RESPONSE STRING: %@", responseString);
	NSLog(@"%d",response.statusCode);
	shareURL = [[NSString stringWithString:responseString] retain];
	if (response.statusCode == 200) {
		[self showShareURL:[NSString stringWithFormat:@"View %@",shareURL] isError:NO];
	} else {
		[self showShareURL:@"Error connecting" isError:YES];
	}

	[request release];

}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [receivedData setLength:0];
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSLog(@"Succeeded! Received %d bytes of data",[receivedData length]);

	NSString * responseString = [[[NSString alloc] initWithData:receivedData encoding:NSASCIIStringEncoding] autorelease];
	NSLog(@"RESPONSE STRING: %@", responseString);
    [receivedData release];
}

- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	if (returnCode == NSFileHandlingPanelOKButton) {

		AppController *app = [[NSApplication sharedApplication] delegate];
		NSString *rawString = [app noteContent];
		NSString *processedString = [[[NSString alloc] init] autorelease];

		if ([app currentPreviewMode] == MarkdownPreview) {
			processedString = [NSString stringWithProcessedMarkdown:rawString];
		} else if ([app currentPreviewMode] == MultiMarkdownPreview) {
			//processedString = ( [includeTemplate state] == NSOnState ) ? [NSString documentWithProcessedMultiMarkdown:rawString] : [NSString xhtmlWithProcessedMultiMarkdown:rawString];
            processedString = [NSString stringWithProcessedMarked:rawString];
		} else if ([app currentPreviewMode] == TextilePreview) {
			processedString = ( [includeTemplate state] == NSOnState ) ? [NSString documentWithProcessedTextile:rawString] : [NSString xhtmlWithProcessedTextile:rawString];
		}
    NSURL *file = [sheet URL];
    NSError *error;
    [processedString writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
  }
}

-(IBAction)saveHTML:(id)sender
{
	if (!accessoryView) {
		if (![NSBundle loadNibNamed:@"SaveHTMLPreview" owner:self]) {
			NSLog(@"Failed to load SaveHTMLPreview.nib");
			NSBeep();
			return;
		}

	}
	// TODO high coupling; too many assumptions on architecture:
	AppController *app = [NSApp delegate];

	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setAccessoryView:accessoryView];
	[savePanel setCanCreateDirectories:YES];
	[savePanel setCanSelectHiddenExtension:YES];

	NSArray *fileTypes = [[NSArray alloc] initWithObjects:@"html",@"xhtml",@"htm",nil];
	[savePanel setAllowedFileTypes:fileTypes];


  NSString *rawString = [app noteContent];
  NSString *xhtmlOutput = [NSString xhtmlWithProcessedMultiMarkdown:rawString];
  if ([xhtmlOutput hasPrefix:@"<?xml version="]) {
    [includeTemplate setState:0];
    [includeTemplate setEnabled:NO];
    [templateNote setStringValue:@"Template embed unavailable because your note will render as a full XHTML document"];
  } else {
    [includeTemplate setEnabled:YES];
    [templateNote setStringValue:@"Select this to embed the ouput within your current preview HTML and CSS"];
  }

	NSString *noteTitle =  ([app selectedNoteObject]) ? [NSString stringWithFormat:@"%@",titleOfNote([app selectedNoteObject])] : @"";
	[savePanel beginSheetForDirectory:nil file:noteTitle modalForWindow:[self window] modalDelegate:self
					   didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];


	[fileTypes release];

}

-(IBAction)switchTabs:(id)sender
{
	int tabSelection = [tabView indexOfTabViewItem:[tabView selectedTabViewItem]];

	if (tabSelection == 0) {
		[tabSwitcher setTitle:@"View Preview"];
		[tabView selectTabViewItem:[tabView tabViewItemAtIndex:1]];
	} else {
		[tabSwitcher setTitle:@"View Source"];
		[tabView selectTabViewItem:[tabView tabViewItemAtIndex:0]];
	}
}

- (IBAction)shareAsk:(id)sender
{
	if (!confirmWindow && !attachedWindow) {
        int side = 3;
        NSPoint buttonPoint = NSMakePoint(NSMidX([shareButton frame]),
                                          NSMidY([shareButton frame]));
        confirmWindow = [[MAAttachedWindow alloc] initWithView:shareConfirmation
                                                attachedToPoint:buttonPoint
                                                       inWindow:[shareButton window]
                                                         onSide:side
                                                     atDistance:15.0f];
        [confirmWindow setBorderColor:[NSColor colorWithCalibratedHue:0.278 saturation:0.000 brightness:0.871 alpha:0.950]];
        [confirmWindow setBackgroundColor:[NSColor colorWithCalibratedRed:0.134 green:0.134 blue:0.134 alpha:0.950]];
        [confirmWindow setViewMargin:3.0f];
        [confirmWindow setBorderWidth:1.0f];
        [confirmWindow setCornerRadius:10.0f];
        [confirmWindow setHasArrow:YES];
        [confirmWindow setDrawsRoundCornerBesideArrow:YES];
        [confirmWindow setArrowBaseWidth:10.0f];
        [confirmWindow setArrowHeight:6.0f];

        [[shareButton window] addChildWindow:confirmWindow ordered:NSWindowAbove];

    } else {
		if (confirmWindow)
			[self cancelShare:self];
		else if (attachedWindow)
			[self hideShareURL:self];
	}
}

- (void)showShareURL:(NSString *)url isError:(BOOL)isError
{
	if (confirmWindow) {
		[[shareButton window] removeChildWindow:confirmWindow];
		[confirmWindow orderOut:self];
		[confirmWindow release];
		confirmWindow = nil;
	}
		// Attach/detach window
    if (!attachedWindow) {
        int side = 3;
        NSPoint buttonPoint = NSMakePoint(NSMidX([shareButton frame]),
                                          NSMidY([shareButton frame]));
        attachedWindow = [[MAAttachedWindow alloc] initWithView:shareNotification
                                                attachedToPoint:buttonPoint
                                                       inWindow:[shareButton window]
                                                         onSide:side
                                                     atDistance:15.0f];
        [attachedWindow setBorderColor:[NSColor colorWithCalibratedHue:0.278 saturation:0.000 brightness:0.871 alpha:0.950]];
        [attachedWindow setBackgroundColor:[NSColor colorWithCalibratedRed:0.134 green:0.134 blue:0.134 alpha:0.950]];
        [attachedWindow setViewMargin:3.0f];
        [attachedWindow setBorderWidth:1.0f];
        [attachedWindow setCornerRadius:10.0f];
        [attachedWindow setHasArrow:YES];
        [attachedWindow setDrawsRoundCornerBesideArrow:YES];
        [attachedWindow setArrowBaseWidth:10.0f];
        [attachedWindow setArrowHeight:6.0f];

        [[shareButton window] addChildWindow:attachedWindow ordered:NSWindowAbove];

    }

	if (isError) {
		[urlTextField setStringValue:url];
		[viewOnWebButton setHidden:YES];
	} else {
		NSPasteboard *pb = [NSPasteboard generalPasteboard];
		NSArray *types = [NSArray arrayWithObjects:NSStringPboardType, nil];
		[pb declareTypes:types owner:self];
		[pb setString:shareURL forType:NSStringPboardType];
		[urlTextField setHidden:NO];
        [urlTextField setStringValue:[@"Copied " stringByAppendingString:[shareURL stringByAppendingString:@" to clipboard"]]];
		//[viewOnWebButton setTitle:url];
	}


}

-(void)closeShareURLView
{
	[[shareButton window] removeChildWindow:attachedWindow];
	[attachedWindow orderOut:self];
	[attachedWindow release];
	attachedWindow = nil;
	[shareURL release];
}

- (IBAction)hideShareURL:(id)sender
{
	[self closeShareURLView];
}

- (IBAction)cancelShare:(id)sender
{
	[[shareButton window] removeChildWindow:confirmWindow];
	[confirmWindow orderOut:self];
	[confirmWindow release];
	confirmWindow = nil;
}

- (IBAction)openShareURL:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:shareURL]];
	[[shareButton window] removeChildWindow:attachedWindow];
	[attachedWindow orderOut:self];
	[attachedWindow release];
	attachedWindow = nil;
	[shareURL release];
}

- (void)dealloc {
  [htmlString release];
  [cssString release];
  [lastNote release];
  [shareButton release];
  [saveButton release];
  [tabSwitcher release];
  [viewOnWebButton release];
  [shareCancel release];
  [shareConfirm release];
  [super dealloc];
}

@end
