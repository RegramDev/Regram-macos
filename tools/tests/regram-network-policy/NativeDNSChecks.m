#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <MtProtoKit/MTRGDNSDiagnostics.h>
#import <MtProtoKit/MTQueue.h>
#import "MTRGDoHResolver.h"

static NSMutableArray<NSURL *> *requests;
static BOOL failBuiltinPrimary;

@interface FixtureDNSProtocol : NSURLProtocol
@end
@implementation FixtureDNSProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    @synchronized (requests) { [requests addObject:self.request.URL]; }
    if ([self.request.URL.host isEqualToString:@"failed-resolver.invalid"] || (failBuiltinPrimary && [self.request.URL.host isEqualToString:@"dns.google"])) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil]];
        return;
    }
    NSCAssert(([@[@"dns.google", @"cloudflare-dns.com", @"custom-resolver.invalid"] containsObject:self.request.URL.host]), @"Unexpected DNS HTTP provider");
    NSURLComponents *url = [NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:NO];
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in url.queryItems) parameters[item.name] = item.value;
    NSString *name = parameters[@"name"];
    NSNumber *type = @([parameters[@"type"] intValue]);
    NSCAssert((name != nil && [@[@1, @28, @16] containsObject:type]), @"Expected JSON A, AAAA or TXT query");
    NSString *address = type.intValue == 28 ? @"2001:db8::7" : type.intValue == 16 ? @"\"signedpayload\"" : @"192.0.2.7";
    NSDictionary *answer = @{@"Status": @0, @"Question": @[@{@"name": name, @"type": type}], @"Answer": @[@{@"name": name, @"type": type, @"TTL": @30, @"data": address}]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:answer options:0 error:nil];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/dns-json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface NSURLSessionConfiguration (FixtureDNS)
+ (NSURLSessionConfiguration *)rgFixtureConfiguration;
@end
@implementation NSURLSessionConfiguration (FixtureDNS)
+ (NSURLSessionConfiguration *)rgFixtureConfiguration {
    NSURLSessionConfiguration *configuration = [self rgFixtureConfiguration];
    configuration.protocolClasses = @[FixtureDNSProtocol.class];
    return configuration;
}
@end

static id resolve(MTSignal *signal, BOOL expectedFailure) {
    __block id result = nil;
    __block BOOL completed = NO;
    __block BOOL failed = NO;
    id<MTDisposable> disposable = [[signal deliverOn:MTQueue.mainQueue] startWithNext:^(id value) { result = value; } error:^(id error) { failed = YES; completed = YES; } completed:^{ completed = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
    while (!completed && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    [disposable dispose];
    NSCAssert(completed && failed == expectedFailure, @"Unexpected resolver completion or timeout");
    return result;
}

static void resetRequests(void) { @synchronized (requests) { [requests removeAllObjects]; } }
static NSArray<NSURL *> *recordedRequests(void) { @synchronized (requests) { return requests.copy; } }

int main(void) {
    @autoreleasepool {
        requests = [NSMutableArray array];
        method_exchangeImplementations(class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration)), class_getClassMethod(NSURLSessionConfiguration.class, @selector(rgFixtureConfiguration)));
        NSArray *v4 = @[@"192.0.2.7"], *v6 = @[@"2001:db8::7"];
        for (NSString *endpoint in @[@"", @"https://custom-resolver.invalid/dns-query"]) {
            for (NSNumber *policy in @[@0, @1, @2, @4, @6]) {
                resetRequests();
                NSString *host = [NSString stringWithFormat:@"policy-%ld-%ld.example", (long)endpoint.length, (long)policy.integerValue];
                NSArray *addresses = resolve([MTRGDNSDiagnostics resolveHostname:host dohEndpoint:endpoint.length ? endpoint : nil policy:policy.integerValue useSystemDNS:NO], NO);
                NSArray *expected = policy.intValue == 1 ? v4 : policy.intValue == 2 ? v6 : policy.intValue == 6 ? [v6 arrayByAddingObjectsFromArray:v4] : [v4 arrayByAddingObjectsFromArray:v6];
                NSCAssert([addresses isEqual:expected], @"Preferred families retain fallback; only modes filter it");
                NSArray *seen = recordedRequests();
                NSCAssert(seen.count == ((policy.intValue == 1 || policy.intValue == 2) ? 1 : 2), @"Only modes must not request the other address family");
                for (NSURL *request in seen) NSCAssert((endpoint.length ? [request.host isEqualToString:@"custom-resolver.invalid"] : [@[@"dns.google", @"cloudflare-dns.com"] containsObject:request.host]), @"DNS mode must select the correct resolver");
            }
        }
        resetRequests();
        failBuiltinPrimary = YES;
        NSDictionary *backup = resolve([MTRGDNSDiagnostics queryHostname:@"builtin-backup.example" dohEndpoint:nil family:4 useSystemDNS:NO], NO);
        failBuiltinPrimary = NO;
        NSCAssert([backup[@"addresses"] isEqual:v4], @"Built-in DNS must survive failure of its primary provider");
        NSArray *providers = [recordedRequests() valueForKey:@"host"];
        NSCAssert([providers containsObject:@"dns.google"] && [providers containsObject:@"cloudflare-dns.com"], @"Built-in fallback must use the secondary HTTPS resolver");
        resetRequests();
        resolve([MTRGDNSDiagnostics resolveHostname:@"localhost" dohEndpoint:@"https://failed-resolver.invalid/dns-query" policy:4 useSystemDNS:NO], YES);
        NSCAssert(recordedRequests().count == 2, @"Custom DNS failure is bounded to its two family queries");
        for (NSURL *request in recordedRequests()) NSCAssert([request.host isEqualToString:@"failed-resolver.invalid"], @"Custom failure must never use a built-in resolver");
        resetRequests();
        NSArray *local = resolve([MTRGDNSDiagnostics resolveHostname:@"localhost" dohEndpoint:nil policy:1 useSystemDNS:YES], NO);
        NSCAssert(local.count > 0 && recordedRequests().count == 0, @"System DNS must use the native resolver");
        for (NSString *address in local) NSCAssert(![address containsString:@":"], @"System resolver obeys IPv4-only");
        resolve([MTRGDNSDiagnostics resolveHostname:@"192.0.2.7" dohEndpoint:nil policy:2 useSystemDNS:NO], YES);
        NSCAssert(recordedRequests().count == 0, @"An incompatible numeric literal must fail before DNS");
        resetRequests();
        NSDictionary *txt = resolve([MTRGDoHResolver queryHostname:@"apv3.stel.com" type:16 endpoint:@"https://custom-resolver.invalid/dns-query" useCache:NO], NO);
        NSCAssert([txt[@"records"] isEqual:@[@"\"signedpayload\""]], @"Custom resolver serves backup-discovery TXT queries");
        NSCAssert(recordedRequests().count == 1, @"Custom TXT lookup must not call built-in DNS");
        puts("Native DNS checks passed: built-in/system/custom routing, all IP modes and fallback order, custom failure without DNS downgrade, numeric family rejection, custom backup TXT path; all HTTP requests used an in-process fixture");
    }
    return 0;
}
