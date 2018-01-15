//
//  Buglife+UIStuff.m
//  Pods
//
//  Created by David Schukin on 2/3/16.
//
//

#import "Buglife+UIStuff.h"
#import "LIFEBugButtonWindow.h"
#import "UIView+LIFEAdditions.h"
#import "LIFEMacros.h"
#import "LIFEOverlayWindow.h"
#import "LIFENotificationLogger.h"
#import "LIFECompatibilityUtils.h"
#import "LIFEAlertController.h"
#import "LIFEAlertAction.h"
#import "LIFEContainerWindow.h"
#import "LIFEContainerViewController.h"

// Block type that can be used as a handler for both LIFEAlertAction and UIAlertAction
typedef void (^LIFEOrUIAlertActionHandler)(NSObject *action);

@implementation Buglife (UIStuff)

+ (void)life_loadCategory_BuglifeUIStuff { }

#pragma mark - Bug Button

- (BOOL)isBugButtonWindowEnabled
{
    return self.bugButtonWindow != nil;
}

#pragma mark - UIAlert stuff

- (void)_presentAlertControllerForInvocation:(LIFEInvocationOptions)invocation withScreenshot:(UIImage *)screenshot
{
    [self _notifyBuglifeInvoked];
    
    // Hide the keyboard before showing the alert
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    UIView *firstResponder = [keyWindow life_firstResponder];
    
    if (firstResponder) {
        if ([firstResponder canResignFirstResponder]) {
            BOOL resigned = [firstResponder resignFirstResponder];
            
            if (resigned == NO) {
                LIFELogExtError(@"Buglife error: %@ returned YES from -canResignFirstResponder, but returned NO from -resignFirstResponder.", LIFEDebugDescription(firstResponder));
            }
        } else {
            LIFELogExtWarn(@"Buglife warning: Found first responder %@, but -canResignFirstResponder returned NO.", LIFEDebugDescription(firstResponder));
        }
    } else {
        LIFELogIntDebug(@"Buglife didn't find a first responder for window %@", LIFEDebugDescription(keyWindow));
    }

    BOOL bugButtonIsEnabled = self.isBugButtonWindowEnabled;

    if (bugButtonIsEnabled) {
        [self.bugButtonWindow setBugButtonHidden:YES animated:YES];
    }

    NSString *message = [self _alertMessageForInvocation:invocation];
    
    UIAlertControllerStyle style = UIAlertControllerStyleActionSheet;
    
    BOOL isIpad = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
    BOOL systemScreenshotThumbnailVisible = (invocation == LIFEInvocationOptionsScreenshot) && ([LIFECompatibilityUtils isiOS11OrHigher]);
    BOOL isScreenRecordingInvocation = (invocation == LIFEInvocationOptionsScreenRecordingFinished);
    
    if (isIpad || systemScreenshotThumbnailVisible || isScreenRecordingInvocation) {
        // On iPad, UIAlertControllerStyleActionSheet must be presented as a popover, so we just use an alert.
        // In iOS 11, if the user took a screenshot then we don't want to overlap the system screenshot thumbnail in the bottom left corner,
        // so we use an alert instead of an action sheet.
        // If it's a screen recording invocation, then we should match
        // the "alert" style of the "stop screen recording" alert.
        style = UIAlertControllerStyleAlert;
    }
    
    LIFEOrUIAlertActionHandler reportHandler = ^void(NSObject *action) {
        [self _presentReporterFromInvocation:invocation withScreenshot:screenshot animated:YES];
    };
    
    LIFEOrUIAlertActionHandler disableHandler;
    NSString *disableTitle;
    
    if (self.hideUntilNextLaunchButtonEnabled) {
        if (invocation == LIFEInvocationOptionsScreenRecordingFinished) {
            disableTitle = LIFELocalizedString(LIFEStringKey_DontAskUntilNextLaunch);
        } else if (invocation == LIFEInvocationOptionsFloatingButton) {
            disableTitle = LIFELocalizedString(LIFEStringKey_HideUntilNextLaunch);
        } else if (invocation == LIFEInvocationOptionsScreenshot) {
            disableTitle = LIFELocalizedString(LIFEStringKey_DontAskUntilNextLaunch);
        } else if (invocation == LIFEInvocationOptionsShake) {
            disableTitle = LIFELocalizedString(LIFEStringKey_DontAskUntilNextLaunch);
        } else if (invocation == LIFEInvocationOptionsNone) {
            // Do nothing
        }
        
        if (disableTitle) {
            disableHandler = ^void(NSObject *action) {
                if (bugButtonIsEnabled) {
                    [self.bugButtonWindow setBugButtonHidden:NO animated:YES];
                }
                
                [self _temporarilyDisableInvocation:invocation];
            };
        }
    }
    
    LIFEOrUIAlertActionHandler cancelHandler = ^void(NSObject *action) {
        if (bugButtonIsEnabled) {
            [self.bugButtonWindow setBugButtonHidden:NO animated:YES];
        }
        
        [firstResponder becomeFirstResponder];
        self.reportAlertOrWindowVisible = NO;
    };
    
    UIViewController *alert = [self alertControllerWithTitle:message image:screenshot preferredStyle:style reportHandler:reportHandler disableActionTitle:disableTitle disableHandler:disableHandler cancelHandler:cancelHandler];;
    
    if (!self.useLegacyReporterUI) {
        [self _showContainerWindowWithViewController:alert animated:YES];
    } else {
        LIFEOverlayWindow *alertWindow = [LIFEOverlayWindow overlayWindow];
        alertWindow.hidden = NO;
        [alertWindow.rootViewController presentViewController:alert animated:YES completion:NULL];
        self.overlayWindow = alertWindow;
        self.reportAlertOrWindowVisible = YES;
    }
}

- (nonnull UIViewController *)alertControllerWithTitle:(nonnull NSString *)title image:(nullable UIImage *)image preferredStyle:(UIAlertControllerStyle)style reportHandler:(LIFEOrUIAlertActionHandler)reportHandler disableActionTitle:(nullable NSString *)disableActionTitle disableHandler:(LIFEOrUIAlertActionHandler)disableHandler cancelHandler:(LIFEOrUIAlertActionHandler)cancelHandler
{
    if (!self.useLegacyReporterUI) {
        let alert = [LIFEAlertController alertControllerWithTitle:title message:nil preferredStyle:style];
        
        if (image) {
            [alert setImage:image];
        }
        
        let reportAction = [LIFEAlertAction actionWithTitle:LIFELocalizedString(LIFEStringKey_ReportABug) style:UIAlertActionStyleDefault handler:reportHandler];
        [alert addAction:reportAction];
        
        if (disableActionTitle != nil && disableHandler != nil) {
            let disableAction = [LIFEAlertAction actionWithTitle:disableActionTitle style:UIAlertActionStyleDestructive handler:disableHandler];
            [alert addAction:disableAction];
        }
        
        let cancelAction = [LIFEAlertAction actionWithTitle:LIFELocalizedString(LIFEStringKey_Cancel) style:UIAlertActionStyleCancel handler:cancelHandler];
        [alert addAction:cancelAction];
        
        return alert;
    } else {
        let alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:style];
        let reportAction = [UIAlertAction actionWithTitle:LIFELocalizedString(LIFEStringKey_ReportABug) style:UIAlertActionStyleDefault handler:reportHandler];
        [alert addAction:reportAction];
        
        if (disableHandler != nil) {
            let disableAction = [UIAlertAction actionWithTitle:disableActionTitle style:UIAlertActionStyleDestructive handler:disableHandler];
            [alert addAction:disableAction];
        }
        
        let cancelAction = [UIAlertAction actionWithTitle:LIFELocalizedString(LIFEStringKey_Cancel) style:UIAlertActionStyleCancel handler:cancelHandler];
        [alert addAction:cancelAction];
        
        return alert;
    }
}

- (void)_notifyBuglifeInvoked
{
    [[NSNotificationCenter defaultCenter] postNotificationName:LIFENotificationLoggerBuglifeInvoked object:nil];
}

- (NSString *)_alertMessageForInvocation:(LIFEInvocationOptions)invocation
{
    NSString *message;

    if (invocation == LIFEInvocationOptionsScreenRecordingFinished) {
        return LIFELocalizedString(LIFEStringKey_ReportABugWithScreenRecording);
    } else if ([self.delegate respondsToSelector:@selector(buglife:titleForPromptWithInvocation:)]) {
        message = [self.delegate buglife:self titleForPromptWithInvocation:invocation];
    } else {
        message = [[self class] _randomAlertMessageForInvocation:invocation];
    }
    
    return message;
}

+ (NSString *)_randomAlertMessageForInvocation:(LIFEInvocationOptions)invocation
{
    NSMutableArray<NSString *> *messages = [NSMutableArray array];
    
    NSString *appName = appName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
    
    if (appName) {
        [messages addObject:[NSString stringWithFormat:LIFELocalizedString(LIFEStringKey_HelpUsMakeXYZBetter), appName]];
    } else {
        [messages addObject:LIFELocalizedString(LIFEStringKey_HelpUsMakeThisAppBetter)];
    }
    
    // Most messages only show up if the current language is English
    if ([[LIFELocalizedStringProvider sharedInstance] isEnglish]) {
        [messages addObjectsFromArray:@[@"Feed me bugs!"]];
        
        if (invocation == LIFEInvocationOptionsShake) {
            [messages addObject:@"I'm guessing you're trying to file a bug, and not out going for a jog..."];
            
            NSString *deviceModel = [UIDevice currentDevice].model;
            NSString *deviceModelForMessage = @"device";
            
            if ([deviceModel rangeOfString:@"iPad"].location != NSNotFound) {
                deviceModelForMessage = @"iPad";
            } else if ([deviceModel rangeOfString:@"iPhone"].location != NSNotFound) {
                deviceModelForMessage = @"iPhone";
            }
            
            [messages addObject:[NSString stringWithFormat:@"Looks like you're shaking your %@ in frustration...? :)", deviceModelForMessage]];
        } else if (invocation == LIFEInvocationOptionsScreenshot) {
            [messages addObject:@"Find something interesting?"];
            [messages addObject:@"Great shot! 📷"];
        }
    }
    
    NSString *randomMessage = [messages objectAtIndex:arc4random() % messages.count];
    return randomMessage;
}

- (void)_temporarilyDisableInvocation:(LIFEInvocationOptions)invocation
{
    if (invocation == LIFEInvocationOptionsScreenRecordingFinished) {
        self.screenRecordingInvocationEnabled = NO;
    } else {
        self.invocationOptions = (self.invocationOptions & ~invocation);
    }
}

@end

void LIFELoadCategoryFor_BuglifeUIStuff() {
    [Buglife life_loadCategory_BuglifeUIStuff];
}
