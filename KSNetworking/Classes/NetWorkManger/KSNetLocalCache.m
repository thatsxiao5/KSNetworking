//
//  KSNetLocalCache.m
//  KSNetWork
//
//  Created by KSummer on 2019/12/3.
//  Copyright © 2019 KSummer. All rights reserved.
//

#import "KSNetLocalCache.h"
#import <UIKit/UIKit.h>

static NSString *KSCacheFileProcessingQueue = @"com.KSummer.NetQueue";
static NSString *KSCachaDocument = @"KSCache";
static const NSInteger KSDefaultCacheMaxDeadLine = 60 * 60 * 24;// 一天

@interface KSNetLocalCache () {
    NSCache *_memoryCache;
    NSString *_cachePath;
    NSFileManager *_fileManger;
    dispatch_queue_t _ksIOQueue;
    NSMutableSet *_protectCaches;
}

@end

@implementation KSNetLocalCache

+ (instancetype)shareInstance {
    static KSNetLocalCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[KSNetLocalCache alloc] init];
    });
    return cache;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        // 添加通知
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(backgroundClearDisk) name:UIApplicationDidEnterBackgroundNotification object:nil];
        _memoryCache = [NSCache new];
        _protectCaches = [NSMutableSet new];
        _ksIOQueue = dispatch_queue_create([KSCacheFileProcessingQueue UTF8String], DISPATCH_QUEUE_CONCURRENT);
        _maxCacheDeadline = KSDefaultCacheMaxDeadLine;

        //同步执行IO操作
        dispatch_sync(_ksIOQueue, ^{
            // 创建fileManger
            _fileManger = [NSFileManager new];
            // 创建缓存路径
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            _cachePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:KSCachaDocument];

            // 文件夹不存在存在,创建,存在,清空,再创建
            BOOL isDir;
            if (![_fileManger fileExistsAtPath:_cachePath isDirectory:&isDir]) {
                [self creatDocument];
            } else {
                if (!isDir) {
                    NSError *error = nil;
                    [_fileManger removeItemAtPath:_cachePath error:&error];
                    [self creatDocument];
                }
            }
        });
    }

    return self;
}

#pragma mark - public

- (void)addProtectCacheKey:(NSString *)urlKey {
    [_protectCaches addObject:urlKey];
}

- (BOOL)checkIfShouldUserCacheWithCacheDuration:(NSTimeInterval)cacheDuration cacheKey:(NSString *)urlkey {
    //缓存时效=0
    if (cacheDuration == 0) {
        return NO;
    }

    id localCache = [self searchCacheWithUrl:urlkey];

    if (localCache) {
        //缓存过期返回NO
        if ([self expireWithCacheKey:urlkey cacheDuration:cacheDuration]) {
            return NO;
        }
        return YES;
    }

    return NO;
}

// 通过urlKey 查找缓存
- (id)searchCacheWithUrl:(NSString *)urlKey {
    
    //内存缓存
    id object = [_memoryCache objectForKey:urlKey];

    if (!object) {
        //磁盘缓存
        NSString *filePath = [_cachePath stringByAppendingPathComponent:urlKey];
        if ([[NSFileManager defaultManager]fileExistsAtPath:filePath]) {
            object =  [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
            //内存缓存赋值
            [_memoryCache setObject:object forKey:urlKey];
        }
    }

    return object;
}

// 保存缓存
- (void)saveCacheData:(id<NSCopying>)data forKey:(NSString *)key {
    if (!data) {
        return;
    }

    [_memoryCache setObject:data forKey:key];
    dispatch_async(_ksIOQueue, ^{
        NSString *filePath = [_cachePath stringByAppendingPathComponent:key];
        BOOL written = [NSKeyedArchiver archiveRootObject:data toFile:filePath];
        if (!written) {
            NSLog(@"写入缓存失败");
        } else {
            NSLog(@"写入缓存成功");
        }
    });
}


#pragma mark - private

- (void)creatDocument {
    __autoreleasing NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:_cachePath withIntermediateDirectories:YES attributes:nil error:&error];
    if (!created) {
        NSLog(@"创建缓存文件失败: %@", error);
        return;
    }

    NSURL *url = [NSURL fileURLWithPath:_cachePath];
    NSError *uError = nil;
    // 避免缓存数据备份到iCloud
    [url setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:&error];
    if (uError) {
        NSLog(@"没有成功的设置 ‘应用不能备份的属性’, uError = %@", uError);
    }
}



// 清空文件缓存
- (void)cleanDiskWithCompletionBlock:(void (^)(void))completionBlock {
    dispatch_async(_ksIOQueue, ^{
        // 根据路径获取url
        NSURL *diskCacheUrl = [NSURL fileURLWithPath:_cachePath isDirectory:YES];

        NSArray *resourceKeys = @[NSURLLocalizedNameKey, NSURLNameKey, NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];

        NSDirectoryEnumerator *fileEnumerator = [_fileManger enumeratorAtURL:diskCacheUrl
                                                  includingPropertiesForKeys:resourceKeys
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                errorHandler:NULL];

        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-self.maxCacheDeadline];
        NSMutableDictionary *cacheFiles = [NSMutableDictionary dictionary];
        NSUInteger currentCacheSize = 0;

        // 遍历缓存文件夹中的所有文件，有2 个目的
        //  1. 删除过期的文件
        //  2. 删除比较的旧的文件 使得当前文件的大小 小于最大文件的大小
        NSMutableArray *urlsToDelete = [[NSMutableArray alloc] init];
        for (NSURL *fileURL in fileEnumerator) {
            NSDictionary *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:NULL];
            // 跳过文件夹
            if ([resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }

            // 跳过指定不能删除的文件 比如首页列表数据
            if ([_protectCaches containsObject:fileURL.lastPathComponent]) {
                continue;
            }

            // 删除过期文件
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                [urlsToDelete addObject:fileURL];
                continue;
            }

            // Store a reference to this file and account for its total size.
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += [totalAllocatedSize unsignedIntegerValue];
            [cacheFiles setObject:resourceValues forKey:fileURL];
        }

        for (NSURL *fileURL in urlsToDelete) {
            [_fileManger removeItemAtURL:fileURL error:nil];
        }

        // 如果删除过期的文件后，缓存的总大小还大于maxsize 的话则删除比较快老的缓存文件
        if (self.maxCacheSize > 0 && currentCacheSize > self.maxCacheSize) {
            // 这个过程主要清除到最大缓存的一半大小
            const NSUInteger desiredCacheSize = self.maxCacheSize / 2;

            // 按照最后的修改时间来排序，旧的文件排在前面
            NSArray *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                            usingComparator:^NSComparisonResult (id obj1, id obj2) {
                return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
            }];
            //删除文件到一半的大小
            for (NSURL *fileURL in sortedFiles) {
                if ([_fileManger removeItemAtURL:fileURL error:nil]) {
                    NSDictionary *resourceValues = cacheFiles[fileURL];
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    currentCacheSize -= [totalAllocatedSize unsignedIntegerValue];
                    if (currentCacheSize < desiredCacheSize) {
                        break;
                    }
                }
            }
        }

        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock();
            });
        }
    });
}


// 判断文件是否过期
- (BOOL)expireWithCacheKey:(NSString *)cacheFileNameKey cacheDuration:(NSTimeInterval)expirationDuration {
    NSString *filePath = [_cachePath stringByAppendingPathComponent:cacheFileNameKey];

    BOOL fileExist = [_fileManger fileExistsAtPath:filePath];
    if (fileExist) {
        NSTimeInterval fileDuration = [self cacheFileDuration:filePath];

        if (fileDuration > expirationDuration) {
            [_fileManger removeItemAtURL:[NSURL fileURLWithPath:filePath] error:nil];
            return YES;
        } else {
            return NO;
        }
    } else {
        return YES;
    }
}

// 当前时间跟文件修改时间做比较,得出时间差和设置的过期时间做比较
- (NSTimeInterval)cacheFileDuration:(NSString *)path {
    NSError *attributesRetrievalError = nil;
    NSDictionary *attributes = [_fileManger attributesOfItemAtPath:path
                                                             error:&attributesRetrievalError];
    if (!attributes) {
        NSLog(@"获取文件属性失败 %@: %@", path, attributesRetrievalError);
        return -1;
    } else {
        NSLog(@"获取文件成功");
    }

    NSTimeInterval seconds = -[[attributes fileModificationDate] timeIntervalSinceNow];
    return seconds;
}

#pragma mark - notification selector

- (void)removeAllObjects {
    [_memoryCache removeAllObjects];
}

- (void)backgroundClearDisk {
    UIApplication *application = [UIApplication sharedApplication];

    __block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];

    [self cleanDiskWithCompletionBlock:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
}

#pragma mark - dealloc

- (void)dealloc {
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

@end
