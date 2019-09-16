/* -*- mode: objc -*- */
//
// Project: NEXTSPACE - DesktopKit framework
//
// Description: Standard panel for application help.
//
// Copyright (C) 2019 Sergii Stoian
//
// This application is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation; either
// version 2 of the License, or (at your option) any later version.
//
// This application is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Library General Public License for more details.
//
// You should have received a copy of the GNU General Public
// License along with this library; if not, write to the Free
// Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
//
#import <Foundation/Foundation.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSNibLoading.h>
#import <GNUstepGUI/GSHelpAttachment.h>

#import "NXTPanelLoader.h"
#import "NXTAlert.h"
#import "NXTListView.h"
#import "NXTHelpPanel.h"
#import "NXTSplitView.h"

// Singleton
static NXTHelpPanel *_sharedHelpPanel = nil;

@implementation NSString (NSStringTextFinding)

- (NSRange)findString:(NSString *)string
        selectedRange:(NSRange)selectedRange
              options:(unsigned)options
                 wrap:(BOOL)wrap
{
  BOOL         forwards = (options & NSBackwardsSearch) == 0;
  unsigned int length = [self length];
  NSRange      searchRange, range;

  if (forwards) {
    searchRange.location = NSMaxRange(selectedRange);
    searchRange.length = length - searchRange.location;
    range = [self rangeOfString:string options:options range:searchRange];

    if ((range.length == 0) && wrap) {
      /* If not found look at the first part of the string */
      searchRange.location = 0;
      searchRange.length = selectedRange.location;
      range = [self rangeOfString:string options:options range:searchRange];
    }
  }
  else {
    searchRange.location = 0;
    searchRange.length = selectedRange.location;
    range = [self rangeOfString:string options:options range:searchRange];
    
    if ((range.length == 0) && wrap) {
      searchRange.location = NSMaxRange(selectedRange);
      searchRange.length = length - searchRange.location;
      range = [self rangeOfString:string options:options range:searchRange];
    }
  }
  return range;
}

@end

@interface NXTHelpArticle : NSTextView
@end
@implementation NXTHelpArticle

- (void)resetCursorRects
{
  NSSize   aSize;
  NSRange  gRange = [_layoutManager glyphRangeForBoundingRect:[self bounds]
                                              inTextContainer:_textContainer];
  NSRect   gRect;
  
  for (NSUInteger index = 0; index < gRange.length; index++) {
    aSize = [_layoutManager attachmentSizeForGlyphAtIndex:index];
    if (aSize.width == 11) {
      gRect = [_layoutManager boundingRectForGlyphRange:NSMakeRange(index,1)
                                        inTextContainer:_textContainer];
      [self addCursorRect:gRect cursor:[NSCursor pointingHandCursor]];
    }
  }
  NSLog(@"resetCursorRects");
}

@end

@implementation NXTHelpPanel (PrivateMethods)

- (void)_setHelpDirectory:(NSString *)helpDirectory
{
  if (_helpDirectory == helpDirectory) {
    return;
  }
  
  if (_helpDirectory) {
    [_helpDirectory release];
  }
  _helpDirectory = [[NSString alloc] initWithString:helpDirectory];
}

- (void)_loadTableOfContents:(NSString *)tocFilePath
{
  NSMutableArray     *titles, *attachments;
  NSAttributedString *attrString;
  NSString           *text, *t;
  NSRange            range;
  NSDictionary       *attrs;
  id                 attachment;

  NSLog(@"Load TOC from: %@", tocFilePath);

  titles = [NSMutableArray new];
  attachments = [NSMutableArray new];
  attrString = [[NSAttributedString alloc]
                   initWithRTF:[NSData dataWithContentsOfFile:tocFilePath]
                 documentAttributes:NULL];
  text = [attrString string];
    
  for (int i = 0; i < [text length]; i++) {
    attrs = [attrString attributesAtIndex:i effectiveRange:&range];
    if ((attachment = [attrs objectForKey:@"NSAttachment"]) != nil) {
      range = [text lineRangeForRange:range];
      // Skip attachment symbol
      range.location++;
      range.length--;
      // Exclude new line character if any
      if ([[text substringFromRange:range]
            characterAtIndex:range.length-1] == '\n') {
        range.length--;
      }
      [titles addObject:[attrString attributedSubstringFromRange:range]];
      [attachments addObject:[attachment fileName]];
    }
    else {
      if ([[text substringFromRange:range] length] > 0) {
        // Exclude new line character if any
        if ([[text substringFromRange:range] characterAtIndex:range.length-1] == '\n') {
          range.length--;
        }
        [titles addObject:[attrString attributedSubstringFromRange:range]];
        [attachments addObject:@""];
      }
    }
    i = range.location + range.length;
  }

  if (tocTitles != nil) [titles release];
  tocTitles = [[NSArray alloc] initWithArray:titles];
  [titles release];
  if (tocAttachments != nil) [titles release];
  tocAttachments = [[NSArray alloc] initWithArray:attachments];
  [attachments release];
  
  [attrString release];
}

- (NSString *)_articlePathForAttachment:(NSString *)attachment
{
  NSString *artPath = nil;

  if (attachment && [attachment isEqualToString:@""] == NO) {
    artPath = [_helpDirectory stringByAppendingPathComponent:attachment];
    if ([[NSFileManager defaultManager] fileExistsAtPath:artPath] == NO) {
      NXTRunAlertPanel(@"Help", @"Help file `%@` doesn't exist",
                       @"OK", nil, nil, attachment);
      artPath = nil;
    }
  }
  return artPath;
}

- (void)_showArticle
{
  NSCell   *cell = [tocList selectedItem];
  NSString *docPath;
  NSString *artPath;

  docPath = [cell representedObject];
  NSLog(@"[HelpPanel] showArticle doc path: %@", docPath);
  artPath = [self _articlePathForAttachment:docPath];
  
  if (artPath != nil) {
    if (historyPosition < historyLength) {
      historyPosition++;
      history[historyPosition] = [tocList indexOfItem:cell];
      NSLog(@"Postion after history grow %i", historyPosition);
    }
    [articleView readRTFDFromFile:artPath];
    [articleView scrollRangeToVisible:NSMakeRange(0,0)];
  }
  if (historyPosition > 0) {
    [backtrackBtn setEnabled:YES];
  }
}

- (NSRange)_findInArcticleAtPath:(NSString *)path
{
  NSText       *reader = [NSText new];
  NSString     *text = nil;
  NSRange      range = NSMakeRange(0,0);
  NSRange      selectedRange = NSMakeRange(0,0);
  unsigned int options = NSCaseInsensitiveSearch;
  BOOL         lastFindWasSuccessful = NO;

  if ([reader readRTFDFromFile:path] != NO) {
    text = [reader string];
  }
  if (text && [text length]) {
    range = [text findString:[findField stringValue]
               selectedRange:selectedRange
                     options:options
                        wrap:NO];
  }
  [reader release];

  return range;
}

- (void)_performFind:(id)sender
{
  // Search opened article
  NSString     *text = [[articleView textStorage] string];
  NSRange      selectedRange= NSMakeRange(0,0);
  NSRange      range;
  unsigned int options = NSCaseInsensitiveSearch;
  BOOL         lastFindWasSuccessful = NO;
  
  if (text && [text length]) {
    selectedRange = [articleView selectedRange];
    if (selectedRange.length != 0) {
      selectedRange.location = selectedRange.location + selectedRange.length;
      selectedRange.length = 0;
    }
    range = [text findString:[findField stringValue]
               selectedRange:selectedRange
                     options:options
                        wrap:NO];
    if (range.length) {
      [articleView setSelectedRange:range];
      [articleView scrollRangeToVisible:range];
      lastFindWasSuccessful = YES;
    }
  }
  
  // Search through the articles, skips Index.rtfd
  if (!lastFindWasSuccessful) {
    NSUInteger index = [tocList indexOfItem:[tocList selectedItem]] + 1;
    NSString   *artPath;
    for (NSUInteger i = index; i < [tocAttachments count]; i++) {
      artPath = [self _articlePathForAttachment:[tocAttachments objectAtIndex:i]];
      if ([artPath isEqualToString:@""] == NO &&
          [[artPath lastPathComponent] isEqualToString:@"Index.rtfd"] == NO) {
        range = [self _findInArcticleAtPath:artPath];
        if (range.length > 0) {
          [tocList selectItemAtIndex:i];
          [self _showArticle];        
          [articleView setSelectedRange:range];
          [articleView scrollRangeToVisible:range];
          break;
        }
      }
    }
  }
}

- (void)_showIndex:(id)sender
{
  // Find item with `Index.rtfd` represented object
  for (int i = 0; i < [tocTitles count]; i++) {
    if ([tocAttachments[i] isEqualToString:@"Index.rtfd"]) {
      [tocList selectItemAtIndex:i];
      [self _showArticle];
      return;
    }
  }

  // Item was not found
  NXTRunAlertPanel(@"Help", @"No Index file found for this help.",
                   @"OK", nil, nil);
}

- (void)_goHistoryBack:(id)sender
{
  NSCell   *cell;
  NSString *artPath;
  
  NSLog(@"Backtrack at %d", historyPosition);
  if (historyPosition > 0) {
    historyPosition--;
    NSLog(@"Backtrack to %d - %lu", historyPosition, history[historyPosition]);
    [tocList selectItemAtIndex:history[historyPosition]];
    cell = [tocList selectedItem];
    artPath = [self _articlePathForAttachment:[cell representedObject]];
    [articleView readRTFDFromFile:artPath];
  }
  NSLog(@"Postion after backtrack %d", historyPosition);
  if (historyPosition == 0) {
    [backtrackBtn setEnabled:NO];
  }
}

@end

@implementation NXTHelpPanel : NSPanel

+ (NXTHelpPanel *)sharedHelpPanel
{
  if (_sharedHelpPanel == nil) {
    [self sharedHelpPanelWithDirectory:nil];
  }
    
  return _sharedHelpPanel;
}
+ (NXTHelpPanel *)sharedHelpPanelWithDirectory:(NSString *)helpDirectory
{
  NSString     *tocFilePath;
  NXTHelpPanel *panel;
  
  // Setup help directory if needed
  if (helpDirectory == nil) {
    helpDirectory = [[NSBundle mainBundle] pathForResource:@"Help"
                                                    ofType:@""
                                               inDirectory:@""];
  }
  
  // Check if TableOfContents exists inside helpDirectory
  tocFilePath = [NSString stringWithFormat:@"%@/TableOfContents.rtf",
                          helpDirectory];
  if ([[NSFileManager defaultManager] fileExistsAtPath:tocFilePath] == NO) {
    NXTRunAlertPanel(@"Help", @"NEXTSPACE Help isn't available for %@",
                     @"OK", nil, nil,
                     [[NSProcessInfo processInfo] processName]);
    return nil;
  }

  
  // Create instance
  if (_sharedHelpPanel == nil) {
    _sharedHelpPanel = [[NXTPanelLoader alloc] loadPanelNamed:@"NXTHelpPanel"];
    [_sharedHelpPanel _setHelpDirectory:helpDirectory];
    panel = _sharedHelpPanel;
  }
  else if ([helpDirectory isEqualToString:[_sharedHelpPanel helpDirectory]] == NO) {
    panel = [[NXTPanelLoader alloc] loadPanelNamed:@"NXTHelpPanel"];
    [panel _setHelpDirectory:helpDirectory];
  }
  else {
    panel = _sharedHelpPanel;
  }

  return panel;
}

- (id)init
{
  self = [NXTHelpPanel sharedHelpPanel];
  return self;
}

- (void)awakeFromNib
{
  [splitView setResizableState:NSOnState];

  // TOC list
  tocList = [[NXTListView alloc] initWithFrame:NSMakeRect(0,0,414,200)];
  [splitView addSubview:tocList];
  [tocList setTarget:self];
  [tocList setAction:@selector(_showArticle)];
  [tocList release];

  // Article
  NSScrollView *scrollView;
  scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,414,200)];
  [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [scrollView setHasVerticalScroller:YES];
  [scrollView setBorderType:NSBezelBorder];
  articleView = [[NXTHelpArticle alloc] initWithFrame:NSMakeRect(0,0,394,200)];
  [articleView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [articleView setEditable:NO];
  [articleView setDelegate:self];
  [scrollView setDocumentView:articleView];
  [splitView addSubview:scrollView];
  [scrollView release];

  // History (for Backtrack)
  historyLength = 20;
  historyPosition = -1;
  
  [splitView setPosition:145.0 ofDividerAtIndex:0];

  [self setTitle:[NSString stringWithFormat:@"%@ Help Panel",
                           [[NSProcessInfo processInfo] processName]]];
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin
{
  NSString *toc;

  if (place != NSWindowOut && !tocTitles) {
    toc = [_helpDirectory stringByAppendingPathComponent:@"TableOfContents.rtf"];
    [self _loadTableOfContents:toc];
    [tocList loadTitles:tocTitles andObjects:tocAttachments];
    [tocList selectItemAtIndex:0];
    [self _showArticle];
  }
  
  [super orderWindow:place relativeTo:otherWin];
}

// NSTextView delegate

- (void)textView:(NSTextView *)textView
   clickedOnCell:(id <NSTextAttachmentCell>)cell
          inRect:(NSRect)cellFrame
{
  GSHelpLinkAttachment *attachment = (GSHelpLinkAttachment *)[cell attachment];
  NSString             *fileName;
  NSString             *currentPath, *filePath;

  NSLog(@"Clicked on CELL(%.0fx%.0f): file:%@ marker:%@",
        [cell cellSize].width, [cell cellSize].height,
        [attachment fileName],
        [attachment markerName]);
  
  if ([attachment isKindOfClass:[GSHelpLinkAttachment class]]) {
    fileName = [attachment fileName];
    currentPath = [_helpDirectory stringByAppendingPathComponent:[self helpFile]];
    filePath = [[currentPath stringByDeletingLastPathComponent]
                 stringByAppendingPathComponent:fileName];
    NSLog(@"Will open: %@", filePath);
    // Select TOC item
    // Show article
    // [self _showArticle];
  }
}

// --- Managing the Contents

+ (void)setHelpDirectory:(NSString *)helpDirectory
{
  if (_sharedHelpPanel != nil) {
    [_sharedHelpPanel _setHelpDirectory:helpDirectory];
  }
}

// TODO
- (void)addSupplement:(NSString *)helpDirectory
               inPath:(NSString *)supplementPath
{
  NSWarnFLog(@"Not implemented");
}

- (NSString *)helpDirectory
{
  return _helpDirectory;
}

- (NSString *)helpFile
{
  return [[tocList selectedItem] representedObject];
}


// --- Attaching Help to Objects

// TODO
+ (void)attachHelpFile:(NSString *)filename
            markerName:(NSString *)markerName
                    to:(id)anObject
{
  NSWarnFLog(@"Not implemented");
}

// TODO
+ (void)detachHelpFrom:(id)anObject
{
  NSWarnFLog(@"Not implemented");
}

// --- Showing Help

// TODO
- (void)showFile:(NSString *)filename
        atMarker:(NSString *)markerName
{
  NSWarnFLog(@"Not implemented");
}

// TODO
- (BOOL)showHelpAttachedTo:(id)anObject
{
  NSWarnFLog(@"Not implemented");
  return NO;
}

// --- Printing 
// TODO
- (void)print:(id)sender
{
  NSLog(@"Not implemented");
}

@end
