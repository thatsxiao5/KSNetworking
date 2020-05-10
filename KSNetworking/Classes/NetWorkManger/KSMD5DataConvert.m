//
//  KSMD5DataConvert.m
//  KSNetWork
//
//  Created by KSummer on 2019/12/3.
//  Copyright © 2019 KSummer. All rights reserved.
//

#import "KSMD5DataConvert.h"
#import <CommonCrypto/CommonDigest.h>


static NSString *KSConverMD5FromString(NSString *key){
    
    if (key.length == 0) {
        return nil;
    }
    
    const char *original_key = [key UTF8String];
    
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    
    CC_MD5(original_key,(unsigned int)strlen(original_key),result);
 
    NSMutableString *hash = [NSMutableString string];
    
    for (int i = 0; i < 16; i ++) {
        [hash appendFormat:@"%02X",result[i]];
    }
    
    return [hash lowercaseString];
    
}

//返回版本号
static NSString *KSNetCacheVersion(){
    
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
}


//根据url + params + method + 版本号生成唯一key
NSString *KSConvertMD5FromParameter(NSString *url,NSString *method,NSDictionary *params){
    
    NSString *requestInfo = [NSString stringWithFormat:@"Method:%@ Url:%@ Argument:%@ AppVersion:%@ ",method,url,params,KSNetCacheVersion()];
    
    return KSConverMD5FromString(requestInfo);
}


@implementation KSMD5DataConvert


@end
