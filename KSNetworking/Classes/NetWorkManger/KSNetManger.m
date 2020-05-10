//
//  KSNetManger.m
//  KSNetWork
//
//  Created by KSummer on 2019/12/3.
//  Copyright © 2019 KSummer. All rights reserved.
//

#import "KSNetManger.h"
#import "KSNetLocalCache.h"
#import "KSNetRequestInfo.h"
#import "AFNetworking.h"

extern NSString * KSConvertMD5FromParameter(NSString *url, NSString *method, NSDictionary *params);

static NSString *KSNetProcessingQueue = @"com.ksummer.net";

@interface KSNetManger ()

@property (nonatomic, strong) KSNetLocalCache *cache;
@property (nonatomic, strong) NSMutableArray *batchGroups;// 批处理
@property (nonatomic, strong) dispatch_queue_t KSNetQueue;

@end

@implementation KSNetManger

#pragma mark - init

- (instancetype)init
{
    self = [super init];
    if (self) {
        _KSNetQueue = dispatch_queue_create([KSNetProcessingQueue UTF8String], DISPATCH_QUEUE_CONCURRENT);
        _cache = [KSNetLocalCache shareInstance];
        _batchGroups = [NSMutableArray new];
    }

    return self;
}

+ (instancetype)shareInstance {
    static KSNetManger *manger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manger = [[KSNetManger alloc] init];
    });

    return manger;
}

#pragma mark - public method

- (void)ksPostCacheWithUrl:(NSString *)urlString
                parameters:(NSDictionary *_Nullable)parameters
         completionHandler:(KSRequestCompletionHandler)completionHandler {
    [self ksPostWithURLString:urlString parameters:parameters ignoreCache:NO cacheDuration:NetCacheDuration completionHandler:completionHandler];
}

- (void)ksGetCacheWithUrl:(NSString *)urlString
               parameters:(NSDictionary *_Nullable)parameters
        completionHandler:(KSRequestCompletionHandler)completionHandler {
    [self ksGetWithURLString:urlString parameters:parameters ignoreCache:NO cacheDuration:NetCacheDuration completionHandler:completionHandler];
}

- (void)ksPostNoCacheWithUrl:(NSString *)urlString
                  parameters:(NSDictionary *_Nullable)parameters
           completionHandler:(KSRequestCompletionHandler)completionHandler {
    [self ksPostWithURLString:urlString parameters:parameters ignoreCache:YES cacheDuration:0 completionHandler:completionHandler];
}

- (void)ksGetNoCacheWithUrl:(NSString *)urlString
                 parameters:(NSDictionary *_Nullable)parameters
          completionHandler:(KSRequestCompletionHandler)completionHandler {
    [self ksGetWithURLString:urlString parameters:parameters ignoreCache:YES cacheDuration:0 completionHandler:completionHandler];
}

- (void)ksPostWithURLString:(NSString *)URLString
                 parameters:(NSDictionary *_Nullable)parameters
                ignoreCache:(BOOL)ignoreCache
              cacheDuration:(NSTimeInterval)cacheDuration
          completionHandler:(KSRequestCompletionHandler)completionHandler {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_KSNetQueue, ^{
        [weakSelf taskWithMethod:@"POST" urlString:URLString params:parameters ignoreCache:ignoreCache cacheDuration:cacheDuration completionHandler:completionHandler];
    });
}

- (void)ksGetWithURLString:(NSString *)URLString
                parameters:(NSDictionary *)parameters
               ignoreCache:(BOOL)ignoreCache
             cacheDuration:(NSTimeInterval)cacheDuration
         completionHandler:(KSRequestCompletionHandler)completionHandler {
    __weak typeof(self) weakSelf = self;

    dispatch_async(_KSNetQueue, ^{
        [weakSelf taskWithMethod:@"GET" urlString:URLString params:parameters ignoreCache:ignoreCache cacheDuration:cacheDuration completionHandler:completionHandler];
    });
}

#pragma mark - total method
- (void)taskWithMethod:(NSString *)method
             urlString:(NSString *)urlString
                params:(NSDictionary *)params
           ignoreCache:(BOOL)ignoreCache
         cacheDuration:(NSTimeInterval)cacheDuration
     completionHandler:(KSRequestCompletionHandler)completionHandler {
    NSString *fileKeyFromUrl = KSConvertMD5FromParameter(urlString, method, params);

    __weak typeof(self) weakSelf = self;

    // 如果不忽略 且缓存已失效才缓存
    if (!ignoreCache && [self.cache checkIfShouldUserCacheWithCacheDuration:cacheDuration cacheKey:fileKeyFromUrl]) {
        NSMutableDictionary *localCache = [NSMutableDictionary dictionary];
        NSDictionary *cacheDic = [self.cache searchCacheWithUrl:fileKeyFromUrl];
        [localCache setDictionary:cacheDic];

        // 如果有缓存
        if (cacheDic) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.exceptionBlock) {
                    weakSelf.exceptionBlock(nil, localCache);
                }
                completionHandler(nil, YES, localCache);
            });
            return;
        }
    }

    // 新增一个block处理
    KSRequestCompletionHandler newCompletionBlock = ^(NSError *error, BOOL isCache, NSDictionary *result) {
        result = [NSMutableDictionary dictionaryWithDictionary:result];
        if (cacheDuration > 0) {
            if (result) {
                if (weakSelf.cacheConditionBlock) {
                    if (weakSelf.cacheConditionBlock(result)) {
                        [weakSelf.cache saveCacheData:result forKey:fileKeyFromUrl];
                    }
                } else {
                    [weakSelf.cache saveCacheData:result forKey:fileKeyFromUrl];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.exceptionBlock) {
                weakSelf.exceptionBlock(error, (NSMutableDictionary *)result);
            }

            completionHandler(error, NO, result);
        });
    };

    // 否则则进行网络下载
    NSURLSessionTask *task = nil;
    if ([method isEqualToString:@"GET"]) {
        // GET

        task = [self.afHttpManager GET:urlString parameters:params progress:^(NSProgress *_Nonnull downloadProgress) {
        } success:^(NSURLSessionDataTask *_Nonnull task, id _Nullable responseObject) {
            newCompletionBlock(nil, NO, responseObject);
        } failure:^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull error) {
            newCompletionBlock(error, NO, nil);
        }];
    } else {
        // POST
        task = [self.afHttpManager POST:urlString parameters:params progress:^(NSProgress *_Nonnull uploadProgress) {
        } success:^(NSURLSessionDataTask *_Nonnull task, id _Nullable responseObject) {
            newCompletionBlock(nil, NO, responseObject);
        } failure:^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull error) {
            newCompletionBlock(error, NO, nil);
        }];
    }

    [task resume];
}

- (AFHTTPSessionManager *)afHttpManager {
    AFHTTPSessionManager *afManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    afManager.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript", @"text/html", nil];
    return afManager;
}

#pragma mark - 多请求

- (KSNetRequestInfo *)ksNetRequestWithURLStr:(NSString *)URLString
                                      method:(NSString *)method
                                  parameters:(NSDictionary *)parameters
                                 ignoreCache:(BOOL)ignoreCache
                               cacheDuration:(NSTimeInterval)cacheDuration
                           completionHandler:(KSRequestCompletionHandler)completionHandler {
    KSNetRequestInfo *netRequestInfo = [KSNetRequestInfo new];
    netRequestInfo.urlStr = URLString;
    netRequestInfo.method = method;
    netRequestInfo.params = parameters;
    netRequestInfo.ignoreCache = ignoreCache;
    netRequestInfo.cacheDuration = cacheDuration;
    netRequestInfo.completionHandlerBlock = completionHandler;
    return netRequestInfo;
}

- (void)ksBatchOfRequestOperations:(NSArray<KSNetRequestInfo *> *)tasks
                     progressBlock:(void (^)(NSUInteger numberOfFinishedTasks, NSUInteger totalNumberOfTasks))progressBlock
                   completionBlock:(KSNetSuccessBatchBlock)completionBlock {
    __weak typeof(self) weakSelf = self;

    dispatch_async(_KSNetQueue, ^{
        __block dispatch_group_t group = dispatch_group_create();
        [weakSelf.batchGroups addObject:group];

        __block NSInteger finishedTasksCount = 0;
        __block NSInteger totalNumberOfTasks = tasks.count;

        [tasks enumerateObjectsUsingBlock:^(KSNetRequestInfo *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
            if (obj) {
                dispatch_group_enter(group);

                KSRequestCompletionHandler newCompletionBlock = ^(NSError *error,  BOOL isCache, NSDictionary *result) {
                    progressBlock(finishedTasksCount, totalNumberOfTasks);
                    if (obj.completionHandlerBlock) {
                        obj.completionHandlerBlock(error, isCache, result);
                    }
                    // 网络任务结束后dispatch_group_enter
                    dispatch_group_leave(group);
                };

                if ([obj.method isEqualToString:@"POST"]) {
                    [[KSNetManger shareInstance]ksPostWithURLString:obj.urlStr parameters:obj.params ignoreCache:obj.ignoreCache cacheDuration:obj.cacheDuration completionHandler:newCompletionBlock];
                } else {
                    [[KSNetManger shareInstance] ksGetWithURLString:obj.urlStr parameters:obj.params ignoreCache:obj.ignoreCache cacheDuration:obj.cacheDuration completionHandler:newCompletionBlock];
                }
            }
        }];

        // 监听
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [weakSelf.batchGroups removeObject:group];
            if (completionBlock) {
                completionBlock(tasks);
            }
        });
    });
}

@end
