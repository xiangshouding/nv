/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 - Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 - Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided with
 the distribution.
 - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse
 or promote products derived from this software without specific prior written permission. */
//ET NV4

#import "NSTextFinder.h"
#import "AppController.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "AlienNoteImporter.h"
#import "AppController_Importing.h"
#import "NotationPrefs.h"
#import "PrefsWindowController.h"
#import "NoteAttributeColumn.h"
#import "NotationSyncServiceManager.h"
#import "NotationDirectoryManager.h"
#import "NotationFileManager.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "EncodingsManager.h"
#import "ExporterManager.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "BufferUtils.h"
#import "LinkingEditor.h"
#import "EmptyView.h"
#import "DualField.h"
#import "TitlebarButton.h"
#import "RBSplitView/RBSplitView.h"
//#import "AugmentedScrollView.h"
#import "BookmarksController.h"
#import "SyncSessionController.h"
#import "MultiplePageView.h"
#import "InvocationRecorder.h"
#import "LinearDividerShader.h"
#import "SecureTextEntryManager.h"
#import "TagEditingManager.h"
#import "NotesTableHeaderCell.h"
#import "DFView.h"
#import "StatusItemView.h"
#import "ETContentView.h"
#import "PreviewController.h"
#import "ETClipView.h"
#import "ETScrollView.h"
#import "NSFileManager+DirectoryLocations.h"
#import "nvaDevConfig.h"
#import <Sparkle/SUUpdater.h>

#define NSApplicationPresentationAutoHideMenuBar (1 <<  2)
#define NSApplicationPresentationHideMenuBar (1 <<  3)
//#define NSApplicationPresentationAutoHideDock (1 <<  0)
#define NSApplicationPresentationHideDock (1 <<  1)
//#define NSApplicationActivationPolicyAccessory

#define kSparkleUpdateFeedForLions @"http://abyss.designheresy.com/nvalt2/nvalt2main.xml"
#define kSparkleUpdateFeedForSnowLeopard @"http://abyss.designheresy.com/nvalt2/nvalt2snowleopardfeed.xml"
//http://abyss.designheresy.com/nvalt/betaupdates.xml



//#define NSTextViewChangedNotification @"TextViewHasChangedContents"
//#define kDefaultMarkupPreviewMode @"markupPreviewMode"
#define kDualFieldHeight 35.0


NSWindow *normalWindow;
int ModFlagger;
int popped;
BOOL splitViewAwoke;


@implementation AppController

@synthesize isEditing;

//an instance of this class is designated in the nib as the delegate of the window, nstextfield and two nstextviews
/*
 + (void)initialize
 {
 NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:MultiMarkdownPreview] forKey:kDefaultMarkupPreviewMode];
 
 [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
 } // initialize*/


- (id)init {
    self = [super init];
    if (self) {
        hasLaunched=NO;
        
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDockIcon"]){
            if (IsLionOrLater) {
                ProcessSerialNumber psn = { 0, kCurrentProcess };
                OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToUIElementApplication);
                if( returnCode != 0) {
                    NSLog(@"Could not bring the application to front. Error %d", returnCode);
                }                
            }
            if (![[NSUserDefaults standardUserDefaults] boolForKey:@"StatusBarItem"]) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"StatusBarItem"];
            }
        }else{
            if (!IsLionOrLater) {
                enum {NSApplicationActivationPolicyRegular};
                [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];
            }
        
        }
        
        splitViewAwoke = NO;
        windowUndoManager = [[NSUndoManager alloc] init];
        
        previewController = [[PreviewController alloc] init];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        
        NSString *folder = [[NSFileManager defaultManager] applicationSupportDirectory];
        
        if ([fileManager fileExistsAtPath: folder] == NO)
        {
//            [fileManager createDirectoryAtPath: folder attributes: nil];
            [fileManager createDirectoryAtPath: folder withIntermediateDirectories: TRUE attributes: nil error: Nil];
        }
        
        NSNotificationCenter *nc=[NSNotificationCenter defaultCenter];
        [nc addObserver:previewController selector:@selector(requestPreviewUpdate:) name:@"TextViewHasChangedContents" object:self];
        [nc addObserver:self selector:@selector(toggleAttachedWindow:) name:@"NVShouldActivate" object:nil];
        [nc addObserver:self selector:@selector(toggleAttachedMenu:) name:@"StatusItemMenuShouldDrop" object:nil];
        [nc addObserver:self selector:@selector(togDockIcon:) name:@"AppShouldToggleDockIcon" object:nil];
        [nc addObserver:self selector:@selector(toggleStatusItem:) name:@"AppShouldToggleStatusItem" object:nil];
        
        [nc addObserver:self selector:@selector(resetModTimers:) name:@"ModTimersShouldReset" object:nil];
        [nc addObserver:self selector:@selector(releaseTagEditor:) name:@"TagEditorShouldRelease" object:nil];
        // Setup URL Handling
        NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
        [appleEventManager setEventHandler:self andSelector:@selector(handleGetURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
        
        //	dividerShader = [[LinearDividerShader alloc] initWithStartColor:[NSColor colorWithCalibratedWhite:0.988 alpha:1.0]
        //														   endColor:[NSColor colorWithCalibratedWhite:0.875 alpha:1.0]];
        dividerShader = [[[LinearDividerShader alloc] initWithBaseColors:self] retain];
        isCreatingANote = isFilteringFromTyping = typedStringIsCached = NO;
        typedString = @"";
        self.isEditing=NO;
    }
    return self;
}

- (void)awakeFromNib {
    theFieldEditor = [[[NSTextView alloc]initWithFrame:[window frame]] retain];
	[theFieldEditor setFieldEditor:YES];
    // [theFieldEditor setDelegate:self];
    [self updateFieldAttributes];
    
	[NSApp setDelegate:self];
	[window setDelegate:self];
    
    //ElasticThreads>> set up the rbsplitview programatically to remove dependency on IBPlugin
    splitView = [[[RBSplitView alloc] initWithFrame:[mainView frame] andSubviews:2] retain];
    [splitView setAutosaveName:@"centralSplitView" recursively:NO];
    [splitView setDelegate:self];
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(1.0,1.0)] autorelease];
    [image lockFocus];
    [[NSColor clearColor] set];
    
    NSRectFill(NSMakeRect(0.0,0.0,1.0,1.0));
    [image unlockFocus];
    [image setFlipped:YES];
    [splitView setDivider:image];
    
    [splitView setDividerThickness:8.75f];
    [splitView setAutoresizesSubviews:YES];
    [splitView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [mainView addSubview:splitView];
    //[mainView setNextResponder:field];//<<--
    [splitView setNextKeyView:notesTableView];
    notesSubview = [[splitView subviewAtPosition:0] retain];
	[notesSubview setMinDimension: 80.0
                  andMaxDimension:600.0];
    [notesSubview setCanCollapse:YES];
    [notesSubview setAutoresizesSubviews:YES];
    [notesSubview addSubview:notesScrollView];
    splitSubview = [[splitView subviewAtPosition:1] retain];
    [notesScrollView setFrame:[notesSubview frame]];
    [notesScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [splitSubview setMinDimension:1 andMaxDimension:0];
    [splitSubview setCanCollapse:NO];
    [splitSubview setAutoresizesSubviews:YES];
    [splitSubview addSubview:textScrollView];
    
    id docView = [[textScrollView documentView] retain];
    ETClipView *newClipView = [[ETClipView alloc] initWithFrame:[[textScrollView contentView] frame]];
    [newClipView setDrawsBackground:NO];
    //    [newClipView setBackgroundColor:[self backgrndColor]];
    [textScrollView setContentView:(ETClipView *)newClipView];
    [newClipView release];
    [textScrollView setDocumentView:textView];
    [docView release];
    
    [textScrollView setFrame:[splitSubview frame]];
    //    [textScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    
    [splitView adjustSubviews];
    [splitView needsDisplay];
    [mainView setNeedsDisplay:YES];
    splitViewAwoke = YES;
    
	[notesScrollView setBorderType:NSNoBorder];
	[textScrollView setBorderType:NSNoBorder];
	prefsController = [GlobalPrefs defaultPrefs];
	[NSColor setIgnoresAlpha:NO];
	
	//For ElasticThreads' fullscreen implementation.
	[self setDualFieldInToolbar];
	[notesTableView setDelegate:self];
	[field setDelegate:self];
	[textView setDelegate:self];
    
	//set up temporary FastListDataSource containing false visible notes
    
	//this will not make a difference
	[window useOptimizedDrawing:YES];
	
    
	//[window makeKeyAndOrderFront:self];
	//[self setEmptyViewState:YES];
	
	// Create elasticthreads' NSStatusItem.
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"StatusBarItem"]) {
		[self setUpStatusBarItem];
	}
	
	currentPreviewMode = [[NSUserDefaults standardUserDefaults] integerForKey:@"markupPreviewMode"];
    if (currentPreviewMode == MarkdownPreview) {
        [multiMarkdownPreview setState:NSOnState];
    } else if (currentPreviewMode == MultiMarkdownPreview) {
        [multiMarkdownPreview setState:NSOnState];
    } else if (currentPreviewMode == TextilePreview) {
        [textilePreview setState:NSOnState];
    }
	
	outletObjectAwoke(self);
}

//really need make AppController a subclass of NSWindowController and stick this junk in windowDidLoad
- (void)setupViewsAfterAppAwakened {
	static BOOL awakenedViews = NO;
	if (!awakenedViews) {
		//NSLog(@"all (hopefully relevant) views awakend!");
		[self _configureDividerForCurrentLayout];
		[splitView restoreState:YES];
		if ([notesSubview dimension]<200.0) {
			if ([splitView isVertical]) {   ///vertical means "Horiz layout"/notes list is to the left of the note body
				if (([splitView frame].size.width < 600.0) && ([splitView frame].size.width - 400 > [notesSubview dimension])) {
					[notesSubview setDimension:[splitView frame].size.width-400.0];
				}else if ([splitView frame].size.width >= 600.0) {
					[notesSubview setDimension:200.0];
				}
			}else{
				if (([splitView frame].size.height < 600.0) && ([splitView frame].size.height - 400 > [notesSubview dimension])) {
					[notesSubview setDimension:[splitView frame].size.height-450.0];
				}else if ([splitView frame].size.height >= 600.0){
					[notesSubview setDimension:150.0];
				}
			}
		}
		[splitView adjustSubviews];
		[splitSubview addSubview:editorStatusView positioned:NSWindowAbove relativeTo:splitSubview];
		[editorStatusView setFrame:[textScrollView frame]];
		
		[notesTableView restoreColumns];
		
		[field setNextKeyView:textView];
		[textView setNextKeyView:field];
		[window setAutorecalculatesKeyViewLoop:NO];
		
        [self updateRTL];
        
		
		[self setEmptyViewState:YES];
		ModFlagger = 0;
        popped = 0;
		userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		if (userScheme==0) {
			[self setBWColorScheme:self];
		}else if (userScheme==1) {
			[self setLCColorScheme:self];
		}else if (userScheme==2) {
			[self setUserColorScheme:self];
		}
		//this is necessary on 10.3; keep just in case
		[splitView display];
        
        
        //        if (![NSApp isActive]) {  probably a mistake to have put this in the begin with
        //            [NSApp activateIgnoringOtherApps:YES];
        //        }
		awakenedViews = YES;
	}
}

//what a hack
void outletObjectAwoke(id sender) {
	static NSMutableSet *awokenOutlets = nil;
	if (!awokenOutlets) awokenOutlets = [[NSMutableSet alloc] initWithCapacity:5];
    
    
	[awokenOutlets addObject:sender];
	
	AppController* appDelegate = (AppController*)[NSApp delegate];
	
	if ((appDelegate) && ([awokenOutlets containsObject:appDelegate] &&
                          [awokenOutlets containsObject:appDelegate->notesTableView] &&
                          [awokenOutlets containsObject:appDelegate->textView] &&
                          [awokenOutlets containsObject:appDelegate->editorStatusView]) &&(splitViewAwoke)) {
		// && [awokenOutlets containsObject:appDelegate->splitView])
		[appDelegate setupViewsAfterAppAwakened];
	}
}

- (void)runDelayedUIActionsAfterLaunch {
	[[prefsController bookmarksController] setAppController:self];
	[[prefsController bookmarksController] restoreWindowFromSave];
	[[prefsController bookmarksController] updateBookmarksUI];
	[self updateNoteMenus];
	[textView setupFontMenu];
	[prefsController registerAppActivationKeystrokeWithTarget:self selector:@selector(toggleNVActivation:)];
	[notationController updateLabelConnectionsAfterDecoding];
	[notationController checkIfNotationIsTrashed];
	[[SecureTextEntryManager sharedInstance] checkForIncompatibleApps];
	
	//connect sparkle programmatically to avoid loading its framework at nib awake;
	
	if (!NSClassFromString(@"SUUpdater")) {
		NSString *frameworkPath = [[[NSBundle bundleForClass:[self class]] privateFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
		if ([[NSBundle bundleWithPath:frameworkPath] load]) {
			SUUpdater *updater =[NSClassFromString(@"SUUpdater") performSelector:@selector(sharedUpdater)];
            if (IsLionOrLater) {
                [updater setFeedURL:[NSURL URLWithString:kSparkleUpdateFeedForLions]];
            }else{
                [updater setFeedURL:[NSURL URLWithString:kSparkleUpdateFeedForSnowLeopard]];
            }
			[sparkleUpdateItem setTarget:updater];
			[sparkleUpdateItem setAction:@selector(checkForUpdates:)];
			NSMenuItem *siSparkle = [statBarMenu itemWithTag:902];
			[siSparkle setTarget:updater];
			[siSparkle setAction:@selector(checkForUpdates:)];
			if (![[prefsController notationPrefs] firstTimeUsed]) {
				//don't do anything automatically on the first launch; afterwards, check every 4 days, as specified in Info.plist
//				SEL checksSEL = @selector(setAutomaticallyChecksForUpdates:);
                [updater setAutomaticallyChecksForUpdates:YES];
//				[updater methodForSelector:checksSEL](updater, checksSEL, YES);
			}
		} else {
			NSLog(@"Could not load %@!", frameworkPath);
		}
	}else{
        NSLog(@"su");
    }
	// add elasticthreads' menuitems
	NSMenuItem *theMenuItem = [[[NSMenuItem alloc] init] autorelease];
	[theMenuItem setTarget:self];
    //	NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
	theMenuItem = [theMenuItem copy];
    //	[statBarMenu insertItem:theMenuItem atIndex:4];
	[theMenuItem release];
    //theMenuItem = [[viewMenu itemWithTag:801] copy];
	//[statBarMenu insertItem:theMenuItem atIndex:11];
    //[theMenuItem release];
    if(IsLeopardOrLater){
        //theMenuItem =[viewMenu itemWithTag:314];
        [fsMenuItem setEnabled:YES];
        [fsMenuItem setHidden:NO];
		
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
        if (IsLionOrLater) {
            //  [window setCollectionBehavior:NSWindowCollectionBehaviorTransient|NSWindowCollectionBehaviorMoveToActiveSpace];
            //
            [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
            //            [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary];
            [NSApp setPresentationOptions:NSApplicationPresentationFullScreen];
            
            
        }else{
#endif
            [fsMenuItem setTarget:self];
            [fsMenuItem setAction:@selector(switchFullScreen:)];
            
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
        }
#endif
        theMenuItem = [fsMenuItem copy];
        [statBarMenu insertItem:theMenuItem atIndex:12];
        [theMenuItem release];
    }
    
	if (![prefsController showWordCount]) {
		[wordCounter setHidden:NO];
	}else {
		[wordCounter setHidden:YES];
	}
	//
	[NSApp setServicesProvider:self];
    if (!hasLaunched) {
        
        hasLaunched=YES;
        [self focusControlField:self activate:NO];
        
        
    }
    
//    self.isEditing=NO;
    
    
    //    [NSApp activateIgnoringOtherApps:NO];
    //    [window makeKeyAndOrderFront:self];
}

//
//- (void)applicationWillFinishLaunching:(NSNotification *)aNotification{
//  
//}


- (void)applicationDidFinishLaunching:(NSNotification*)aNote {
	//on tiger dualfield is often not ready to add tracking tracks until this point:
	
	[field setTrackingRect];
    NSDate *before = [NSDate date];
	prefsWindowController = [[PrefsWindowController alloc] init];
	
	OSStatus err = noErr;
	NotationController *newNotation = nil;
	NSData *aliasData = [prefsController aliasDataForDefaultDirectory];
	
	NSString *subMessage = @"";
	
	//if the option key is depressed, go straight to picking a new notes folder location
	if (kCGEventFlagMaskAlternate == (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & NSDeviceIndependentModifierFlagsMask)) {
		goto showOpenPanel;
	}
	
	if (aliasData) {
	    newNotation = [[NotationController alloc] initWithAliasData:aliasData error:&err];//autorelease]
	    subMessage = NSLocalizedString(@"Please choose a different folder in which to store your notes.",nil);
	} else {
	    newNotation = [[NotationController alloc] initWithDefaultDirectoryReturningError:&err];
	    subMessage = NSLocalizedString(@"Please choose a folder in which your notes will be stored.",nil);
	}
	//no need to display an alert if the error wasn't real
	if (err == kPassCanceledErr)
		goto showOpenPanel;
	
	NSString *location = (aliasData ? [[NSFileManager defaultManager] pathCopiedFromAliasData:aliasData] : NSLocalizedString(@"your Application Support directory",nil));
	if (!location) { //fscopyaliasinfo sucks
		FSRef locationRef;
		if ([aliasData fsRefAsAlias:&locationRef] && LSCopyDisplayNameForRef(&locationRef, (CFStringRef*)&location) == noErr) {
			[location autorelease];
		} else {
			location = NSLocalizedString(@"its current location",nil);
		}
	}
	
	while (!newNotation) {
	    location = [location stringByAbbreviatingWithTildeInPath];
	    NSString *reason = [NSString reasonStringFromCarbonFSError:err];
		
	    if (NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.",nil), location, reason],
							subMessage, NSLocalizedString(@"Choose another folder",nil),NSLocalizedString(@"Quit",nil),NULL) == NSAlertDefaultReturn) {
			//show nsopenpanel, defaulting to current default notes dir
			FSRef notesDirectoryRef;
		showOpenPanel:
			if (![prefsWindowController getNewNotesRefFromOpenPanel:&notesDirectoryRef returnedPath:&location]) {
				//they cancelled the open panel, or it was unable to get the path/FSRef of the file
				goto terminateApp;
			} else if ((newNotation = [[NotationController alloc] initWithDirectoryRef:&notesDirectoryRef error:&err])) {
				//have to make sure alias data is saved from setNotationController
				[newNotation setAliasNeedsUpdating:YES];
				break;
			}
	    } else {
			goto terminateApp;
	    }
	}
	
	[self setNotationController:newNotation];
	
	NSLog(@"load time: %g, ",[[NSDate date] timeIntervalSinceDate:before]);
	//	NSLog(@"version: %s", PRODUCT_NAME);
	
	//import old database(s) here if necessary
	[AlienNoteImporter importBlorOrHelpFilesIfNecessaryIntoNotation:newNotation];
	
	[newNotation release];
	if (pathsToOpenOnLaunch) {
		[notationController openFiles:[pathsToOpenOnLaunch autorelease]];//autorelease
		pathsToOpenOnLaunch = nil;
	}
	
	if (URLToInterpretOnLaunch) {
		[self interpretNVURL:[URLToInterpretOnLaunch autorelease]];
		URLToInterpretOnLaunch = nil;
	}
	
	//tell us..
	[prefsController registerWithTarget:self forChangesInSettings:
	 @selector(setAliasDataForDefaultDirectory:sender:),  //when someone wants to load a new database
	 @selector(setSortedTableColumnKey:reversed:sender:),  //when sorting prefs changed
	 @selector(setNoteBodyFont:sender:),  //when to tell notationcontroller to restyle its notes
	 @selector(setForegroundTextColor:sender:),  //ditto
	 @selector(setBackgroundTextColor:sender:),  //ditto
	 @selector(setTableFontSize:sender:),  //when to tell notationcontroller to regenerate the (now potentially too-short) note-body previews
	 @selector(addTableColumn:sender:),  //ditto
	 @selector(removeTableColumn:sender:),  //ditto
	 @selector(setTableColumnsShowPreview:sender:),  //when to tell notationcontroller to generate or disable note-body previews
	 @selector(setConfirmNoteDeletion:sender:),  //whether "delete note" should have an ellipsis
	 @selector(setAutoCompleteSearches:sender:),@selector(setUseETScrollbarsOnLion:sender:), nil];   //when to tell notationcontroller to build its title-prefix connections
	
	[self performSelector:@selector(runDelayedUIActionsAfterLaunch) withObject:nil afterDelay:0.0];
    
	
    
	return;
terminateApp:
	[NSApp terminate:self];
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
	
	NSURL *fullURL = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
	
	if (notationController) {
		if (![self interpretNVURL:fullURL])
			NSBeep();
	} else {
		URLToInterpretOnLaunch = [[fullURL path]retain];
	}
}

- (void)setNotationController:(NotationController*)newNotation {
	
    if (newNotation) {
		if (notationController) {
			[notationController closeAllResources];
			[[NSNotificationCenter defaultCenter] removeObserver:self name:SyncSessionsChangedVisibleStatusNotification
														  object:[notationController syncSessionController]];
		}
		
		NotationController *oldNotation = notationController;
		notationController = [newNotation retain];
		
		if (oldNotation) {
			[notesTableView abortEditing];
			[prefsController setLastSearchString:[self fieldSearchString] selectedNote:currentNote
						scrollOffsetForTableView:notesTableView sender:self];
			//if we already had a notation, appController should already be bookmarksController's delegate
			[[prefsController bookmarksController] performSelector:@selector(updateBookmarksUI) withObject:nil afterDelay:0.0];
		}
		[notationController setSortColumn:[notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]]];
		[notesTableView setDataSource:[notationController notesListDataSource]];
		[notesTableView setLabelsListSource:[notationController labelsListDataSource]];
		[notationController setDelegate:self];
		
		//allow resolution of UUIDs to NoteObjects from saved searches
		[[prefsController bookmarksController] setDataSource:notationController];
		
		//update the list using the new notation and saved settings
		[self restoreListStateUsingPreferences];
		
		//window's undomanager could be referencing actions from the old notation object
		[[window undoManager] removeAllActions];
		[notationController setUndoManager:[window undoManager]];
		
		if ([notationController aliasNeedsUpdating]) {
			[prefsController setAliasDataForDefaultDirectory:[notationController aliasDataForNoteDirectory] sender:self];
		}
		if ([prefsController tableColumnsShowPreview] || [prefsController horizontalLayout]) {
			[self _forceRegeneratePreviewsForTitleColumn];
			[notesTableView setNeedsDisplay:YES];
		}
		[titleBarButton setMenu:[[notationController syncSessionController] syncStatusMenu]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncSessionsChangedVisibleStatus:)
													 name:SyncSessionsChangedVisibleStatusNotification
												   object:[notationController syncSessionController]];
		[notationController performSelector:@selector(startSyncServices) withObject:nil afterDelay:0.0];
		
		if ([[notationController notationPrefs] secureTextEntry]) {
			[[SecureTextEntryManager sharedInstance] enableSecureTextEntry];
		} else {
			[[SecureTextEntryManager sharedInstance] disableSecureTextEntry];
		}
		
		[field selectText:nil];
		
		[oldNotation autorelease];
    }
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
    if ((![prefsController quitWhenClosingWindow])&&(hasLaunched)) {
        [self bringFocusToControlField:nil];
        return YES;
    }
    
    return NO;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
	return [itemIdentifier isEqualToString:@"DualField"] ? dualFieldItem : nil;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)theToolbar {
	return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)theToolbar {
	return [NSArray arrayWithObject:@"DualField"];
}


- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
	SEL selector = [menuItem action];
	NSInteger numberSelected = [notesTableView numberOfSelectedRows];
	NSInteger tag = [menuItem tag];
    
    if ((tag == TextilePreview) || (tag == MarkdownPreview) || (tag == MultiMarkdownPreview)) {
        // Allow only one Preview mode to be selected at every one time
        [menuItem setState:((tag == currentPreviewMode) ? NSOnState : NSOffState)];
        return YES;
    } else if (selector == @selector(printNote:) ||
               selector == @selector(deleteNote:) ||
               selector == @selector(exportNote:) ||
               selector == @selector(tagNote:)) {
		
		return (numberSelected > 0);
		
	} else if (selector == @selector(renameNote:) ||
			   selector == @selector(copyNoteLink:)) {
		
		return (numberSelected == 1);
		
	} else if (selector == @selector(revealNote:)) {
        
		return (numberSelected == 1) && [notationController currentNoteStorageFormat] != SingleDatabaseFormat;
		
        //	} else if (selector == @selector(openFileInEditor:)) {
        //		NSString *defApp = [prefsController textEditor];
        //		if (![[self getTxtAppList] containsObject:defApp]) {
        //			defApp = @"Default";
        //			[prefsController setTextEditor:@"Default"];
        //		}
        //		if (([defApp isEqualToString:@"Default"])||(![[NSFileManager defaultManager] fileExistsAtPath:[[NSWorkspace sharedWorkspace] fullPathForApplication:defApp]])) {
        //
        //			if (![defApp isEqualToString:@"Default"]) {
        //				[prefsController setTextEditor:@"Default"];
        //			}
        //			CFStringRef cfFormat = (CFStringRef)noteFormat;
        //			defApp = [(NSString *)LSCopyDefaultRoleHandlerForContentType(cfFormat,kLSRolesEditor) autorelease];
        //			defApp = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: defApp];
        //			defApp = [[NSFileManager defaultManager] displayNameAtPath: defApp];
        //		}
        //		if ((!defApp)||([defApp isEqualToString:@"Safari"])) {
        //			defApp = @"TextEdit";
        //		}
        //		[menuItem setTitle:[@"Open Note in " stringByAppendingString:defApp]];
        //		return (numberSelected == 1) && [notationController currentNoteStorageFormat] != SingleDatabaseFormat;
	} else if (selector == @selector(toggleCollapse:)) {
        if ([notesSubview isCollapsed]) {
            [menuItem setTitle:NSLocalizedString(@"Expand Notes List",@"menu item title for expanding notes list")];
        }else{
            
            [menuItem setTitle:NSLocalizedString(@"Collapse Notes List",@"menu item title for collapsing notes list")];
            
            if (!currentNote){
                return NO;
            }
        }
	} else if ((selector == @selector(toggleFullScreen:))||(selector == @selector(switchFullScreen:))) {
        
        if (IsLeopardOrLater) {
            
            if([NSApp presentationOptions]>0){
                [menuItem setTitle:NSLocalizedString(@"Exit Full Screen",@"menu item title for exiting fullscreen")];
            }else{
                
                [menuItem setTitle:NSLocalizedString(@"Enter Full Screen",@"menu item title for entering fullscreen")];
                
            }
            
        }
        
        
	} else if (selector == @selector(fixFileEncoding:)) {
		
		return (currentNote != nil && storageFormatOfNote(currentNote) == PlainTextFormat && ![currentNote contentsWere7Bit]);
    } else if (selector == @selector(editNoteExternally:)) {
        return (numberSelected > 0) && [[menuItem representedObject] canEditAllNotes:[notationController notesAtIndexes:[notesTableView selectedRowIndexes]]];
	}else if (selector == @selector(previewNoteWithMarked:)){
        BOOL gotMarked=[[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marky"] isFileURL];
        if ([menuItem isHidden]==gotMarked) {
            [menuItem setHidden:!gotMarked];
        }
        return gotMarked&&([[notesTableView selectedRowIndexes]count]>0);
    }else if (selector==@selector(togglePreview:)){        
          return (currentNote != nil);
    }
	return YES;
}

- (void)updateNoteMenus {
	NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
	
	NSInteger menuIndex = [notesMenu indexOfItemWithTarget:self andAction:@selector(deleteNote:)];
	NSMenuItem *deleteItem = nil;
	if (menuIndex > -1 && (deleteItem = [notesMenu itemAtIndex:menuIndex]))	{
		NSString *trailingQualifier = [prefsController confirmNoteDeletion] ? NSLocalizedString(@"...", @"ellipsis character") : @"";
		[deleteItem setTitle:[NSString stringWithFormat:@"%@%@",
							  NSLocalizedString(@"Delete", nil), trailingQualifier]];
	}
	
    [notesMenu setSubmenu:[[ExternalEditorListController sharedInstance] addEditNotesMenu] forItem:[notesMenu itemWithTag:88]];
	NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
	
	menuIndex = [viewMenu indexOfItemWithTarget:notesTableView andAction:@selector(toggleNoteBodyPreviews:)];
	NSMenuItem *bodyPreviewItem = nil;
	if (menuIndex > -1 && (bodyPreviewItem = [viewMenu itemAtIndex:menuIndex])) {
		[bodyPreviewItem setTitle: [prefsController tableColumnsShowPreview] ?
		 NSLocalizedString(@"Hide Note Previews in Title", @"menu item in the View menu to turn off note-body previews in the Title column") :
		 NSLocalizedString(@"Show Note Previews in Title", @"menu item in the View menu to turn on note-body previews in the Title column")];
	}
	menuIndex = [viewMenu indexOfItemWithTarget:self andAction:@selector(switchViewLayout:)];
	NSMenuItem *switchLayoutItem = nil;
	NSString *switchStr = [prefsController horizontalLayout] ?
	NSLocalizedString(@"Switch to Vertical Layout", @"title of alternate view layout menu item") :
	NSLocalizedString(@"Switch to Horizontal Layout", @"title of view layout menu item");
	
	if (menuIndex > -1 && (switchLayoutItem = [viewMenu itemAtIndex:menuIndex])) {
		[switchLayoutItem setTitle:switchStr];
	}
	// add to elasticthreads' statusbar menu
	menuIndex = [statBarMenu indexOfItemWithTarget:self andAction:@selector(switchViewLayout:)];
	if (menuIndex>-1) {
		NSMenuItem *anxItem = [statBarMenu itemAtIndex:menuIndex];
		[anxItem setTitle:switchStr];
	}
}

- (void)_forceRegeneratePreviewsForTitleColumn {
	[notationController regeneratePreviewsForColumn:[notesTableView noteAttributeColumnForIdentifier:NoteTitleColumnString]
								visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:YES];
    
}

- (void)_configureDividerForCurrentLayout {
    
    self.isEditing = NO;
	BOOL horiz = [prefsController horizontalLayout];
	if ([notesSubview isCollapsed]) {
		[notesSubview expand];
		[splitView setVertical:horiz];
		[splitView setDividerThickness:7.0f];
//        NSSize size = [notesSubview frame].size;
//        [notesScrollView setFrame: NSMakeRect(0, 0, size.width, size.height + 1)];
		[notesSubview collapse];
	}else {
        [splitView setVertical:horiz];
        if (!verticalDividerImg && [splitView divider]) verticalDividerImg = [[splitView divider] retain];
        [splitView setDivider: verticalDividerImg];
		[splitView setDividerThickness:8.75f];
//        NSSize size = [notesSubview frame].size;
//        [notesScrollView setFrame: horiz? NSMakeRect(0, 0, size.width, size.height) :  NSMakeRect(0, 0, size.width, size.height + 1)];
        if (![self dualFieldIsVisible]) {
            [self setDualFieldIsVisible:YES];
        }
	}
	
    if (horiz) {
        [splitSubview setMinDimension:100.0 andMaxDimension:0.0];
    }
}

- (IBAction)switchViewLayout:(id)sender {
    if ([self isInFullScreen]) {
        wasVert = YES;
    }
	ViewLocationContext ctx = [notesTableView viewingLocation];
	ctx.pivotRowWasEdge = NO;
	CGFloat colW = [notesSubview dimension];
    if (![splitView isVertical]) {
        colW += 30.0f;
    }else{
        colW -= 30.0f;
    }
	
	[prefsController setHorizontalLayout:![prefsController horizontalLayout] sender:self];
	[notationController updateDateStringsIfNecessary];
	[self _configureDividerForCurrentLayout];
    //	[notesTableView noteFirstVisibleRow];
    [notesSubview setDimension:colW];
	[notationController regenerateAllPreviews];
	[splitView adjustSubviews];
    
	[notesTableView setViewingLocation:ctx];
	[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	
	[self updateNoteMenus];
    
	[notesTableView setBackgroundColor:backgrndColor];
	[notesTableView setNeedsDisplay];
}

- (void)createFromSelection:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	if (!notationController || ![self addNotesFromPasteboard:pboard]) {
		*error = NSLocalizedString(@"Error: Couldn't create a note from the selection.", @"error message to set during a Service call when adding a note failed");
	}
}



- (IBAction)renameNote:(id)sender {
    if ([notesSubview isCollapsed]) {
        [self toggleCollapse:sender];
    }
    //edit the first selected note
    self.isEditing = YES;
    
	[notesTableView editRowAtColumnWithIdentifier:NoteTitleColumnString];
}

- (void)deleteAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    
	id retainedDeleteObj = (id)contextInfo;
	
	if (returnCode == NSAlertDefaultReturn) {
		//delete! nil-msgsnd-checking
		
		//ensure that there are no pending edits in the tableview,
		//lest editing end with the same field editor and a different selected note
		//resulting in the renaming of notes in adjacent rows
		[notesTableView abortEditing];
		
		if ([retainedDeleteObj isKindOfClass:[NSArray class]]) {
			[notationController removeNotes:retainedDeleteObj];
		} else if ([retainedDeleteObj isKindOfClass:[NoteObject class]]) {
			[notationController removeNote:retainedDeleteObj];
		}
		
		if (IsLeopardOrLater && [[alert suppressionButton] state] == NSOnState) {
			[prefsController setConfirmNoteDeletion:NO sender:self];
		}
	}
	[retainedDeleteObj release];
}


- (IBAction)deleteNote:(id)sender {
    
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	if ([indexes count] > 0) {
		id deleteObj = [indexes count] > 1 ? (id)([notationController notesAtIndexes:indexes]) : (id)([notationController noteObjectAtFilteredIndex:[indexes firstIndex]]);
		
		if ([prefsController confirmNoteDeletion]) {
			[deleteObj retain];
			NSString *warningSingleFormatString = NSLocalizedString(@"Delete the note titled quotemark%@quotemark?", @"alert title when asked to delete a note");
			NSString *warningMultipleFormatString = NSLocalizedString(@"Delete %d notes?", @"alert title when asked to delete multiple notes");
			NSString *warnString = currentNote ? [NSString stringWithFormat:warningSingleFormatString, titleOfNote(currentNote)] :
			[NSString stringWithFormat:warningMultipleFormatString, [indexes count]];
			
			NSAlert *alert = [NSAlert alertWithMessageText:warnString defaultButton:NSLocalizedString(@"Delete", @"name of delete button")
										   alternateButton:NSLocalizedString(@"Cancel", @"name of cancel button") otherButton:nil
								 informativeTextWithFormat:NSLocalizedString(@"Press Command-Z to undo this action later.", @"informational delete-this-note? text")];
			if (IsLeopardOrLater) [alert setShowsSuppressionButton:YES];
			
			[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:@selector(deleteAlertDidEnd:returnCode:contextInfo:) contextInfo:(void*)deleteObj];
		} else {
			//just delete the notes outright
			[notationController performSelector:[indexes count] > 1 ? @selector(removeNotes:) : @selector(removeNote:) withObject:deleteObj];
		}
	}
}

- (IBAction)copyNoteLink:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	if ([indexes count] == 1) {
		[[[[[notationController notesAtIndexes:indexes] lastObject]
		   uniqueNoteLink] absoluteString] copyItemToPasteboard:nil];
	}
}

- (IBAction)exportNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	NSArray *notes = [notationController notesAtIndexes:indexes];
	
	[notationController synchronizeNoteChanges:nil];
	[[ExporterManager sharedManager] exportNotes:notes forWindow:window];
}

- (IBAction)revealNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSString *path = nil;
	
	if ([indexes count] != 1 || !(path = [[notationController noteObjectAtFilteredIndex:[indexes lastIndex]] noteFilePath])) {
		NSBeep();
		return;
	}
	[[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (IBAction)editNoteExternally:(id)sender {
    ExternalEditor *ed = [sender representedObject];
    if ([ed isKindOfClass:[ExternalEditor class]]) {
        NSIndexSet *indexes = [notesTableView selectedRowIndexes];
        if (kCGEventFlagMaskAlternate == (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & NSDeviceIndependentModifierFlagsMask)) {
            //allow changing the default editor directly from Notes menu
            [[ExternalEditorListController sharedInstance] setDefaultEditor:ed];
        }
        //force-write any queued changes to disk in case notes are being stored as separate files which might be opened directly by the method below
        [notationController synchronizeNoteChanges:nil];
        [[notationController notesAtIndexes:indexes] makeObjectsPerformSelector:@selector(editExternallyUsingEditor:) withObject:ed];
    } else {
        NSBeep();
    }
}

- (IBAction)previewNoteWithMarked:(id)sender {
    if (![[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marky"] isFileURL])
    {
        NSBeep();
        NSLog(@"Marked not found");
    } else {
        NSIndexSet *indexes = [notesTableView selectedRowIndexes];
        //force-write any queued changes to disk in case notes are being stored as separate files which might be opened directly by the method below
        [notationController synchronizeNoteChanges:nil];
        [[notationController notesAtIndexes:indexes] makeObjectsPerformSelector:@selector(previewUsingMarked)];
    }
}

- (IBAction)printNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	[MultiplePageView printNotes:[notationController notesAtIndexes:indexes] forWindow:window];
}

- (IBAction)tagNote:(id)sender {
    
    if ([notesSubview isCollapsed]) {
        [self toggleCollapse:sender];
    }
	//if single note, add the tag column if necessary and then begin editing
	
	NSIndexSet *selIndexes = [notesTableView selectedRowIndexes];
	
	if ([selIndexes count] > 1) {
        
        NSRect linkingFrame=[textScrollView convertRect:[textScrollView frame] toView:nil];
        
        if (IsLionOrLater) {
            linkingFrame=[window convertRectToScreen:linkingFrame];
        }else{
            linkingFrame.origin=[window convertBaseToScreen:linkingFrame.origin];
        }
        NSPoint cPoint=NSMakePoint(NSMidX(linkingFrame), NSMaxY(linkingFrame));
        
        //Multiple Notes selected, use ElasticThreads' multitagging implementation
        tagEditor = [[[TagEditingManager alloc] initWithDelegate:self commonTags:[self commonLabelsForNotesAtIndexes:selIndexes] atPoint:cPoint] retain];
        
		//Multiple Notes selected, use ElasticThreads' multitagging implementation
	} else if ([selIndexes count] == 1) {
        self.isEditing = YES;
		[notesTableView editRowAtColumnWithIdentifier:NoteLabelsColumnString];
	}
}

- (void)noteImporter:(AlienNoteImporter*)importer importedNotes:(NSArray*)notes {
	
	[notationController addNotes:notes];
}
- (IBAction)importNotes:(id)sender {
	AlienNoteImporter *importer = [[AlienNoteImporter alloc] init];
	[importer importNotesFromDialogAroundWindow:window receptionDelegate:self];
	[importer autorelease];
}

- (void)settingChangedForSelectorString:(NSString*)selectorString {
    if ([selectorString isEqualToString:SEL_STR(setAliasDataForDefaultDirectory:sender:)]) {
		//defaults changed for the database location -- load the new one!
		
		OSStatus err = noErr;
		NotationController *newNotation = nil;
		NSData *newData = [prefsController aliasDataForDefaultDirectory];
		if (newData) {
#if kUseCachesFolderForInterimNoteChanges
            if (notationController&&[notationController flushAllNoteChanges]) {
                [notationController closeJournal];
            }
#endif
			if ((newNotation = [[NotationController alloc] initWithAliasData:newData error:&err])) {
				[self setNotationController:newNotation];
				[newNotation release];
				
			} else {
				
				//set alias data back
				NSData *oldData = [notationController aliasDataForNoteDirectory];
				[prefsController setAliasDataForDefaultDirectory:oldData sender:self];
				
				//display alert with err--could not set notation directory
				NSString *location = [[[NSFileManager defaultManager] pathCopiedFromAliasData:newData] stringByAbbreviatingWithTildeInPath];
				NSString *oldLocation = [[[NSFileManager defaultManager] pathCopiedFromAliasData:oldData] stringByAbbreviatingWithTildeInPath];
				NSString *reason = [NSString reasonStringFromCarbonFSError:err];
				NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.",nil), location, reason],
								[NSString stringWithFormat:NSLocalizedString(@"Reverting to current location of %@.",nil), oldLocation],
								NSLocalizedString(@"OK",nil), NULL, NULL);
			}
		}
    } else if ([selectorString isEqualToString:SEL_STR(setSortedTableColumnKey:reversed:sender:)]) {
		NoteAttributeColumn *oldSortCol = [notationController sortColumn];
		NoteAttributeColumn *newSortCol = [notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]];
		BOOL changedColumns = oldSortCol != newSortCol;
		
		ViewLocationContext ctx;
		if (changedColumns) {
			ctx = [notesTableView viewingLocation];
			ctx.pivotRowWasEdge = NO;
		}
		
		[notationController setSortColumn:newSortCol];
		
		if (changedColumns) [notesTableView setViewingLocation:ctx];
		
	} else if ([selectorString isEqualToString:SEL_STR(setNoteBodyFont:sender:)]) {
		
		[notationController restyleAllNotes];
		if (currentNote) {
			[self contentsUpdatedForNote:currentNote];
		}
	} else if ([selectorString isEqualToString:SEL_STR(setForegroundTextColor:sender:)]) {
		if (userScheme!=2) {
			[self setUserColorScheme:self];
		}else {
			[self setForegrndColor:[prefsController foregroundTextColor]];
			[self updateColorScheme];
		}
	} else if ([selectorString isEqualToString:SEL_STR(setBackgroundTextColor:sender:)]) {
		if (userScheme!=2) {
			[self setUserColorScheme:self];
		}else {
			[self setBackgrndColor:[prefsController backgroundTextColor]];
			[self updateColorScheme];
		}
		
	} else if ([selectorString isEqualToString:SEL_STR(setTableFontSize:sender:)] || [selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview:sender:)]) {
		
		ResetFontRelatedTableAttributes();
		[notesTableView updateTitleDereferencorState];
		[[notationController labelsListDataSource] invalidateCachedLabelImages];
		[self _forceRegeneratePreviewsForTitleColumn];
        
		if ([selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview:sender:)]) [self updateNoteMenus];
		
		[notesTableView performSelector:@selector(reloadData) withObject:nil afterDelay:0];
	} else if ([selectorString isEqualToString:SEL_STR(addTableColumn:sender:)] || [selectorString isEqualToString:SEL_STR(removeTableColumn:sender:)]) {
		
		ResetFontRelatedTableAttributes();
		[self _forceRegeneratePreviewsForTitleColumn];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0];
		
	} else if ([selectorString isEqualToString:SEL_STR(setConfirmNoteDeletion:sender:)]) {
		[self updateNoteMenus];
	} else if ([selectorString isEqualToString:SEL_STR(setAutoCompleteSearches:sender:)]) {
		if ([prefsController autoCompleteSearches])
			[notationController updateTitlePrefixConnections];
		
	}
	
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
    if (tableView == notesTableView) {
		//this sets global prefs options, which ultimately calls back to us
		[notesTableView setStatusForSortedColumn:tableColumn];
    }
}

- (BOOL)tableView:(NSTableView *)tableView shouldShowCellExpansionForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	return ![[tableColumn identifier] isEqualToString:NoteTitleColumnString];
}

- (IBAction)showHelpDocument:(id)sender {
	NSString *path = nil;
	
	switch ([sender tag]) {
		case 1:		//shortcuts
			path = [[NSBundle mainBundle] pathForResource:NSLocalizedString(@"Excruciatingly Useful Shortcuts", nil) ofType:@"nvhelp" inDirectory:nil];
		case 2:		//acknowledgments
			if (!path) path = [[NSBundle mainBundle] pathForResource:@"Acknowledgments" ofType:@"txt" inDirectory:nil];
			[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:path]] withAppBundleIdentifier:@"com.apple.TextEdit"
											options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifiers:NULL];
			break;
		case 3:		//product site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:NSLocalizedString(@"SiteURL", nil)]];
			break;
		case 4:		//development site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/ttscoff/nv/wiki"]];
			break;
        case 5:     //nvALT home
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brettterpstra.com/project/nvalt/"]];
            break;
        case 6:     //ElasticThreads
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://elasticthreads.tumblr.com/nv"]];
            break;
        case 7:     //Brett Terpstra
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brettterpstra.com"]];
            break;
		default:
			NSBeep();
	}
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
	
	if (notationController)
		[notationController openFiles:filenames];
	else
		pathsToOpenOnLaunch = [filenames mutableCopyWithZone:nil];
	
	[NSApp replyToOpenOrPrint:[filenames count] ? NSApplicationDelegateReplySuccess : NSApplicationDelegateReplyFailure];
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification {
	
	if (IsLeopardOrLater) {
		SpaceSwitchingContext thisSpaceSwitchCtx;
        if ([window windowNumber]!=-1) {
            CurrentContextForWindowNumber([window windowNumber], &thisSpaceSwitchCtx);
            
        }
		//what if the app is switched-to in another way? then the last-stored spaceSwitchCtx will cause us to return to the wrong app
		//unfortunately this notification occurs only after NV has become the front process, but we can still verify the space number
		
		if (thisSpaceSwitchCtx.userSpace != spaceSwitchCtx.userSpace ||
			thisSpaceSwitchCtx.windowSpace != spaceSwitchCtx.windowSpace) {
			//forget the last space-switch info if it's effectively different from how we're switching into the app now
			bzero(&spaceSwitchCtx, sizeof(SpaceSwitchingContext));
		}
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
	[notationController checkJournalExistence];
	
    if ([notationController currentNoteStorageFormat] != SingleDatabaseFormat)
		[notationController performSelector:@selector(synchronizeNotesFromDirectory) withObject:nil afterDelay:0.0];
	[notationController updateDateStringsIfNecessary];
}

- (void)applicationWillResignActive:(NSNotification *)aNotification {
	//sync note files when switching apps so user doesn't have to guess when they'll be updated
	[notationController synchronizeNoteChanges:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
	static NSMenu *dockMenu = nil;
	if (!dockMenu) {
		dockMenu = [[NSMenu alloc] initWithTitle:@"NV Dock Menu"];
		[[dockMenu addItemWithTitle:NSLocalizedString(@"Add New Note from Clipboard", @"menu item title in dock menu")
							 action:@selector(paste:) keyEquivalent:@""] setTarget:notesTableView];
	}
	return dockMenu;
}

- (void)cancel:(id)sender {
	//fallback for when other views are hidden/removed during toolbar collapse
	[self cancelOperation:sender];
}

- (void)cancelOperation:(id)sender {
	//simulate a search for nothing
	if ([window isKeyWindow]) {
		if (IsLionOrLater&&([textView textFinderIsVisible])) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:self];
            return;
        }
		[field setStringValue:@""];
		typedStringIsCached = NO;
		
		[notesTableView deselectAll:sender];//thiss
		[notationController filterNotesFromString:@""];
		//was here
        [self setDualFieldIsVisible:YES];
        //		[self _expandToolbar];
		
		[field selectText:sender];
		[[field cell] setShowsClearButton:NO];
	}
}



- (BOOL)control:(NSControl *)control textView:(NSTextView *)aTextView doCommandBySelector:(SEL)command {
	if (control == (NSControl*)field) {
		
        self.isEditing=NO;
		//backwards-searching is slow enough as it is, so why not just check this first?
		if (command == @selector(deleteBackward:))
			return NO;
		
		if (command == @selector(moveDown:) || command == @selector(moveUp:) ||
			//catch shift-up/down selection behavior
			command == @selector(moveDownAndModifySelection:) ||
			command == @selector(moveUpAndModifySelection:) ||
			command == @selector(moveToBeginningOfDocumentAndModifySelection:) ||
			command == @selector(moveToEndOfDocumentAndModifySelection:)) {
			
			BOOL singleSelection = ([notesTableView numberOfRows] == 1 && [notesTableView numberOfSelectedRows] == 1);
			[notesTableView keyDown:[window currentEvent]];
			
			NSUInteger strLen = [[aTextView string] length];
			if (!singleSelection && [aTextView selectedRange].length != strLen) {
				[aTextView setSelectedRange:NSMakeRange(0, strLen)];
			}
			
			return YES;
		}
		
		if ((command == @selector(insertTab:) || command == @selector(insertTabIgnoringFieldEditor:))) {
			//[self setEmptyViewState:NO];
			if (![[aTextView string] length]) {
				return YES;
			}
			if (!currentNote && [notationController preferredSelectedNoteIndex] != NSNotFound && [prefsController autoCompleteSearches]) {
				//if the current note is deselected and re-searching would auto-complete this search, then allow tab to trigger it
				[self searchForString:[self fieldSearchString]];
				return YES;
			} else if ([textView isHidden]) {
				return YES;
			}
			
			[window makeFirstResponder:textView];
			
			//don't eat the tab!
			return NO;
		}
		if (command == @selector(moveToBeginningOfDocument:)) {
		    [notesTableView selectRowAndScroll:0];
		    return YES;
		}
		if (command == @selector(moveToEndOfDocument:)) {
		    [notesTableView selectRowAndScroll:[notesTableView numberOfRows]-1];
		    return YES;
		}
		
		if (command == @selector(moveToBeginningOfLine:) || command == @selector(moveToLeftEndOfLine:)) {
			[aTextView moveToBeginningOfDocument:nil];
			return YES;
		}
		if (command == @selector(moveToEndOfLine:) || command == @selector(moveToRightEndOfLine:)) {
			[aTextView moveToEndOfDocument:nil];
			return YES;
		}
		
		if (command == @selector(moveToBeginningOfLineAndModifySelection:) || command == @selector(moveToLeftEndOfLineAndModifySelection:)) {
			
			if ([aTextView respondsToSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)]) {
				[(id)aTextView performSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)];
				return YES;
			}
		}
		if (command == @selector(moveToEndOfLineAndModifySelection:) || command == @selector(moveToRightEndOfLineAndModifySelection:)) {
			if ([aTextView respondsToSelector:@selector(moveToEndOfDocumentAndModifySelection:)]) {
				[(id)aTextView performSelector:@selector(moveToEndOfDocumentAndModifySelection:)];
				return YES;
			}
		}
		
		//we should make these two commands work for linking editor as well
		if (command == @selector(deleteToMark:)) {
			[aTextView deleteWordBackward:nil];
			return YES;
		}
		if (command == @selector(noop:)) {
			//control-U is not set to anything by default, so we have to check the event itself for noops
			NSEvent *event = [window currentEvent];
			if ([event modifierFlags] & NSControlKeyMask) {
				if ([event firstCharacterIgnoringModifiers] == 'u') {
					//in 1.1.1 this deleted the entire line, like tcsh. this is more in-line with bash
					[aTextView deleteToBeginningOfLine:nil];
					return YES;
				}
			}
		}
		
	} else if (control == (NSControl*)notesTableView) {
		
		if (command == @selector(insertNewline:)) {
			//hit return in cell
            self.isEditing=NO;
			[window makeFirstResponder:textView];
			return YES;
		}
	} else if (control == [tagEditor tagField]) {
		if ((command == @selector(insertNewline:))||(command == @selector(insertTab:))) {
            if ([aTextView selectedRange].length>0) {
                NSString *fieldStr=[aTextView string];
                NSInteger len=fieldStr.length;
                if ((![fieldStr hasSuffix:@","])&&![fieldStr hasSuffix:@" "]) {
                    [aTextView insertText:@"," replacementRange:NSMakeRange(len, 0)];
                    len++;
                }
                [aTextView setSelectedRange:NSMakeRange(len, 0)];
                return YES;
            }
		}else {
            if ((command == @selector(deleteBackward:))||(command == @selector(deleteForward:))) {
                wasDeleting = YES;
            }
            return NO;
		}
	} else{
        
		NSLog(@"%@/%@ got %@", [control description], [aTextView description], NSStringFromSelector(command));
        self.isEditing=NO;
    }
	
	return NO;
}

- (void)_setCurrentNote:(NoteObject*)aNote {
	//save range of old current note
	//we really only want to save the insertion point position if it's currently invisible
	//how do we test that?
	BOOL wasAutomatic = NO;
	NSRange currentRange = [textView selectedRangeWasAutomatic:&wasAutomatic];
	if (!wasAutomatic) [currentNote setSelectedRange:currentRange];
	
	//regenerate content cache before switching to new note
	[currentNote updateContentCacheCStringIfNecessary];
	
	
	[currentNote release];
	currentNote = [aNote retain];
}

- (NoteObject*)selectedNoteObject {
	return currentNote;
}

- (NSString*)fieldSearchString {
	NSString *typed = [self typedString];
	if (typed) return typed;
	
	if (!currentNote) return [field stringValue];
	
	return nil;
}

- (NSString*)typedString {
	if (typedStringIsCached)
		return typedString;
	
	return nil;
}

- (void)cacheTypedStringIfNecessary:(NSString*)aString {
	if (!typedStringIsCached) {
		[typedString release];
		typedString = [(aString ? aString : [field stringValue]) copy];
		typedStringIsCached = YES;
	}
}

//from fieldeditor
- (void)controlTextDidChange:(NSNotification *)aNotification {
    
	if ([aNotification object] == field) {
		typedStringIsCached = NO;
		isFilteringFromTyping = YES;
		
		NSTextView *fieldEditor = [[aNotification userInfo] objectForKey:@"NSFieldEditor"];
		NSString *fieldString = [fieldEditor string];
		
		BOOL didFilter = [notationController filterNotesFromString:fieldString];
		
		if ([fieldString length] > 0) {
//             [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldReset" object:self];
			[field setSnapbackString:nil];
			
            
			NSUInteger preferredNoteIndex = [notationController preferredSelectedNoteIndex];
			
			//lastLengthReplaced depends on textView:shouldChangeTextInRange:replacementString: being sent before controlTextDidChange: runs
			if ([prefsController autoCompleteSearches] && preferredNoteIndex != NSNotFound && ([field lastLengthReplaced] > 0)) {
				
				[notesTableView selectRowAndScroll:preferredNoteIndex];
				
				if (didFilter) {
					//current selection may be at the same row, but note at that row may have changed
					[self displayContentsForNoteAtIndex:preferredNoteIndex];
				}
				
				NSAssert(currentNote != nil, @"currentNote must not--cannot--be nil!");
				
				NSRange typingRange = [fieldEditor selectedRange];
				
				//fill in the remaining characters of the title and select
				if ([field lastLengthReplaced] > 0 && typingRange.location < [titleOfNote(currentNote) length]) {
					
					[self cacheTypedStringIfNecessary:fieldString];
					
					NSAssert([fieldString isEqualToString:[fieldEditor string]], @"I don't think it makes sense for fieldString to change");
					
					NSString *remainingTitle = [titleOfNote(currentNote) substringFromIndex:typingRange.location];
					typingRange.length = [fieldString length] - typingRange.location;
					typingRange.length = MAX(typingRange.length, 0U);
					
					[fieldEditor replaceCharactersInRange:typingRange withString:remainingTitle];
					typingRange.length = [remainingTitle length];
					[fieldEditor setSelectedRange:typingRange];
				}
				
			} else {
				//auto-complete is off, search string doesn't prefix any title, or part of the search string is being removed
				goto selectNothing;
			}
		} else {
			//selecting nothing; nothing typed
		selectNothing:
			isFilteringFromTyping = NO;
			[notesTableView deselectAll:nil];
			
			//reloadData could have already de-selected us, and hence this notification would not be sent from -deselectAll:
			[self processChangedSelectionForTable:notesTableView];
		}
		
		isFilteringFromTyping = NO;
        
	} else if ([tagEditor isMultitagging]) { //<--for elasticthreads multitagging
        if (!isAutocompleting&&!wasDeleting) {
            isAutocompleting = YES;
            NSTextView *editor = [tagEditor tagFieldEditor];
            NSRange selRange = [editor selectedRange];
            NSString *tagString = [NSString stringWithString:tagEditor.tagFieldString];
            NSString *searchString = tagString;
            if (selRange.length>0) {
                searchString = [searchString substringWithRange:selRange];
            }
            searchString = [[searchString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]] lastObject];
            selRange = [tagString rangeOfString:searchString options:NSBackwardsSearch];
            NSArray *theTags = [notesTableView labelCompletionsForString:searchString index:0];
            if ((theTags)&&([theTags count]>0)&&(![[theTags objectAtIndex:0] isEqualToString:@""])){
                NSString *useStr;
                for (useStr in theTags) {
                    if ([tagString rangeOfString:useStr].location==NSNotFound) {
                        break;
                    }
                }
                if (useStr) {
                    tagString = [tagString substringToIndex:selRange.location];
                    tagString = [tagString stringByAppendingString:useStr];
                    selRange = NSMakeRange(selRange.location + selRange.length, useStr.length - searchString.length );
                    [tagEditor setTF:tagString];
                    [editor setSelectedRange:selRange];
                }
            }
            isAutocompleting = NO;
            //            [tagString release];
        }
        wasDeleting = NO;
    }
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification {
	
    if (IsLionOrLater) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldReset" object:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    
	BOOL allowMultipleSelection = NO;
	NSEvent *event = [window currentEvent];
    
	NSEventType type = [event type];
	//do not allow drag-selections unless a modifier is pressed
	if (type == NSLeftMouseDragged || type == NSLeftMouseDown) {
		NSUInteger flags = [event modifierFlags];
		if ((flags & NSShiftKeyMask) || (flags & NSCommandKeyMask)) {
			allowMultipleSelection = YES;
		}
	}
	
	if (allowMultipleSelection != [notesTableView allowsMultipleSelection]) {
		//we may need to hack some hidden NSTableView instance variables to improve mid-drag flags-changing
		//NSLog(@"set allows mult: %d", allowMultipleSelection);
		
		[notesTableView setAllowsMultipleSelection:allowMultipleSelection];
		
		//we need this because dragging a selection back to the same note will nto trigger a selectionDidChange notification
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}
    
	if ([window firstResponder] != notesTableView) {
		//occasionally changing multiple selection ability in-between selecting multiple items causes total deselection
		[window makeFirstResponder:notesTableView];
	}
	
	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)setTableAllowsMultipleSelection {
	[notesTableView setAllowsMultipleSelection:YES];
	//NSLog(@"allow mult: %d", [notesTableView allowsMultipleSelection]);
	//[textView setNeedsDisplay:YES];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    if (IsLionOrLater) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldUpdate" object:self];
    }
    self.isEditing = NO;
	NSEventType type = [[window currentEvent] type];
	if (type != NSKeyDown && type != NSKeyUp) {
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}
	
	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)processChangedSelectionForTable:(NSTableView*)table {
	NSInteger selectedRow = [table selectedRow];
	NSInteger numberSelected = [table numberOfSelectedRows];
	
	NSTextView *fieldEditor = (NSTextView*)[field currentEditor];
	
	if (table == (NSTableView*)notesTableView) {
		
		if (selectedRow > -1 && numberSelected == 1) {
			//if it is uncached, cache the typed string only if we are selecting a note
			
			[self cacheTypedStringIfNecessary:[fieldEditor string]];
			
			//add snapback-button here?
			if (!isFilteringFromTyping && !isCreatingANote)
				[field setSnapbackString:typedString];
			
			if ([self displayContentsForNoteAtIndex:selectedRow]) {
				
				[[field cell] setShowsClearButton:YES];
				
				//there doesn't seem to be any situation in which a note will be selected
				//while the user is typing and auto-completion is disabled, so should be OK
                
				if (!isFilteringFromTyping) {
                    //	if ([toolbar isVisible]) {
                    if ([self dualFieldIsVisible]) {
						if (fieldEditor) {
							//the field editor has focus--select text, too
							[fieldEditor setString:titleOfNote(currentNote)];
							NSUInteger strLen = [titleOfNote(currentNote) length];
							if (strLen != [fieldEditor selectedRange].length)
								[fieldEditor setSelectedRange:NSMakeRange(0, strLen)];
						} else {
							//this could be faster
							[field setStringValue:titleOfNote(currentNote)];
						}
					} else {
						[window setTitle:titleOfNote(currentNote)];
					}
				}
			}
			return;
		}
	} else { //tags
#if 0
		if (numberSelected == 1)
			[notationController filterNotesFromLabelAtIndex:selectedRow];
		else if (numberSelected > 1)
			[notationController filterNotesFromLabelIndexSet:[table selectedRowIndexes]];
#endif
	}
	
	if (!isFilteringFromTyping) {
		if (currentNote) {
			//selected nothing and something is currently selected
			
			[self _setCurrentNote:nil];
			[field setShowsDocumentIcon:NO];
			
			if (typedStringIsCached) {
				//restore the un-selected state, but only if something had been first selected to cause that state to be saved
				[field setStringValue:typedString];
			}
			[textView setString:@""];
		}
		//[self _expandToolbar];
        [self setDualFieldIsVisible:YES];
        [mainView setNeedsDisplay:YES];
		if (!currentNote) {
			if (selectedRow == -1 && (!fieldEditor || [window firstResponder] != fieldEditor)) {
				//don't select the field if we're already there
				[window makeFirstResponder:field];
				fieldEditor = (NSTextView*)[field currentEditor];
			}
			if (fieldEditor && [fieldEditor selectedRange].length)
				[fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];
			
			
			//remove snapback-button from dual field here?
			[field setSnapbackString:nil];
			
			if (!numberSelected && savedSelectedNotes) {
				//savedSelectedNotes needs to be empty after de-selecting all notes,
				//to ensure that any delayed list-resorting does not re-select savedSelectedNotes
                
				[savedSelectedNotes release];
				savedSelectedNotes = nil;
			}
		}
	}
	[self setEmptyViewState:currentNote == nil];
	[field setShowsDocumentIcon:currentNote != nil];
	[[field cell] setShowsClearButton:currentNote != nil || [[field stringValue] length]];
}


- (BOOL)setNoteIfNecessary{
    if (currentNote==nil) {
        [notesTableView selectRowAndScroll:0];
        return (currentNote!=nil);
    }
    return YES;
}

- (void)setEmptyViewState:(BOOL)state {
    //return;
	
	//int numberSelected = [notesTableView numberOfSelectedRows];
	//BOOL enable = /*numberSelected != 1;*/ state;
    
	[self postTextUpdate];
    [self updateWordCount:(![prefsController showWordCount])];
	[textView setHidden:state];
	[editorStatusView setHidden:!state];
	
	if (state) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:self];
		[editorStatusView setLabelStatus:[notesTableView numberOfSelectedRows]];
        if ([notesSubview isCollapsed]) {
            [self toggleCollapse:self];
        }
	}
}

- (BOOL)displayContentsForNoteAtIndex:(int)noteIndex {
	NoteObject *note = [notationController noteObjectAtFilteredIndex:noteIndex];
	if (note != currentNote) {
		[self setEmptyViewState:NO];
		[field setShowsDocumentIcon:YES];
		
		//actually load the new note
		[self _setCurrentNote:note];
		
		NSRange firstFoundTermRange = NSMakeRange(NSNotFound,0);
		NSRange noteSelectionRange = [currentNote lastSelectedRange];
		
		if (noteSelectionRange.location == NSNotFound ||
			NSMaxRange(noteSelectionRange) > [[note contentString] length]) {
			//revert to the top; selection is invalid
			noteSelectionRange = NSMakeRange(0,0);
		}
		
		//[textView beginInhibitingUpdates];
		//scroll to the top first in the old note body if necessary, because the text will (or really ought to) have already been laid-out
		//if ([textView visibleRect].origin.y > 0)
		//	[textView scrollRangeToVisible:NSMakeRange(0,0)];
		
		if (![textView didRenderFully]) {
			//NSLog(@"redisplay because last note was too long to finish before we switched");
			[textView setNeedsDisplayInRect:[textView visibleRect] avoidAdditionalLayout:YES];
		}
		
		//restore string
		[[textView textStorage] setAttributedString:[note contentString]];
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
		//[textView setAutomaticallySelectedRange:NSMakeRange(0,0)];
		
		//highlight terms--delay this, too
		if ((unsigned)noteIndex != [notationController preferredSelectedNoteIndex])
			firstFoundTermRange = [textView highlightTermsTemporarilyReturningFirstRange:typedString avoidHighlight:
								   ![prefsController highlightSearchTerms]];
		
		//if there was nothing selected, select the first found range
		if (!noteSelectionRange.length && firstFoundTermRange.location != NSNotFound)
			noteSelectionRange = firstFoundTermRange;
		
		//select and scroll
		[textView setAutomaticallySelectedRange:noteSelectionRange];
		[textView scrollRangeToVisible:noteSelectionRange];
		
		//NSString *words = noteIndex != [notationController preferredSelectedNoteIndex] ? typedString : nil;
		//[textView setFutureSelectionRange:noteSelectionRange highlightingWords:words];
		
        [self updateRTL];
        
		return YES;
	}
	
	return NO;
}

//from linkingeditor
- (void)textDidChange:(NSNotification *)aNotification {
	id textObject = [aNotification object];
    //[self resetModTimers];
	if (textObject == textView) {
		[currentNote setContentString:[textView textStorage]];
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
        if (IsLionOrLater) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldUpdate" object:self];
        }
	}
    
    
}

- (void)textDidBeginEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		[textView removeHighlightedTerms];
	    [self createNoteIfNecessary];
	}/*else if ([aNotification object] == notesTableView) {
      NSLog(@"ntv tdbe2");
      }*/
}

- (BOOL)textShouldBeginEditing:(NSText *)aTextObject {
    if (IsLionOrLater) {
        if (aTextObject==textView) {
            [[NSNotificationCenter defaultCenter]postNotificationName:@"TextFindContextShouldNoteChanges" object:nil];
            
        }else{
            
            NSLog(@"not textview should begin with to:%@",[aTextObject description]);
        }
    }
    return YES;
    
}

/*
 - (void)controlTextDidBeginEditing:(NSNotification *)aNotification{
 NSLog(@"controltextdidbegin");
 }
*/
- (void)textDidEndEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		//save last selection range for currentNote?
		//[currentNote setSelectedRange:[textView selectedRange]];
		
		//we need to set this here as we could return to searching before changing notes
		//and the next time the note would change would be when searching had triggered it
		//which would be too late
		[currentNote updateContentCacheCStringIfNecessary];
	}
}

- (NSMenu *)textView:(NSTextView *)view menu:(NSMenu *)menu forEvent:(NSEvent *)event atIndex:(NSUInteger)charIndex {
    //    NSLog(@"textview menu for event");
	NSInteger idx;
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(_removeLinkFromMenu:)]) > -1)
		[menu removeItemAtIndex:idx];
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(orderFrontLinkPanel:)]) > -1)
		[menu removeItemAtIndex:idx];
	return menu;
}

- (NSArray *)textView:(NSTextView *)aTextView completions:(NSArray *)words
  forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)anIndex {
	NSArray *noteTitles = [notationController noteTitlesPrefixedByString:[[aTextView string] substringWithRange:charRange] indexOfSelectedItem:anIndex];
	return noteTitles;
}


- (IBAction)fieldAction:(id)sender {
	
	[self createNoteIfNecessary];
	[window makeFirstResponder:textView];
	
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)sender {
	
	if ([sender firstResponder] == textView) {
		if ((floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_3) && currentNote) {
			NSLog(@"windowWillReturnUndoManager should not be called when textView is first responder on Tiger or higher");
		}
		
		NSUndoManager *undoMan = [self undoManagerForTextView:textView];
		if (undoMan)
			return undoMan;
	}
	return windowUndoManager;
}

- (NSUndoManager *)undoManagerForTextView:(NSTextView *)aTextView {
    if (aTextView == textView && currentNote)
		return [currentNote undoManager];
    
    return nil;
}

- (NoteObject*)createNoteIfNecessary {
    
    if (!currentNote) {
		//this assertion not yet valid until labels list changes notes list
		NSAssert([notesTableView numberOfSelectedRows] != 1, @"cannot create a note when one is already selected");
		
		[textView setTypingAttributes:[prefsController noteBodyAttributes]];
		[textView setFont:[prefsController noteBodyFont]];
		
		isCreatingANote = YES;
		NSString *title = [[field stringValue] length] ? [field stringValue] : NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		NSAttributedString *attributedContents = [textView textStorage] ? [textView textStorage] : [[[NSAttributedString alloc] initWithString:@"" attributes:
																									 [prefsController noteBodyAttributes]] autorelease];
		NoteObject *note = [[[NoteObject alloc] initWithNoteBody:attributedContents title:title delegate:notationController
														  format:[notationController currentNoteStorageFormat] labels:nil] autorelease];
		[notationController addNewNote:note];
		
		isCreatingANote = NO;
		return note;
    }
    
    return currentNote;
}

- (void)restoreListStateUsingPreferences {
	//to be invoked after loading a notationcontroller
	
	NSString *searchString = [prefsController lastSearchString];
	if ([searchString length])
		[self searchForString:searchString];
	else
		[notationController refilterNotes];
    
	CFUUIDBytes bytes = [prefsController UUIDBytesOfLastSelectedNote];
	NSUInteger idx = [self revealNote:[notationController noteForUUIDBytes:&bytes] options:NVDoNotChangeScrollPosition];
	//scroll using saved scrollbar position
	[notesTableView scrollRowToVisible:NSNotFound == idx ? 0 : idx withVerticalOffset:[prefsController scrollOffsetOfLastSelectedNote]];
}

- (NSUInteger)revealNote:(NoteObject*)note options:(NSUInteger)opts {
	if (note) {
		NSUInteger selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
		
		if (selectedNoteIndex == NSNotFound) {
			NSLog(@"Note was not visible--showing all notes and trying again");
			[self cancelOperation:nil];
			
			selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
		}
		
		if (selectedNoteIndex != NSNotFound) {
			if (opts & NVDoNotChangeScrollPosition) { //select the note only
				[notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedNoteIndex] byExtendingSelection:NO];
			} else {
				[notesTableView selectRowAndScroll:selectedNoteIndex];
			}
		}
		
		if (opts & NVEditNoteToReveal) {
			[window makeFirstResponder:textView];
		}
		if (opts & NVOrderFrontWindow) {
			//for external url-handling, often the app will already have been brought to the foreground
			if (![NSApp isActive]) {
				if (IsLeopardOrLater)
					CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
				[NSApp activateIgnoringOtherApps:YES];
			}
			if (![window isKeyWindow])
				[window makeKeyAndOrderFront:nil];
		}
		return selectedNoteIndex;
	} else {
		[notesTableView deselectAll:self];
		return NSNotFound;
	}
}

- (void)notation:(NotationController*)notation revealNote:(NoteObject*)note options:(NSUInteger)opts {
	[self revealNote:note options:opts];
}

- (void)notation:(NotationController*)notation revealNotes:(NSArray*)notes {
	
	NSIndexSet *indexes = [notation indexesOfNotes:notes];
	if ([notes count] != [indexes count]) {
		[self cancelOperation:nil];
		
		indexes = [notation indexesOfNotes:notes];
	}
	if ([indexes count]) {
		[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];
		[notesTableView scrollRowToVisible:[indexes firstIndex]];
	}
}

- (void)searchForString:(NSString*)string {
	
	if (string) {
		
		//problem: this won't work when the toolbar (and consequently the searchfield) is hidden;
		//and neither will the controlTextDidChange implementation
		//[self _expandToolbar];
		
        [self setDualFieldIsVisible:YES];
        [mainView setNeedsDisplay:YES];
		[window makeFirstResponder:field];
		NSTextView* fieldEditor = (NSTextView*)[field currentEditor];
		NSRange fullRange = NSMakeRange(0, [[fieldEditor string] length]);
		if ([fieldEditor shouldChangeTextInRange:fullRange replacementString:string]) {
			[fieldEditor replaceCharactersInRange:fullRange withString:string];
			[fieldEditor didChangeText];
		} else {
			NSLog(@"I shouldn't change text?");
		}
	}
}

- (void)bookmarksController:(BookmarksController*)controller restoreNoteBookmark:(NoteBookmark*)aBookmark inBackground:(BOOL)inBG {
	if (aBookmark) {
		[self searchForString:[aBookmark searchString]];
		[self revealNote:[aBookmark noteObject] options:!inBG ? NVOrderFrontWindow : 0];
	}
}



- (void)splitView:(RBSplitView*)sender wasResizedFrom:(CGFloat)oldDimension to:(CGFloat)newDimension {
	if (sender == splitView) {
		[sender adjustSubviewsExcepting:notesSubview];
	}
}

- (BOOL)splitView:(RBSplitView*)sender shouldHandleEvent:(NSEvent*)theEvent inDivider:(NSUInteger)divider
	  betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing {
	//if upon the first mousedown, the top selected index is visible, snap to it when resizing
	[notesTableView noteFirstVisibleRow];
	if ([theEvent clickCount]>1) {
        if ((currentNote)||([notesSubview isCollapsed])){
            [self toggleCollapse:sender];
        }
		return NO;
	}
	return YES;
}

//mail.app-like resizing behavior wrt item selections
- (void)willAdjustSubviews:(RBSplitView*)sender {
	//problem: don't do this if the horizontal splitview is being resized; in horizontal layout, only do this when resizing the window
	if (![prefsController horizontalLayout]) {
		[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	}
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize {
	if ([prefsController horizontalLayout]) {
		[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	}
	return proposedFrameSize;
}
/*
 - (void)_expandToolbar {
 if (![toolbar isVisible]) {
 [window setTitle:@"Notation"];
 if (currentNote)
 [field setStringValue:titleOfNote(currentNote)];
 [toolbar setVisible:YES];
 //[window toggleToolbarShown:nil];
 //	if (![splitView isDragging])
 //[[splitView subviewAtPosition:0] setDimension:100.0];
 //[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ToolbarHidden"];
 }
 //if ([[splitView subviewAtPosition:0] isCollapsed])
 //	[[splitView subviewAtPosition:0] expand];
 
 }
 
 - (void)_collapseToolbar {
 if ([toolbar isVisible]) {
 //	if (currentNote)
 //		[window setTitle:titleOfNote(currentNote)];
 //		[window toggleToolbarShown:nil];
 
 [toolbar setVisible:NO];
 //[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ToolbarHidden"];
 }
 }
 */
- (BOOL)splitView:(RBSplitView*)sender shouldResizeWindowForDivider:(NSUInteger)divider
	  betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing willGrow:(BOOL)grow {
    
	if ([sender isDragging]) {
		BOOL toolbarVisible  = [self dualFieldIsVisible];
		NSPoint mouse = [sender convertPoint:[[window currentEvent] locationInWindow] fromView:nil];
        CGFloat mouseDim = mouse.y;
        if ([splitView isVertical]) {
            mouseDim = mouse.x - 50.0;
        }
		if ((toolbarVisible && !grow && mouseDim < -28.0 && ![leading canShrink]) ||
			(!toolbarVisible && grow)) {
            [self setDualFieldIsVisible:!toolbarVisible];
            
            [mainView setNeedsDisplay:YES];
			if (!toolbarVisible && [window firstResponder] == window) {
				//if dualfield had first responder previously, it might need to be restored
				//if it had been removed from the view hierarchy due to hiding the toolbar
				[field selectText:sender];
			}
		}
	}
    
	return NO;
}

- (void)tableViewColumnDidResize:(NSNotification *)aNotification {
	NoteAttributeColumn *col = [[aNotification userInfo] objectForKey:@"NSTableColumn"];
	if ([[col identifier] isEqualToString:NoteTitleColumnString]) {
		[notationController regeneratePreviewsForColumn:col visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:NO];
		
	 	[NSObject cancelPreviousPerformRequestsWithTarget:notesTableView selector:@selector(reloadDataIfNotEditing) object:nil];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0.0];
	}
}

- (NSRect)splitView:(RBSplitView*)sender willDrawDividerInRect:(NSRect)dividerRect betweenView:(RBSplitSubview*)leading
			andView:(RBSplitSubview*)trailing withProposedRect:(NSRect)imageRect {
	
	[dividerShader drawDividerInRect:dividerRect withDimpleRect:imageRect blendVertically:![prefsController horizontalLayout]];
	
	return NSZeroRect;
}

- (NSUInteger)splitView:(RBSplitView*)sender dividerForPoint:(NSPoint)point inSubview:(RBSplitSubview*)subview {
	//if ([(AugmentedScrollView*)[notesTableView enclosingScrollView] shouldDragWithPoint:point sender:sender]) {
	//	return 0;       // [firstSplit position], which we assume to be zero
	//}
	return NSNotFound;
}

- (BOOL)splitView:(RBSplitView*)sender canCollapse:(RBSplitSubview*)subview {
	if ([sender subviewAtPosition:0] == subview) {
		return currentNote != nil;
		//this is the list view; let it collapse in horizontal layout when a note is being edited
		//return [prefsController horizontalLayout] && currentNote != nil;
	}
	return NO;
}


//the notationcontroller must call notationListShouldChange: first
//if it's going to do something that could mess up the tableview's field eidtor
- (BOOL)notationListShouldChange:(NotationController*)someNotation {
	
	if (someNotation == notationController) {
		if ([notesTableView currentEditor])
			return NO;
	}
	
	return YES;
}

- (void)notationListMightChange:(NotationController*)someNotation {
	
	if (!isFilteringFromTyping) {
		if (someNotation == notationController) {
			//deal with one notation at a time
			
			if ([notesTableView numberOfSelectedRows] > 0) {
				NSIndexSet *indexSet = [notesTableView selectedRowIndexes];
                
				[savedSelectedNotes release];
				savedSelectedNotes = [[someNotation notesAtIndexes:indexSet] retain];
			}
			
			listUpdateViewCtx = [notesTableView viewingLocation];
		}
	}
}

- (void)notationListDidChange:(NotationController*)someNotation {
	
	if (someNotation == notationController) {
		//deal with one notation at a time
        
		[notesTableView reloadData];
		//[notesTableView noteNumberOfRowsChanged];
		
		if (!isFilteringFromTyping) {
			if (savedSelectedNotes) {
				NSIndexSet *indexes = [someNotation indexesOfNotes:savedSelectedNotes];
				[savedSelectedNotes release];
				savedSelectedNotes = nil;
				
				[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];
			}
			
			[notesTableView setViewingLocation:listUpdateViewCtx];
		}
	}
}

- (void)titleUpdatedForNote:(NoteObject*)aNoteObject {
    if (aNoteObject == currentNote) {
        //	if ([toolbar isVisible]) {
        if ([self dualFieldIsVisible]) {
			[field setStringValue:titleOfNote(currentNote)];
		} else {
			[window setTitle:titleOfNote(currentNote)];
		}
    }
	[[prefsController bookmarksController] updateBookmarksUI];
}

- (void)contentsUpdatedForNote:(NoteObject*)aNoteObject {
	if (aNoteObject == currentNote) {
		NSArray *selRanges=[textView selectedRanges];
		[[textView textStorage] setAttributedString:[aNoteObject contentString]];
        if (![selRanges isEqualToArray:[textView selectedRanges]]) {
            NSRange testEnd=[[selRanges lastObject] rangeValue];
            NSUInteger test=testEnd.location+testEnd.length;
            
            if (test<=[textView string].length) {
                [textView setSelectedRanges:selRanges];
            }
        }
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
	}
}

- (void)rowShouldUpdate:(NSInteger)affectedRow {
	NSRect rowRect = [notesTableView rectOfRow:affectedRow];
	NSRect visibleRect = [notesTableView visibleRect];
	
	if (NSContainsRect(visibleRect, rowRect) || NSIntersectsRect(visibleRect, rowRect)) {
		[notesTableView setNeedsDisplayInRect:rowRect];
	}
}

- (void)syncSessionsChangedVisibleStatus:(NSNotification*)aNotification {
	SyncSessionController *syncSessionController = [aNotification object];
	if ([syncSessionController hasErrors]) {
		[titleBarButton setStatusIconType:AlertIcon];
	} else if ([syncSessionController hasRunningSessions]) {
		[titleBarButton setStatusIconType:SynchronizingIcon];
	} else {
		[titleBarButton setStatusIconType: [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowSyncMenu"] ? DownArrowIcon : NoIcon ];
	}
}


- (IBAction)fixFileEncoding:(id)sender {
	if (currentNote) {
		[notationController synchronizeNoteChanges:nil];
		
		[[EncodingsManager sharedManager] showPanelForNote:currentNote];
	}
}


- (void)windowDidResignKey:(NSNotification *)notification{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];    
}

- (void)windowWillClose:(NSNotification *)aNotification {
    
    //	[self resetModTimers];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    if ([prefsController quitWhenClosingWindow]){
		[NSApp terminate:nil];
    }
}

- (void)_finishSyncWait {
	//always post to next runloop to ensure that a sleep-delay response invocation, if one is also queued, runs before this one
	//if the app quits before the sleep-delay response posts, then obviously sleep will be delayed by quite a bit
	[self performSelector:@selector(syncWaitQuit:) withObject:nil afterDelay:0];
}

- (IBAction)syncWaitQuit:(id)sender {
	//need this variable to allow overriding the wait
	waitedForUncommittedChanges = YES;
	NSString *errMsg = [[notationController syncSessionController] changeCommittingErrorMessage];
	if ([errMsg length]) NSRunAlertPanel(NSLocalizedString(@"Changes could not be uploaded.", nil), errMsg, @"Quit", nil, nil);
	
	[NSApp terminate:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	//if a sync session is still running, then wait for it to finish before sending terminatereply
	//otherwise, if there are unsynced notes to send, then push them right now and wait until session is no longer running
	//use waitForUncommitedChangesWithTarget:selector: and provide a callback to send NSTerminateNow
	
	InvocationRecorder *invRecorder = [InvocationRecorder invocationRecorder];
	[[invRecorder prepareWithInvocationTarget:self] _finishSyncWait];
	
	if (!waitedForUncommittedChanges &&
		[[notationController syncSessionController] waitForUncommitedChangesWithInvocation:[invRecorder invocation]]) {
		
		[[NSApp windows] makeObjectsPerformSelector:@selector(orderOut:) withObject:nil];
		[syncWaitPanel center];
		[syncWaitPanel makeKeyAndOrderFront:nil];
		[syncWaitSpinner startAnimation:nil];
		//use NSTerminateCancel instead of NSTerminateLater because we need the runloop functioning in order to receive start/stop sync notifications
		return NSTerminateCancel;
	}
	return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (notationController) {
		//only save the state if the notation instance has actually loaded; i.e., don't save last-selected-note if we quit from a PW dialog
		BOOL wasAutomatic = NO;
		NSRange currentRange = [textView selectedRangeWasAutomatic:&wasAutomatic];
		if (!wasAutomatic) [currentNote setSelectedRange:currentRange];
		
		[currentNote updateContentCacheCStringIfNecessary];
		
		[prefsController setLastSearchString:[self fieldSearchString] selectedNote:currentNote
					scrollOffsetForTableView:notesTableView sender:self];
		
		[prefsController saveCurrentBookmarksFromSender:self];
	}
	
	[[NSApp windows] makeObjectsPerformSelector:@selector(close)];
	[notationController stopFileNotifications];
	
	//wait for syncing to finish, showing a progress bar
	
    if ([notationController flushAllNoteChanges])
		[notationController closeJournal];
	else
		NSLog(@"Could not flush database, so not removing journal");
	
    [prefsController synchronize];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter]removeObserver:self];
    [fsMenuItem release];
    [mainView release];
    [dualFieldView release];
    [wordCounter release];
    [splitView release];
    [splitSubview release];
    [notesSubview release];
    [notesScrollView release];
    [textScrollView release];
    [previewController release];
	[windowUndoManager release];
	[dividerShader release];
	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    [statusItem release];
    [cView release];
    [statBarMenu release];
	[self postTextUpdate];
	
	[super dealloc];
}

- (IBAction)showPreferencesWindow:(id)sender {
	[prefsWindowController showWindow:sender];
}

- (IBAction)toggleNVActivation:(id)sender {
    
	if ([NSApp isActive] && [window isMainWindow]&&[window isVisible]) {
        
		SpaceSwitchingContext laterSpaceSwitchCtx;
		if (IsLeopardOrLater){
			CurrentContextForWindowNumber([window windowNumber], &laterSpaceSwitchCtx);
            
        }
		if (!IsLeopardOrLater || !CompareContextsAndSwitch(&spaceSwitchCtx, &laterSpaceSwitchCtx)) {
			//hide only if we didn't need to or weren't able to switch spaces
			[NSApp hide:sender];
		}
		//clear the space-switch context that we just looked at, to ensure it's not reused inadvertently
		bzero(&spaceSwitchCtx, sizeof(SpaceSwitchingContext));
		return;
	}
	[self bringFocusToControlField:sender];
}

- (void)focusControlField:(id)sender activate:(BOOL)shouldActivate{
//        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:sender];

	if ([notesSubview isCollapsed]) {
		[self toggleCollapse:self];
	}else if (![self dualFieldIsVisible]){
		
        [self setDualFieldIsVisible:YES];
	}
    
	[field selectText:sender];
    
	if (!shouldActivate) {
        [window makeKeyAndOrderFront:sender];
        [window makeMainWindow];
        if (![NSApp isActive]) {
            CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
        }
    }else{
        if (![NSApp isActive]) {
            CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
            [NSApp activateIgnoringOtherApps:YES];
        }
        if (![window isMainWindow]||![window isVisible]){
            [window makeKeyAndOrderFront:sender];
        }
	}
	[self setEmptyViewState:currentNote == nil];
    self.isEditing = NO;
    
    
}

- (IBAction)bringFocusToControlField:(id)sender {
	//For ElasticThreads' fullscreen mode use this if/else otherwise uncomment the expand toolbar
    
    [self focusControlField:sender activate:YES];
}


- (NSWindow*)window {
	return window;
}

#pragma mark nvALT methods

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    if (aTableView==notesTableView) {
        if ([aCell isHighlighted]) {           
            if (([window firstResponder]==notesTableView)||([notesTableView rowHeight]>30.0)||(isEditing&&([notesTableView editedRow]==rowIndex))) {
                [aCell setTextColor:[NSColor whiteColor]];
                return;
            }else if ([[foregrndColor colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent]>0.5) {                    
                [aCell setTextColor:[NSColor colorWithCalibratedWhite:0.2 alpha:1.0]];
                return;
            }
        }
        [aCell setTextColor:foregrndColor];
    }
}

- (NSMenu *)statBarMenu{
	return statBarMenu;
}

- (void)toggleAttachedWindow:(NSNotification *)aNotification
{
	[self toggleNVActivation:[aNotification object]];
}

- (void)toggleAttachedMenu:(NSNotification *)aNotification
{
	[statusItem popUpStatusItemMenu:statBarMenu];
}

#pragma mark multitagging

- (NSArray *)commonLabelsForNotesAtIndexes:(NSIndexSet *)selDexes{
	NSArray *retArray =[NSArray array];
    
	NSEnumerator *noteEnum = [[[notationController notesAtIndexes:selDexes] objectEnumerator] retain];
	NoteObject *aNote;
	aNote = [noteEnum nextObject];
	NSString *existTags = labelsOfNote(aNote);
	if (existTags&&(existTags.length>0)) {
        NSMutableSet *commonTags = [NSMutableSet new];
        
        [commonTags addObjectsFromArray:[existTags labelCompatibleWords]];
		while (((aNote = [noteEnum nextObject]))&&([commonTags count]>0)) {
			existTags = labelsOfNote(aNote);
			if (!existTags||(existTags.length==0)) {
				[commonTags removeAllObjects];
				break;
            }else{
				NSArray *tagArray = [existTags labelCompatibleWords];
                if (tagArray&&([tagArray count]>0)) {
                    NSSet *tagsForNote =[NSSet setWithArray:tagArray];
                    if ([commonTags intersectsSet:tagsForNote]) {
                        [commonTags intersectSet:tagsForNote];
                    }else {
                        [commonTags removeAllObjects];
                        break;
                    }
                }else {
                    [commonTags removeAllObjects];
                    break;
                }
			}
		}
		if (commonTags&&([commonTags count]>0)) {
			retArray = [NSArray arrayWithArray:[commonTags allObjects]];
		}
        [commonTags release];
	}
	[noteEnum release];
	return retArray;
}

- (IBAction)multiTag:(id)sender {
	NSString *tagString = [tagEditor.tagFieldString stringByTrimmingCharactersInSet:[NSCharacterSet labelSeparatorCharacterSet]];
	NSArray *newTags;
    if (tagString&&(tagString.length>0)) {
        newTags=[tagString labelCompatibleWords];
    }else{
        newTags=[NSArray array];
    }
    NSArray *commonLabs=tagEditor.commonTags;
    if (![newTags isEqualToArray:commonLabs]) {
        
        NSArray *selNotes = [notationController notesAtIndexes:[notesTableView selectedRowIndexes]];
        if (!selNotes||([selNotes count]==0)) {
            return;
        }
        tagString=nil;
        
        BOOL gotNewLabels=(newTags&&([newTags count]>0));
        BOOL gotCommonLabels=(commonLabs&&([commonLabs count]>0));
        NSPredicate *pred;
        if (gotCommonLabels&&gotNewLabels) {
            pred=[NSPredicate predicateWithFormat:@"NOT %@ CONTAINS[cd] SELF",newTags];
            commonLabs=[commonLabs filteredArrayUsingPredicate:pred];
        }
        NSMutableArray *finalTags = [NSMutableArray new];
        for (NoteObject *aNote in selNotes) {
            NSString *separator=@" ";
            tagString=labelsOfNote(aNote);
            NSArray *filteredTags;
            
            if (tagString&&(tagString.length>0)) {
                if (([tagString rangeOfString:@","].location!=NSNotFound)) {
                    separator=@",";
                }
                filteredTags=[tagString labelCompatibleWords];
                if (gotCommonLabels) {
                    pred=[NSPredicate predicateWithFormat:@"NOT %@ CONTAINS[cd] SELF",commonLabs];
                    filteredTags=[filteredTags filteredArrayUsingPredicate:pred];
                }
                if (filteredTags&&([filteredTags count]>0)) {
                    [finalTags addObjectsFromArray:filteredTags];
                }
            }
            if (gotNewLabels) {
                if (finalTags&&([finalTags count]>0)) {
                    pred=[NSPredicate predicateWithFormat:@"NOT %@ CONTAINS[cd] SELF",finalTags];
                    filteredTags=[newTags filteredArrayUsingPredicate:pred];
                    if (filteredTags&&([filteredTags count]>0)) {
                        [finalTags addObjectsFromArray:filteredTags];
                    }
                }else{
                    [finalTags addObjectsFromArray:newTags];
                }
            }
            if (finalTags&&([finalTags count]>0)) {
                tagString = [finalTags componentsJoinedByString:separator];
            }else{
                tagString=@"";
            }
        
            [aNote setLabelString:tagString];
            [finalTags removeAllObjects];
        }
        
		[notesTableView scrollRowToVisible:[[notesTableView selectedRowIndexes] firstIndex]];
        [finalTags release];
    }
	[tagEditor closeTP:self];
}

- (void)releaseTagEditor:(NSNotification *)note{
    if (tagEditor) {
        [tagEditor release];
    }
}

#pragma mark splitview/toolbar management

- (void)setDualFieldInToolbar {
	NSView *dualSV = [field superview];
	[dualFieldView removeFromSuperviewWithoutNeedingDisplay];
	[dualSV removeFromSuperviewWithoutNeedingDisplay];
	[dualFieldView release];
	dualFieldItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"DualField"];
	[dualFieldItem setView:dualSV];
	[dualFieldItem setMaxSize:NSMakeSize(FLT_MAX, [dualSV frame].size.height)];
	[dualFieldItem setMinSize:NSMakeSize(50.0f, [dualSV frame].size.height)];
    [dualFieldItem setLabel:NSLocalizedString(@"Search or Create", @"placeholder text in search/create field")];
	
	toolbar = [[NSToolbar alloc] initWithIdentifier:@"NVToolbar"];
	[toolbar setAllowsUserCustomization:NO];
	[toolbar setAutosavesConfiguration:NO];
	[toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[toolbar setShowsBaselineSeparator:YES];
    [toolbar setSizeMode:NSToolbarSizeModeSmall];
	[toolbar setDelegate:self];
	[window setToolbar:toolbar];
	
	[window setShowsToolbarButton:NO];
	titleBarButton = [[TitlebarButton alloc] initWithFrame:NSMakeRect(0, 0, 19.0, 19.0) pullsDown:YES];
	[titleBarButton addToWindow:window];
	
	[field setDelegate:self];
    [self setDualFieldIsVisible:[self dualFieldIsVisible]];
}

- (void)setDualFieldInView {
	NSView *dualSV = [field superview];
    [dualSV setAutoresizesSubviews:YES];
    [dualSV setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];
    //	BOOL dfIsVis = [self dualFieldIsVisible];
	[dualSV removeFromSuperviewWithoutNeedingDisplay];
	NSSize wSize = [mainView frame].size;
	wSize.height-=kDualFieldHeight;
	[splitView setFrameSize:wSize];
	NSRect dfViewFrame = [splitView frame];
	dfViewFrame.size.height = kDualFieldHeight;
	dfViewFrame.origin.y = [splitView frame].size.height;
	dualFieldView = [[[DFView alloc] initWithFrame:dfViewFrame] retain];
    [dualFieldView setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];
    [dualFieldView setAutoresizesSubviews:YES];
    [mainView addSubview:dualFieldView positioned:NSWindowAbove relativeTo:splitView];
	NSRect dsvFrame = [dualSV frame];
	dsvFrame.origin.y +=1.0;
    if (![mainView isInFullScreenMode]) {
        dsvFrame.origin.y +=4.0;
    }
	dsvFrame.size.width = roundf(wSize.width * 0.99);
	dsvFrame.origin.x =roundf(wSize.width *0.005);
	[dualSV setFrame:dsvFrame];
	[dualFieldView addSubview:dualSV];
    [field setNextKeyView:textView];
    [textView setNextKeyView:field];
    [self setDualFieldIsVisible:[self dualFieldIsVisible]];
    [toolbar release];
    [titleBarButton release];
}

- (void)setDualFieldIsVisible:(BOOL)isVis{
    if ([self dualFieldIsVisible]!=isVis) {
        if (IsLionOrLater||![mainView isInFullScreenMode]) {
            [toolbar setVisible:isVis];
        }else{
            NSSize wSize = [mainView frame].size;
            if (isVis) {
                wSize.height -= kDualFieldHeight;
            }
            [dualFieldView setHidden:!isVis];
            [splitView setFrameSize:wSize];
            //        [splitView adjustSubviews];
            [mainView setNeedsDisplay:YES];
        }
    }
    //        [[NSUserDefaults standardUserDefaults] setBool:!isVis forKey:@"ToolbarHidden"];
    if (isVis) {
        [window setTitle:@"nvALT"];
        if (currentNote&&(![[field stringValue]isEqualToString:titleOfNote(currentNote)]))
            [field setStringValue:titleOfNote(currentNote)];
        
        
        [window setInitialFirstResponder:field];
        
    }else{
        if (currentNote)
            [window setTitle:titleOfNote(currentNote)];
        
        
        [window setInitialFirstResponder:textView];
    }
    
    if (![[NSArray arrayWithObjects:textView,notesTableView,theFieldEditor, nil] containsObject:[window firstResponder]]) {
        if (isVis) {
            [field selectText:self];
        }else{
            [window makeFirstResponder:textView];
        }
    }
    [[NSUserDefaults standardUserDefaults] setBool:!isVis forKey:@"ToolbarHidden"];
}


- (BOOL)dualFieldIsVisible{
    BOOL dfIsVis=NO;
    if (!IsLionOrLater&&[mainView isInFullScreenMode]) {
        if (dualFieldView) {
            dfIsVis=![dualFieldView isHidden];
        }
    }else{
        dfIsVis=[toolbar isVisible];
    }
    return dfIsVis;
}

- (IBAction)toggleCollapse:(id)sender{
    
	if ([notesSubview isCollapsed]) {
		[self setDualFieldIsVisible:YES];
		//[splitView setDivider: verticalDividerImg];//horiz ? nil : verticalDividerImg];
		//BOOL horiz = [prefsController horizontalLayout];
        [splitView setDividerThickness:8.75f];
		[notesSubview expand];
	}else {
        [self setDualFieldIsVisible:NO];
        [splitView setDividerThickness: 7.0];
        [notesSubview collapse];
        [window makeFirstResponder:textView];
	}
    [splitView adjustSubviews];
    [mainView setNeedsDisplay:YES];
}

#pragma mark fullscreen methods


#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7

- (NSApplicationPresentationOptions)window:(NSWindow *)window
      willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)rect{
    
    BOOL autohideTB=NO;
    wasDFVisible=[self dualFieldIsVisible];
    NSUInteger options=NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock;
    if (autohideTB) {
        return options|NSApplicationPresentationAutoHideToolbar;
    }
    
    return options;
}

- (void)windowWillEnterFullScreen:(NSNotification *)aNotification{
    //   / [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    if (![splitView isVertical]) {
        [self switchViewLayout:self];
        wasVert = NO;
    }else {
        wasVert = YES;
        //[splitView adjustSubviews];
    }
    
}

- (void)windowDidEnterFullScreen:(NSNotification *)aNotification{
    
    [self setDualFieldIsVisible:wasDFVisible];
    
//    [self performSelector:@selector(postToggleToolbar:) withObject:[NSNumber numberWithBool:wasDFVisible] afterDelay:0.0001];
    [textView updateInsetAndForceLayout:YES];
}

- (NSArray *)customWindowsToExitFullScreenForWindow:(NSWindow *)aWindow{
    fieldWasFirstResponder = [[NSArray arrayWithObjects:field,theFieldEditor, nil] containsObject:[aWindow firstResponder]];
    return nil;
}

- (void)windowWillExitFullScreen:(NSNotification *)aNotification{
    wasDFVisible=[self dualFieldIsVisible]&&(![notesSubview isCollapsed]);
    if ((!wasVert)&&([splitView isVertical])) {
        [self switchViewLayout:self];
    }
}
- (void)windowDidExitFullScreen:(NSNotification *)notification{
    //  [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorMoveToActiveSpace];
    
    [self setDualFieldIsVisible:wasDFVisible];
//    [self performSelector:@selector(postToggleToolbar:) withObject:[NSNumber numberWithBool:wasDFVisible] afterDelay:0.0001];
    if (wasDFVisible&&fieldWasFirstResponder) {
        [window makeFirstResponder:field];
    }
    
    [textView updateInsetAndForceLayout:YES];
}

- (void)postToggleToolbar:(NSNumber *)boolNum{
    [self setDualFieldIsVisible:[boolNum boolValue]];
}

#endif

- (BOOL)isInFullScreen{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if (IsLionOrLater) {
        return (([window styleMask]&NSFullScreenWindowMask)>0);
    }
#endif
    return [mainView isInFullScreenMode];
    
}

- (IBAction)switchFullScreen:(id)sender
{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if (IsLionOrLater) {
        //        BOOL inFS=[self isInFullScreen];
        [window toggleFullScreen:nil];
        return;
	}   
#endif
    if(IsLeopardOrLater){
        
        self.isEditing = NO;
        NSResponder *currentResponder = [window firstResponder];
        NSDictionary* options;
        if (([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDockIcon"])&&(IsSnowLeopardOrLater)) {
            options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:(NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationHideDock)],@"NSFullScreenModeApplicationPresentationOptions", nil];
        }else {
            options = [NSDictionary dictionaryWithObjectsAndKeys:nil];
        }
        CGFloat colW = [notesSubview dimension];
        
        wasDFVisible=[self dualFieldIsVisible];
        if ([mainView isInFullScreenMode]) {
            window = normalWindow;
            [mainView exitFullScreenModeWithOptions:options];
            
            [notesSubview setDimension:colW];
            [self setDualFieldInToolbar];
            [splitView setFrameSize:[mainView frame].size];
            if ((!wasVert)&&([splitView isVertical])) {
                [self switchViewLayout:self];
            }else{
                [splitView adjustSubviews];
            }
            [window makeKeyAndOrderFront:self];
        }else {
            [mainView enterFullScreenMode:[window screen]  withOptions:options];
            [notesSubview setDimension:colW];
            [self setDualFieldInView];
            if (![splitView isVertical]) {
                [self switchViewLayout:self];
                wasVert = NO;
            }else {
                wasVert = YES;
                [splitView adjustSubviews];
            }
            normalWindow = window;
            [normalWindow orderOut:self];
            window = [mainView window];
            //[NSApp setDelegate:self];
            [notesTableView setDelegate:self];
            [window setDelegate:self];
            // [window setInitialFirstResponder:field];
            [field setDelegate:self];
            [textView setDelegate:self];
            [splitView setDelegate:self];
            NSSize wSize = [mainView frame].size;
            wSize.height = [splitView frame].size.height;
            [splitView setFrameSize:wSize];
        }
        [window setBackgroundColor:backgrndColor];
        
        [self setDualFieldIsVisible:wasDFVisible];
        
        [textView updateInsetAndForceLayout:YES];
        if ([[currentResponder description] rangeOfString:@"_NSFullScreenWindow"].length>0){
            currentResponder = textView;
        }
        if (([currentResponder isKindOfClass:[NSTextView class]])&&(![currentResponder isKindOfClass:[LinkingEditor class]])) {
            currentResponder = field;
        }
        
        [splitView setNextKeyView:notesTableView];
        [field setNextKeyView:textView];
        [textView setNextKeyView:field];
        [window setAutorecalculatesKeyViewLoop:NO];
        [window makeFirstResponder:currentResponder];
        
        [mainView setNeedsDisplay:YES];
        if (![NSApp isActive]) {
            [NSApp activateIgnoringOtherApps:YES];
        }
    }
}

#pragma mark color scheme methods
    
    - (IBAction)setBWColorScheme:(id)sender{
        userScheme=0;
        [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
        
        [self setForegrndColor:[[NSColor colorWithCalibratedWhite:0.02f alpha:1.0f]colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
        [self setBackgrndColor:[[NSColor colorWithCalibratedWhite:0.98f alpha:1.0f]colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
        NSMenu *mainM = [NSApp mainMenu];
        NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
        mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
        viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
        [[mainM itemAtIndex:0] setState:1];
        [[mainM itemAtIndex:1] setState:0];
        [[mainM itemAtIndex:2] setState:0];
        
        [[viewM  itemAtIndex:0] setState:1];
        [[viewM  itemAtIndex:1] setState:0];
        [[viewM  itemAtIndex:2] setState:0];
        [self updateColorScheme];
    }
    
    - (IBAction)setLCColorScheme:(id)sender{
        userScheme=1;
        [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];

        [self setForegrndColor:[NSColor colorWithCalibratedRed:0.2430 green:0.2430 blue:0.2430 alpha:1.0]];
        
        [self setBackgrndColor:[NSColor colorWithCalibratedRed:0.902 green:0.902 blue:0.902 alpha:1.0]];
        NSMenu *mainM = [NSApp mainMenu];
        NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
        mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
        viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
        [[mainM itemAtIndex:0] setState:0];
        [[mainM itemAtIndex:1] setState:1];
        [[mainM itemAtIndex:2] setState:0];
        
        [[viewM  itemAtIndex:0] setState:0];
        [[viewM  itemAtIndex:1] setState:1];
        [[viewM  itemAtIndex:2] setState:0];
        [self updateColorScheme];
    }
    
    - (IBAction)setUserColorScheme:(id)sender{
        userScheme=2;
        [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
        [self setForegrndColor:[prefsController foregroundTextColor]];
        [self setBackgrndColor:[prefsController backgroundTextColor]];
        NSMenu *mainM = [NSApp mainMenu];
        NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
        mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
        viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
        [[mainM itemAtIndex:0] setState:0];
        [[mainM itemAtIndex:1] setState:0];
        [[mainM itemAtIndex:2] setState:1];
        
        [[viewM  itemAtIndex:0] setState:0];
        [[viewM  itemAtIndex:1] setState:0];
        [[viewM  itemAtIndex:2] setState:1];
        //NSLog(@"foreground col is: %@",[foregrndColor description]);
        //NSLog(@"background col is: %@",[backgrndColor description]);
        [self updateColorScheme];
    }
    
- (void)updateColorScheme{
    if (!IsLionOrLater) {
        
        [window setBackgroundColor:backgrndColor];//[NSColor blueColor]
        [dualFieldView setBackgroundColor:backgrndColor];
    }
    [mainView setBackgroundColor:backgrndColor];
    [notesTableView setBackgroundColor:backgrndColor];
    [NotesTableHeaderCell setTxtColor:foregrndColor];
    [notationController setForegroundTextColor:foregrndColor];
    
    [textView setBackgroundColor:backgrndColor];
    [textView updateTextColors];
    [self updateFieldAttributes];
    if (currentNote) {
        [self contentsUpdatedForNote:currentNote];
    }
    [dividerShader updateColors:backgrndColor];
    [splitView setNeedsDisplay:YES];
}

    - (void)updateFieldAttributes{
        if (!foregrndColor) {
            foregrndColor = [self foregrndColor];
        }
        if (!backgrndColor) {
            backgrndColor = [self backgrndColor];
        }
        if (fieldAttributes) {
            [fieldAttributes release];
        }
        fieldAttributes = [[NSDictionary dictionaryWithObject:[textView _selectionColorForForegroundColor:foregrndColor backgroundColor:backgrndColor] forKey:NSBackgroundColorAttributeName] retain];
        
        if (self.isEditing) {
            [theFieldEditor setDrawsBackground:NO];
            [theFieldEditor setTextColor:foregrndColor];
            // [theFieldEditor setBackgroundColor:backgrndColor];
            [theFieldEditor setSelectedTextAttributes:fieldAttributes];
            [theFieldEditor setInsertionPointColor:foregrndColor];
            //   [notesTableView setNeedsDisplay:YES];
            
        }
        
    }
    
    - (void)setBackgrndColor:(NSColor *)inColor{
        if (backgrndColor) {
            [backgrndColor release];
        }
        backgrndColor = [inColor retain];
    }
    
    - (void)setForegrndColor:(NSColor *)inColor{
        if (foregrndColor) {
            [foregrndColor release];
        }
        foregrndColor = [inColor retain];
    }
    
    - (NSColor *)backgrndColor{
        if (!backgrndColor) {
            NSColor *theColor;// = [NSColor redColor];
            if (!userScheme) {
                userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
            }
            if (userScheme==0) {
                theColor = [NSColor colorWithCalibratedRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
            }else if (userScheme==1) {
                theColor = [NSColor colorWithCalibratedRed:0.874f green:0.874f blue:0.874f alpha:1.0f];
            }else if (userScheme==2) {
                NSData *theData = [[NSUserDefaults standardUserDefaults] dataForKey:@"BackgroundTextColor"];
                if (theData){
                    theColor = (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
                }else {
                    theColor = [prefsController backgroundTextColor];
                }
                
            }else{
                theColor =  [NSColor whiteColor];
            }
            [self setBackgrndColor:theColor];
            
            return theColor;
        }else {
            return backgrndColor;
        }
        
    }
    
    - (NSColor *)foregrndColor{
        if (!foregrndColor) {
            NSColor *theColor = [NSColor blackColor];
            if (!userScheme) {
                userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
            }
            
            if (userScheme==0) {
                theColor = [NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:1.0f];
            }else if (userScheme==1) {
                theColor = [NSColor colorWithCalibratedRed:0.142f green:0.142f blue:0.142f alpha:1.0f];
            }else if (userScheme==2) {
                
                NSData *theData = [[NSUserDefaults standardUserDefaults] dataForKey:@"ForegroundTextColor"];
                if (theData){
                    theColor = (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
                }else {
                    theColor = [prefsController foregroundTextColor];
                }
            }
            [self setForegrndColor:theColor];
            return theColor;
        }else {
            return foregrndColor;
        }
        
    }
    
#pragma mark control/opt key hold down to pop word count/preview window
    
    - (void)updateWordCount:(BOOL)doIt{
        if (doIt) {            
            NSUInteger theCount = [[[textView textStorage] words] count];

            if (theCount > 0) {
                [wordCounter setStringValue:[[NSString stringWithFormat:@"%d", theCount] stringByAppendingString:theCount == 1 ? @" word" : @" words"]];
            }else {
                [wordCounter setStringValue:@""];
            }
        }
    }
    
    - (void)popWordCount:(BOOL)showIt{
        NSUInteger curEv=[[NSApp currentEvent] type];
        if ((curEv==NSFlagsChanged)||(curEv==NSMouseMoved)||(curEv==NSMouseEntered)||(curEv==NSMouseExited)||(curEv==NSScrollWheel)){
            if (showIt) {
                if (([wordCounter isHidden])&&([prefsController showWordCount])) {
                    [self updateWordCount:YES];
                    [wordCounter setHidden:NO];
                    popped=1;
                }
            }else {
                if ((![wordCounter isHidden])&&([prefsController showWordCount])) {
                    [wordCounter setHidden:YES];
                    [wordCounter setStringValue:@""];
                    popped=0;
                }
            }
        }
    }
    
    - (IBAction)toggleWordCount:(id)sender{
        
        
        [prefsController synchronize];
        if ([prefsController showWordCount]) {
            [self updateWordCount:YES];
            [wordCounter setHidden:NO];
            
            popped=1;
        }else {
            [wordCounter setHidden:YES];
            [wordCounter setStringValue:@""];
            popped=0;
        }
        
        if (![[sender className] isEqualToString:@"NSMenuItem"]) {
            [prefsController setShowWordCount:![prefsController showWordCount]];
        }
        
    }
    
    - (void)flagsChanged:(NSEvent *)theEvent{
        if ((ModFlagger==0)&&(popped==0)) {            
            NSUInteger flags=[theEvent modifierFlags];
            if (((flags&NSDeviceIndependentModifierFlagsMask)==(flags&NSAlternateKeyMask))&&((flags&NSDeviceIndependentModifierFlagsMask)>0)) { //only option key down
                ModFlagger = 1;
                modifierTimer = [[NSTimer scheduledTimerWithTimeInterval:1.2
                                                                  target:self
                                                                selector:@selector(updateModifier:)
                                                                userInfo:@"option"
                                                                 repeats:NO] retain];
                return;
            }else if (((flags&NSDeviceIndependentModifierFlagsMask)==(flags&NSControlKeyMask))&&((flags&NSDeviceIndependentModifierFlagsMask)>0)) { //only ctrl key is down
                ModFlagger = 2;
                modifierTimer = [[NSTimer scheduledTimerWithTimeInterval:1.2
                                                                  target:self
                                                                selector:@selector(updateModifier:)
                                                                userInfo:@"control"
                                                                 repeats:NO] retain];
                return;
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    }
    
    - (void)updateModifier:(NSTimer*)theTimer{
        if ([theTimer isValid]) {
            if((ModFlagger>0)&&(popped==0)){
                if ([[theTimer userInfo] isEqualToString:@"option"]) {
                    [self popWordCount:YES];
                    popped=1;
                }else if ([[theTimer userInfo] isEqualToString:@"control"]) {
                    [self popPreview:YES];
                    popped=2;
                }
            }
            [theTimer invalidate];
        }
    }
    
    - (void)resetModTimers:(NSNotification *)notification{
        
        
        if ((ModFlagger>0)||(popped>0)) {
            ModFlagger = 0;
            if (modifierTimer){
                if ([modifierTimer isValid]) {
                    [modifierTimer invalidate];
                }
                modifierTimer = nil;
                [modifierTimer release];
            }
            if (popped==1) {
                [self performSelector:@selector(popWordCount:) withObject:NO afterDelay:0.1];
            }else if (popped==2) {
                [self performSelector:@selector(popPreview:) withObject:NO afterDelay:0.1];
            }
            popped=0;
        }
    }
    
    
#pragma mark Preview-related and to be extracted into separate files
    
    - (void)popPreview:(BOOL)showIt{
        NSUInteger curEv=[[NSApp currentEvent] type];
        if((curEv==NSFlagsChanged)||(curEv==NSMouseMoved)||(curEv==NSMouseEntered)||(curEv==NSMouseExited)||(curEv==NSScrollWheel)){
            if ([previewToggler state]==0) {
                if (showIt) {
                    if (![previewController previewIsVisible]) {
                        [self togglePreview:self];
                    }
                    popped=2;
                }else {
                    if ([previewController previewIsVisible]) {
                        [self togglePreview:self];
                    }
                    popped=0;
                }
            }
        }
    }
    
    
    - (IBAction)togglePreview:(id)sender
    {
        BOOL doIt = (currentNote != nil);
        if ([previewController previewIsVisible]) {
            doIt = YES;
        }
        if ([[sender className] isEqualToString:@"NSMenuItem"]) {
			[sender setState:![sender state]];
        }
        if (doIt) {
            [previewController togglePreview:self];
        }
    }
    
    - (void)ensurePreviewIsVisible
    {
        if (![[previewController window] isVisible]) {
            [previewController togglePreview:self];
        }
    }
    
    - (IBAction)toggleSourceView:(id)sender
    {
        [self ensurePreviewIsVisible];
        [previewController switchTabs:self];
    }
    
    - (IBAction)savePreview:(id)sender
    {
        [self ensurePreviewIsVisible];
        [previewController saveHTML:self];
    }
    
    - (IBAction)sharePreview:(id)sender
    {
        [self ensurePreviewIsVisible];
        [previewController shareAsk:self];
    }
    
    - (IBAction)lockPreview:(id)sender
    {
        if (![previewController previewIsVisible])
            return;
        if ([previewController isPreviewSticky]) {
            [previewController makePreviewNotSticky:self];
        } else {
            [previewController makePreviewSticky:self];
        }
    }
    
    - (IBAction)printPreview:(id)sender
    {
        [self ensurePreviewIsVisible];
        [previewController printPreview:self];
    }
    
    - (void)postTextUpdate{
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextViewHasChangedContents" object:self];
    }
    
    - (IBAction)selectPreviewMode:(id)sender
    {
        NSMenuItem *previewItem = sender;
        currentPreviewMode = [previewItem tag];
        
        // update user defaults
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:currentPreviewMode]
                                                  forKey:@"markupPreviewMode"];
        
        [self postTextUpdate];
    }
    
    - (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client{
        
        if (self.isEditing) {
            
            if (!fieldAttributes) {
                [self updateFieldAttributes];
            }else{
                if (!foregrndColor) {
                    foregrndColor = [self foregrndColor];
                }
                if (!backgrndColor) {
                    backgrndColor = [self backgrndColor];
                }
                [theFieldEditor setDrawsBackground:NO];
                // [theFieldEditor setBackgroundColor:backgrndColor];
                [theFieldEditor setTextColor:foregrndColor];
                [theFieldEditor setSelectedTextAttributes:fieldAttributes];
                [theFieldEditor setInsertionPointColor:foregrndColor];
                
                // [notesTableView setNeedsDisplay:YES];
            }
        }else {//if (client==field) {
            [theFieldEditor setDrawsBackground:NO];
            [theFieldEditor setSelectedTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor selectedTextBackgroundColor], NSBackgroundColorAttributeName, nil]];
            [theFieldEditor setInsertionPointColor:[NSColor blackColor]];
        }
        // NSLog(@"window first is :%@",[window firstResponder]);
        //NSLog(@"client is :%@",client);
        //}
        
        
        return theFieldEditor;
        //[super windowWillReturnFieldEditor:sender toObject:client];
    }
    
    - (void)updateRTL
    {
        if ([prefsController rtl]) {
            [textView setBaseWritingDirection:NSWritingDirectionRightToLeft range:NSMakeRange(0, [[textView string] length])];
        } else {
            [textView setBaseWritingDirection:NSWritingDirectionLeftToRight range:NSMakeRange(0, [[textView string] length])];
        }
    }
    
    - (void)refreshNotesList
    {
        [notesTableView setNeedsDisplay:YES];
    }
    
    
    
#pragma mark toggleDock
    - (void)togDockIcon:(NSNotification *)notification{
        
        [NSApp hide:self];
        BOOL showIt=[[notification object]boolValue];
        if (showIt) {
            [self performSelectorOnMainThread:@selector(showDockIcon) withObject:nil waitUntilDone:NO];
        }else {
            [self performSelectorOnMainThread:@selector(hideDockIconAfterDelay) withObject:nil waitUntilDone:NO];
            
        }
    }
    
    - (void)showDockIcon{
        if (IsLionOrLater) {
            ProcessSerialNumber psn = { 0, kCurrentProcess };
            OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToForegroundApplication);
            if( returnCode != 0) {
                NSLog(@"Could not bring the application to front. Error %d", returnCode);
            }

        }else{
            enum {NSApplicationActivationPolicyRegular};
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
              [self performSelector:@selector(reActivate:) withObject:self afterDelay:0.16];
    }

    - (void)hideDockIcon{
        //    id fullPath = [[NSBundle mainBundle] executablePath];
        //    NSArray *arg = [NSArray arrayWithObjects:nil];
        //    [NSTask launchedTaskWithLaunchPath:fullPath arguments:arg];
        //    [NSApp terminate:sender];
        if (IsLionOrLater) {
            ProcessSerialNumber psn = { 0, kCurrentProcess };
            OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToUIElementApplication);
            if( returnCode != 0) {
                NSLog(@"Could not bring the application to front. Error %d", returnCode);
            }
            if (!statusItem) {
                [self setUpStatusBarItem];
            }
            
            [self performSelector:@selector(reActivate:) withObject:self afterDelay:0.36];
        }else{
//            NSLog(@"hiding dock incon in snow leopard");
            id fullPath = [[NSBundle mainBundle] executablePath];
            NSArray *arg = [NSArray arrayWithObjects:nil];
            [NSTask launchedTaskWithLaunchPath:fullPath arguments:arg];
            [NSApp terminate:self];
        }
        
    }
    
    - (void)reActivate:(id)sender{
        [NSApp activateIgnoringOtherApps:YES];
    }
    
    - (void)hideDockIconAfterDelay{
        
        [self performSelector:@selector(hideDockIcon) withObject:nil afterDelay:0.22];
    }
    
- (void)setUpStatusBarItem{
    NSRect viewFrame = NSMakeRect(0.0f, 0.0f, 24.0f,[[NSStatusBar systemStatusBar] thickness]);
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:24.0f] retain];
    cView = [[[StatusItemView alloc] initWithFrame:viewFrame] autorelease];
    [statusItem setView:cView];
    
    [[NSNotificationCenter defaultCenter]postNotificationName:@"StatusBarMenuIsAwake" object:statBarMenu];
}

    - (void)toggleStatusItem:(NSNotification *)notification{
        if (!statusItem) {
            [self setUpStatusBarItem];
        }else{
            [[NSStatusBar systemStatusBar]removeStatusItem:statusItem];
            cView=nil;
            statusItem=nil;
        }
    }
    
    
#pragma mark NSPREDICATE TO FIND MARKDOWN REFERENCE LINKS
//    - (IBAction)testThing:(id)sender{
        //    NSString *testString=@"not []http://sdfas as\n\not [][]\n not [](http://)\n     a   [a ref]: http://nytimes.com \n squirels [another ref]: http://google.com    \n http://squarshit \n how's tthat http his lorem ipsum";
        //    
        //    NSArray *foundLinks=[self referenceLinksInString:testString];
        //    if (foundLinks&&([foundLinks count]>0)) {
        //        NSLog(@"found'em:%@",[foundLinks description]);
        //    }else{
        //        NSLog(@"didn't find shit");
        //    }
//    }
    
    - (NSArray *)referenceLinksInString:(NSString *)contentString{    
        NSString *wildString = @"*[*]:*http*"; //This is where you define your match string.    
        NSPredicate *matchPred = [NSPredicate predicateWithFormat:@"SELF LIKE[cd] %@", wildString]; 
        /*
         Breaking it down:
         SELF is the string your testing
         [cd] makes the test case insensitive
         LIKE is one of the predicate search possiblities. It's NOT regex, but lets you use wildcards '?' for one character and '*' for any number of characters
         MATCH (not used) is what you would use for Regex. And you'd set it up similiar to LIKE. I don't really know regex, and I can't quite get it to work. But that might be because I don't know regex. 
         %@ you need to pass in the search string like this, rather than just embedding it in the format string. so DON'T USE something like [NSPredicate predicateWithFormat:@"SELF LIKE[cd] *[*]:*http*"]
         */
        
        NSMutableArray *referenceLinks=[NSMutableArray new];
        
        //enumerateLinesUsing block seems like a good way to go line by line thru the note and test each line for the regex match of a reference link. Downside is that it uses blocks so requires 10.6+. Let's get it to work and then we can figure out a Leopard friendly way of doing this; which I don't think will be a problem (famous last words).
        [contentString enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) { 
            if([matchPred evaluateWithObject:line]){
                //            NSLog(@"%@ matched",line);
                NSString *theRef=line;
                //theRef=[line substring...]  here you want to parse out and get just the name of the reference link we'd want to offer up to the user in the autocomplete
                //and maybe trim out whitespace
                theRef = [theRef stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                //check to make sure its not empty
                if(![theRef isEqualToString:@""]){
                    [referenceLinks addObject:theRef];
                } 		
            }	
        }];
        //create an immutable array safe for returning
        NSArray *returnArray=[NSArray array];
        //see if we found anything
        if(referenceLinks&&([referenceLinks count]>0))
        {
            returnArray=[NSArray arrayWithArray:referenceLinks];
        }
        [referenceLinks release];
        return returnArray;
    }
    
    @end
