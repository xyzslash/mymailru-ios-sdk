// MMRSession.m
//
// Copyright (c) 2014 Anton Grachev
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#import "MMRSession.h"
#import <UIKit/UIKit.h>

#import "MyMailRu.h"
#import "MMRTokenCache.h"
#import "MMRUtils.h"
#import "MMRErrors.h"
#import "MMRInAppLoginManager.h"

static NSString* const MMROAuthAuthorizeURL = @"https://connect.mail.ru/oauth/authorize";
static NSString* const MMRRedirectURL = @"http://connect.mail.ru/oauth/success.html";
static NSString* const MMROAuthTokenURL = @"https://appsmail.ru/oauth/token";

@interface MMRSession () <UIWebViewDelegate, MMRInAppLoginDelegate>
@property (readwrite, copy, nonatomic) NSString *accessToken;
@property (readwrite, copy, nonatomic) NSString *refreshToken;
@property (readwrite, copy, nonatomic) NSDate *expirationDate;
@property (readwrite, copy, nonatomic) NSString *userId;
@property (readwrite, copy, nonatomic) NSArray *permissions;
@property (strong, nonatomic) UIViewController *loginVC;
@property (copy, nonatomic) MMRSessionOpenHandler openHandler;
@property (strong, nonatomic) MMRInAppLoginManager *loginManager;
@end

@implementation MMRSession

static MMRSession *mmr_currentSession = nil;
static NSString *mmr_redirectURI = nil;

#pragma mark - Public methods

- (instancetype)init {
    self = [super init];
    if (self) {
        _accessToken = @"";
        _refreshToken = @"";
        _expirationDate = [NSDate dateWithTimeIntervalSince1970:0];
        _userId = @"";
        _permissions = @[];
    }
    return  self;
}

+ (void)openSessionWithPermissions:(NSArray *)permissions loginBehavior:(MMRSessionLoginBehavior)behavior completionsHandler:(MMRSessionOpenHandler)handler {
    mmr_currentSession = [[MMRSession alloc] init];
    
    NSDictionary *cachedToken = [MMRTokenCache getTokenInformation];
    if (cachedToken) {
        NSArray *cachedPermissions = [cachedToken valueForKey:kMMRPermissions];
        if ([cachedPermissions isEqualToArray:permissions]) {
            mmr_currentSession.permissions = cachedPermissions;
            mmr_currentSession.accessToken = cachedToken[kMMRAccessToken];
            mmr_currentSession.refreshToken = cachedToken[kMMRRefreshToken];
            mmr_currentSession.expirationDate = cachedToken[kMMRExpirationDate];
            mmr_currentSession.userId = cachedToken[kMMRUserId];
        }
    }
    
    if (mmr_currentSession.isValid) {
        if (handler) handler(mmr_currentSession, nil);
    } else if (behavior != MMRSessionLoginWithCachedToken) {
        if (mmr_redirectURI == nil) [MMRSession setRedirectURI:MMRRedirectURL];

        mmr_currentSession.openHandler = handler;
        mmr_currentSession.permissions = permissions;
        
        NSMutableDictionary* params = [@{@"client_id" : [MyMailRu appId],
                                         @"response_type" : @"token",
                                         @"display" : @"mobile",
                                         @"redirect_uri" :  [MMRSession redirectURI]} mutableCopy];
        
        if (permissions) {
            NSString *scope = [permissions componentsJoinedByString:@" "];
            params[@"scope"] = scope;
        }
        
        
        MMRInAppLoginManager *loginManager = [[MMRInAppLoginManager alloc] init];
        loginManager.delegate = mmr_currentSession;
        mmr_currentSession.loginManager = loginManager;
        
        if (behavior == MMRSessionLoginInAppLoginAndPasswordView) {
            [mmr_currentSession.loginManager showLoginAndPasswordView];
        } else  {
            NSString *appURL = [NSString stringWithFormat:@"%@?%@", MMROAuthAuthorizeURL, [MMRUtils URLEncodedStringFromParams:params]];
            NSURL *url = [NSURL URLWithString:appURL];
            
            if (behavior == MMRSessionLoginInAppWebView) [loginManager showLoginWebViewWithURL:url];
            else if (behavior == MMRSessionLoginInSafari) [[UIApplication sharedApplication] openURL:url];
        }
    }
}

+ (void)openSessionForUsername:(NSString *)username password:(NSString *)password permissions:(NSArray *)permissions completionsHandler:(MMRSessionOpenHandler)handler {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    request.HTTPMethod = @"POST";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"grant_type"] = @"password";
    params[@"client_id"] = [MyMailRu appId];
    params[@"client_secret"] = [MyMailRu appPrivateKey];
    params[@"username"] = username ?: @"";
    params[@"password"] = password ?: @"";
    if (permissions) {
        NSString *scope = [permissions componentsJoinedByString:@" "];
        params[@"scope"] = scope;
    }
    
    request.URL = [NSURL URLWithString:MMROAuthTokenURL];
    request.HTTPBody = [[MMRUtils URLEncodedStringFromParams:params] dataUsingEncoding:NSUTF8StringEncoding];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               if (connectionError) {
                                   if (handler) handler(nil, connectionError);
                                   return;
                               }
                               
                               NSError *jsonParsingError = nil;
                               id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonParsingError];
                               if (jsonParsingError) {
                                   if (handler) handler(nil, jsonParsingError);
                                   return;
                               }
                               
                               NSError *error = [MMRErrors errorFromJSON:result];
                               if (error) {
                                   if (handler) handler(nil, error);
                                   return;
                               }
                               
                               if (!mmr_currentSession) mmr_currentSession = [[MMRSession alloc] init];
                               [mmr_currentSession updateTokenInformationWithParams:result];
                               if (handler) handler(mmr_currentSession, nil);
                           }];
}

+ (MMRSession *)currentSession {
    return mmr_currentSession;
}

+ (void)setRedirectURI:(NSString *)redirectURI {
    mmr_redirectURI = [redirectURI copy];
}

+ (NSString *)redirectURI {
    return mmr_redirectURI;
}

- (BOOL)isValid {
    return (self.userId && [self.userId length] > 0) && (self.accessToken && [self.accessToken length] > 0) && ([self.expirationDate timeIntervalSince1970] > [[NSDate date] timeIntervalSince1970]);
}

- (void)refreshTokenWithCompletionHandler:(MMRSessionRefreshTokenHandler)handler {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    request.HTTPMethod = @"POST";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"grant_type"] = @"refresh_token";
    params[@"client_id"] = [MyMailRu appId];
    params[@"client_secret"] = [MyMailRu appPrivateKey];
    params[@"refresh_token"] = self.refreshToken;
    NSString *signature = [MMRUtils signatureForParams:params
                                       withAccessToken:self.accessToken
                                                userID:self.userId
                                         andPrivateKey:[MyMailRu appPrivateKey]];
    params[@"sig"] = signature;
    
    request.URL = [NSURL URLWithString:MMROAuthTokenURL];
    request.HTTPBody = [[MMRUtils URLEncodedStringFromParams:params] dataUsingEncoding:NSUTF8StringEncoding];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               if (connectionError) {
                                   if (handler) handler(connectionError);
                                   return;
                               }
                               
                               NSError *jsonParsingError = nil;
                               id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonParsingError];
                               if (jsonParsingError) {
                                   if (handler) handler(jsonParsingError);
                                   return;
                               }
                               
                               NSError *error = [MMRErrors errorFromJSON:result];
                               if (error) {
                                   if (handler) handler(error);
                                   return;
                               }
                               
                               [self updateTokenInformationWithParams:result];
                               if (handler) handler(nil);
                           }];
}

- (void)close {
    self.userId = @"";
    self.accessToken = @"";
    self.refreshToken = @"";
    self.expirationDate = [NSDate dateWithTimeIntervalSince1970:0];
    self.permissions = @[];
}

- (void)closeAndClearTokenInformation {
    [self close];
    [MMRTokenCache clearTokenInformation];
}

- (BOOL)handleOpenURL:(NSURL *)url {
    if (![[url absoluteString] hasPrefix:[NSString stringWithFormat:@"mm%@", [MyMailRu appId]]]) {
		return NO;
	}
    
    NSMutableDictionary * newAccessData = [NSMutableDictionary dictionary];
	for(NSString * param in [url.query componentsSeparatedByString:@"&"]) {
		NSArray * elements = [param componentsSeparatedByString:@"="];
		if (elements.count != 2) continue;
		[newAccessData setObject:[elements objectAtIndex:1] forKey:[elements objectAtIndex:0]];
	}
    
	[self updateTokenInformationWithParams:newAccessData];
    
    if (self.isValid) {
        if (self.openHandler) self.openHandler(self, nil);
        self.openHandler = nil;
    } else {
        self.permissions = @[];
        NSError *error = [MMRErrors errorForCode:MMRErrorUserAuthorizationFailed];
        self.openHandler(nil, error);
    }
          
	return YES;
}

#pragma mark - Private methods

- (void)updateTokenInformationWithParams:(NSDictionary *)params {
    self.refreshToken = params[@"refresh_token"];
    self.accessToken = params[@"access_token"];
    self.userId = params[@"x_mailru_vid"];
    NSString *expiresIn = params[@"expires_in"];
    self.expirationDate = [NSDate dateWithTimeIntervalSinceNow:[expiresIn doubleValue]];
    [self cacheTokenInformation];
}

-(void)cacheTokenInformation {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[kMMRAccessToken] = self.accessToken ?: @"";
    info[kMMRRefreshToken] = self.refreshToken ?: @"";
    info[kMMRExpirationDate] = self.expirationDate ?: @"";
    info[kMMRPermissions] = self.permissions ?: @"";
    info[kMMRUserId] = self.userId ?: @"";
	[MMRTokenCache cacheTokenInformation:info];
}

#pragma mark - MMRInAppLoginDelegate

- (void)userAuthorizedWithSessionParams:(NSDictionary *)params error:(NSError *)error {
    if (!error) {
        [self updateTokenInformationWithParams:params];
    }
    if (self.openHandler) self.openHandler(self, error);
    self.openHandler = nil;
}

- (void)userDidEnterLogin:(NSString *)login andPassword:(NSString *)password {
    [MMRSession openSessionForUsername:login
                              password:password
                           permissions:self.permissions
                    completionsHandler:^(MMRSession *session, NSError *error) {
                        if (self.openHandler) self.openHandler(session, error);
                        self.openHandler = nil;
                    }];
}

- (void)userDidCloseLoginView {
    if (self.openHandler) {
        NSError *error = [MMRErrors errorForCode:MMRErrorUserCancelOperation];
        self.openHandler(nil, error);
        self.openHandler = nil;
    }
}

@end
