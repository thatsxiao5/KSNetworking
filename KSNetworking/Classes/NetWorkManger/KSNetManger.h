//
//  KSNetManger.h
//  KSNetWork
//
//  Created by KSummer on 2019/12/3.
//  Copyright © 2019 KSummer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KSNetRequestInfo.h"

NS_ASSUME_NONNULL_BEGIN

#define NetCacheDuration 60 * 5

@interface KSNetManger : NSObject

/** 网络状态*/
@property (nonatomic, copy) NSString *netState;

/** 外部添加异常处理,根据服务器返回的数据，统一处理，如处理登录实效），默认不做处理*/
@property (nonatomic, copy) KSRequestCompletionAddExcepetionHanle exceptionBlock;

/** 返回NO， cache不保存*/
@property (nonatomic, copy) KSRequestComletionAddCacheConditionBlock cacheConditionBlock;

+ (instancetype)shareInstance;

// POST 缓存
- (void)ksPostCacheWithUrl:(NSString *)urlString
                parameters:(NSDictionary *_Nullable)parameters
         completionHandler:(KSRequestCompletionHandler)completionHandler;
// GET 缓存
- (void)ksGetCacheWithUrl:(NSString *)urlString
               parameters:(NSDictionary *_Nullable)parameters
        completionHandler:(KSRequestCompletionHandler)completionHandler;
// POST 不缓存
- (void)ksPostNoCacheWithUrl:(NSString *)urlString
                  parameters:(NSDictionary *_Nullable)parameters
           completionHandler:(KSRequestCompletionHandler)completionHandler;
// GET 不缓存
- (void)ksGetNoCacheWithUrl:(NSString *)urlString
                 parameters:(NSDictionary *_Nullable)parameters
          completionHandler:(KSRequestCompletionHandler)completionHandler;

// POST 缓存自己选
- (void)ksPostWithURLString:(NSString *)URLString
                 parameters:(NSDictionary *_Nullable)parameters
                ignoreCache:(BOOL)ignoreCache
              cacheDuration:(NSTimeInterval)cacheDuration
          completionHandler:(KSRequestCompletionHandler)completionHandler;
// GET 缓存自己选
- (void)ksGetWithURLString:(NSString *)URLString
                parameters:(NSDictionary *)parameters
               ignoreCache:(BOOL)ignoreCache
             cacheDuration:(NSTimeInterval)cacheDuration
         completionHandler:(KSRequestCompletionHandler)completionHandler;

// 配合多网络请求一起用
- (KSNetRequestInfo *)ksNetRequestWithURLStr:(NSString *)URLString
                                      method:(NSString *)method
                                  parameters:(NSDictionary *)parameters
                                 ignoreCache:(BOOL)ignoreCache
                               cacheDuration:(NSTimeInterval)cacheDuration
                           completionHandler:(KSRequestCompletionHandler)completionHandler;

// 多网络请求
- (void)ksBatchOfRequestOperations:(NSArray<KSNetRequestInfo *> *)tasks
                     progressBlock:(void (^)(NSUInteger numberOfFinishedTasks, NSUInteger totalNumberOfTasks))progressBlock
                   completionBlock:(KSNetSuccessBatchBlock)completionBlock;

@end

NS_ASSUME_NONNULL_END
