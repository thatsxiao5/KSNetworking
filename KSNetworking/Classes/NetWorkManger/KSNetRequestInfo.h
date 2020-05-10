//
//  KSNetRequestInfo.h
//  KSNetWork
//
//  Created by KSummer on 2019/12/3.
//  Copyright © 2019 KSummer. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


typedef void (^KSRequestCompletionHandler) (NSError *_Nullable error, BOOL isCache, NSDictionary *_Nullable result);
typedef BOOL (^KSRequestComletionAddCacheConditionBlock)(NSDictionary *result);

typedef void (^KSNetSuccessBatchBlock)(NSArray *operationArray);
typedef void (^KSRequestCompletionAddExcepetionHanle)(NSError* _Nullable errror,  NSMutableDictionary* result);


//创建一个对象，用来保存，url，method，params，是否忽略缓存，缓存时间和回调
@interface KSNetRequestInfo : NSObject

/* url*/
@property (nonatomic, strong) NSString *urlStr;
/* 请求方式*/
@property (nonatomic, strong) NSString *method;
/* 参数*/
@property (nonatomic, strong) NSDictionary *params;
/** 是否忽略缓存*/
@property (nonatomic, assign) BOOL ignoreCache;
/** 缓存时间*/
@property (nonatomic, assign) NSTimeInterval cacheDuration;
/** block回调*/
@property(nonatomic, copy)KSRequestCompletionHandler completionHandlerBlock;


@end

NS_ASSUME_NONNULL_END
