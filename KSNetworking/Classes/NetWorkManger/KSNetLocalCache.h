//
//  KSNetLocalCache.h
//  KSNetWork
//
//  Created by KSummer on 2019/12/3.
//  Copyright © 2019 KSummer. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KSNetLocalCache : NSObject

/** 失效*/
@property (nonatomic, assign) NSInteger maxCacheDeadline;
/** 缓存最大size*/
@property (nonatomic, assign) NSUInteger maxCacheSize;


+ (instancetype)shareInstance;

- (BOOL)checkIfShouldUserCacheWithCacheDuration:(NSTimeInterval)cacheDuration cacheKey:(NSString *)urlkey;
- (void)addProtectCacheKey:(NSString*)key;
- (id)searchCacheWithUrl:(NSString *)urlKey;
- (void)saveCacheData:(id<NSCopying>)data forKey:(NSString *)key;



@end

NS_ASSUME_NONNULL_END
