/**
 * ti.accountkit
 *
 * Created by Hans Knoechel
 * Copyright (c) 2016 Hans Knoechel. All rights reserved.
 */

#import "TiAccountkitModule.h"
#import "TiBase.h"
#import "TiHost.h"
#import "TiUtils.h"
#import "TiApp.h"

@implementation TiAccountkitModule

#pragma mark Internal

- (id)moduleGUID
{
	return @"43908d52-f013-4f83-917e-b3e8f89e5df5";
}

- (NSString*)moduleId
{
	return @"ti.accountkit";
}

#pragma mark Lifecycle

- (void)startup
{
	[super startup];
	NSLog(@"[INFO] %@ loaded",self);
}

#pragma mark Cleanup

- (void)dealloc
{
    RELEASE_TO_NIL(accountKit);
	[super dealloc];
}

#pragma mark Public APIs

- (void)initialize:(id)args
{
    ENSURE_ARG_COUNT(args, 1);
    ENSURE_TYPE([args objectAtIndex:0], NSNumber);
    
    AKFResponseType responseType = [TiUtils intValue:[args objectAtIndex:0] def:AKFResponseTypeAccessToken];
    
    if (accountKit == nil) {
        accountKit = [[AKFAccountKit alloc] initWithResponseType:responseType];
    }
}

- (void)loginWithPhone:(id)args
{
    ENSURE_UI_THREAD(loginWithPhone, args);

    id phone = [args objectAtIndex:0];
    ENSURE_TYPE_OR_NIL(phone, NSString);
    
    NSLocale *currentLocale = [NSLocale currentLocale];
    NSString *countryCode = [currentLocale objectForKey:NSLocaleCountryCode];
    
    AKFPhoneNumber *phoneNumber = [[AKFPhoneNumber alloc] initWithCountryCode:@"CA" phoneNumber:[TiUtils stringValue:phone]];
    NSString *inputState = [[NSUUID UUID] UUIDString];
    UIViewController<AKFViewController> *viewController = [accountKit viewControllerForPhoneLoginWithPhoneNumber:nil state:inputState];
    [viewController setEnableSendToFacebook:YES];

    // Country Codes
    viewController.whitelistedCountryCodes = @[@"CA", @"US", @"VN"];
    viewController.defaultCountryCode = @"CA";
    
    [self _prepareLoginViewController:viewController]; // apply theme
    [viewController setDelegate:self];
    [[[TiApp app] controller] presentViewController:viewController animated:YES completion:nil];
}

- (void)loginWithEmail:(id)args
{
    ENSURE_UI_THREAD(loginWithEmail, args);
    
    id email = [args objectAtIndex:0];
    ENSURE_TYPE_OR_NIL(email, NSString);

    NSString *prefilledEmail = [TiUtils stringValue:email];
    NSString *inputState = [[NSUUID UUID] UUIDString];
    UIViewController<AKFViewController> *viewController = [accountKit viewControllerForEmailLoginWithEmail:prefilledEmail state:inputState];
    
    [self _prepareLoginViewController:viewController]; // apply theme
    [viewController setDelegate:self];
    [[[TiApp app] controller] presentViewController:viewController animated:YES completion:nil];
}

- (void)_prepareLoginViewController:(UIViewController<AKFViewController> *)loginViewController
{
    AKFTheme *theme = [AKFTheme outlineThemeWithPrimaryColor:[self _colorWithHex:0xff323a45]
                                            primaryTextColor:[UIColor whiteColor]
                                          secondaryTextColor:[self _colorWithHex:0xff151515]
                                              statusBarStyle:UIStatusBarStyleLightContent];
    theme.backgroundColor = [self _colorWithHex:0xfff7f7f7];
    theme.buttonBackgroundColor = [self _colorWithHex:0xffff3366];
    theme.buttonBorderColor = [self _colorWithHex:0xffff3366];
    theme.inputBorderColor = [self _colorWithHex:0x323A4545];
    
    loginViewController.theme = theme;
    
    // Title
    theme.headerTextType = AKFHeaderTextTypeAppName; // title bar text says `APP_NAME`
    // theme.headerTextType = AKFHeaderTextTypeLogin; // title bar text says `Log into APP_NAME`
}

- (UIColor *)_colorWithHex:(NSUInteger)hex
{
    CGFloat alpha = ((CGFloat)((hex & 0xff000000) >> 24)) / 255.0;
    CGFloat red = ((CGFloat)((hex & 0x00ff0000) >> 16)) / 255.0;
    CGFloat green = ((CGFloat)((hex & 0x0000ff00) >> 8)) / 255.0;
    CGFloat blue = ((CGFloat)((hex & 0x000000ff) >> 0)) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

- (void)logout:(id)unused
{
   [accountKit logOut];
}

- (void)requestAccount:(id)args
{
    ENSURE_TYPE([args objectAtIndex:0], KrollCallback);
    KrollCallback *callback = [args objectAtIndex:0];
    
    TiThreadPerformOnMainThread(^{
        [accountKit requestAccount:^(id<AKFAccount> account, NSError *error) {

            NSMutableDictionary * event = [[NSMutableDictionary alloc] initWithDictionary:@{@"success":[NSNumber numberWithBool:!error]}];

            if (error != nil) {
                [event setValue:[[[[error userInfo] valueForKey:@"NSUnderlyingError"] userInfo] valueForKey:@"com.facebook.accountkit:ErrorDeveloperMessageKey"] forKey:@"message"];
            } else {
                if ([account accountID] != nil) {
                    [event setValue:[account accountID] forKey:@"accountID"];
                }
                
                if ([account emailAddress] != nil) {
                    [event setValue:[account emailAddress] forKey:@"email"];
                }
                
                if ([account phoneNumber] != nil) {
                    [event setValue:[account phoneNumber] forKey:@"phone"];
                }
            }
            
            KrollEvent * invocationEvent = [[KrollEvent alloc] initWithCallback:callback eventObject:event thisObject:self];
            [[callback context] enqueue:invocationEvent];
            [invocationEvent release];
            [event release];
        }];
    }, NO);
}

- (void)cancelLogin:(id)unused
{
    [accountKit cancelLogin];
}

- (void)currentAccessToken
{
    return [self dictionaryFromAccessToken:[accountKit currentAccessToken]];
}

- (NSString*)graphVersion
{
    return [AKFAccountKit graphVersionString];
}

- (NSString*)version
{
    return [AKFAccountKit versionString];
}

#pragma mark Delegates

- (void)viewController:(UIViewController<AKFViewController> *)viewController didCompleteLoginWithAccessToken:(id<AKFAccessToken>)accessToken state:(NSString *)state
{
    [self fireEvent:@"login" withObject:@{
        @"accessToken": [self dictionaryFromAccessToken:accessToken],
        @"state":state,
        @"success": @YES
    }];
}

- (void)viewControllerDidCancel:(UIViewController<AKFViewController> *)viewController
{
    [self fireEvent:@"login" withObject:@{
        @"success": @NO,
        @"cancel": @YES
    }];
}

- (void)viewController:(UIViewController<AKFViewController> *)viewController didFailWithError:(NSError *)error
{
    [self fireEvent:@"login" withObject:@{
        @"success": @NO,
        @"error":[error localizedDescription]
    }];
}

- (void)viewController:(UIViewController<AKFViewController> *)viewController didCompleteLoginWithAuthorizationCode:(NSString *)code state:(NSString *)state
{
    [self fireEvent:@"login" withObject:@{
        @"success": @YES,
        @"code":code,
        @"state":state
    }];
}

#pragma mark Utilities

- (NSDictionary*)dictionaryFromAccessToken:(id<AKFAccessToken>)accessToken
{
    return @{
         @"accountID": [accessToken accountID],
         @"applicationID": [accessToken applicationID],
         @"lastRefresh": [accessToken lastRefresh],
         @"tokenRefreshInterval": NUMDOUBLE([accessToken tokenRefreshInterval]),
         @"tokenString": [accessToken tokenString]
    };
}

#pragma mark Constants

MAKE_SYSTEM_PROP(RESPONSE_TYPE_AUTHORIZATION_CODE, AKFResponseTypeAuthorizationCode);
MAKE_SYSTEM_PROP(RESPONSE_TYPE_ACCESS_TOKEN, AKFResponseTypeAccessToken);

@end
