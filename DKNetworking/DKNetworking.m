//
//  DKNetworking.m
//  DKNetworking
//
//  Created by 庄槟豪 on 2017/2/25.
//  Copyright © 2017年 cn.dankal. All rights reserved.
//

#import "DKNetworking.h"
#import "AFNetworking.h"
#import "DKNetworkSessionManager.h"
#import "DKNetworkLogManager.h"
#import "MBProgressHUD+DZM.h"
#import "UIView+Toast.h"
#define KeyWindow       [[UIApplication sharedApplication] keyWindow]
#define KNetworkSessionTask(Method) [self request:[DKNetworkRequest requestWithUrlStr:URL method:Method params:parameters] callback:callback]
#define KNetworkSessionTaskInstance(Method) [DKNetworkManager Method:URL parameters:parameters callback:callback]

@interface DKNetworking ()
@property (nonatomic, strong) DKNetworkRequest *request;
@end

@implementation DKNetworking

static BOOL isOpenLog;
static NSArray<NSString *> *_methods;
static DKNetworkSessionManager *_sessionManager;
static NSMutableArray<NSURLSessionTask *> *_allSessionTask;

#ifdef RAC
static DKNetworkFlattenMapBlock _flattenMapBlock;
#endif
static DKNetworkCacheType _networkCacheType;                    // 缓存类型
static DKRequestSerializer _networkRequestSerializer;           // 请求序列化格式
static DKResponseSerializer _networkResponseSerializer;         // 响应反序列化格式
static DKRequestTimeoutInterval _networkRequestTimeoutInterval; // 请求超时时间
static NSDictionary *_networkHeader;                            // 全局请求头
static NSString  *_hudText;
static NSInteger  _networkStatus;//返回数据状态码
static NSString *  _networkStatusKeyName;//返回数据状态的字段key
static BOOL _isNoAuthenticateResultStatus;//不鉴定数据返回的状态
static NSString*  _statusErrorKeyName;//返回数据状态错误时候的提示文字例如密码错误

/** 请求状态成功数据失败是否显示后台定义的提示文字 */
static BOOL _isHideServerErrorText;


static CGFloat const kDefaultTimeoutInterval = 10.f;

+ (instancetype)networkManager
{
    static dispatch_once_t onceToken;
    static DKNetworking *networkManager;

    dispatch_once(&onceToken, ^{
        networkManager = [[DKNetworking alloc]init];
    });
    return networkManager;}

+ (void)setupCacheType:(DKNetworkCacheType)cacheType
{
    _networkCacheType = cacheType;
}

+ (void)setupBaseURL:(NSString *)baseURL
{
    _sessionManager = [[DKNetworkSessionManager alloc] initWithBaseURL:[NSURL URLWithString:baseURL]];
    
    [self initSessionManager];
}

#pragma mark - Network Status

+ (void)networkStatusWithBlock:(DKNetworkStatusBlock)networkStatusBlock
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            switch (status) {
                case AFNetworkReachabilityStatusUnknown:
                    if (networkStatusBlock) networkStatusBlock(DKNetworkStatusUnknown);
                    break;
                case AFNetworkReachabilityStatusNotReachable:
                    if (networkStatusBlock) networkStatusBlock(DKNetworkStatusNotReachable);
                    break;
                case AFNetworkReachabilityStatusReachableViaWWAN:
                    if (networkStatusBlock) networkStatusBlock(DKNetworkStatusReachableViaWWAN);
                    break;
                case AFNetworkReachabilityStatusReachableViaWiFi:
                    if (networkStatusBlock) networkStatusBlock(DKNetworkStatusReachableViaWiFi);
                    break;
            }
        }];
    });
}

+ (BOOL)isNetworking
{
    return [AFNetworkReachabilityManager sharedManager].reachable;
}

+ (BOOL)isWWANNetwork
{
    return [AFNetworkReachabilityManager sharedManager].reachableViaWWAN;
}

+ (BOOL)isWiFiNetwork
{
    return [AFNetworkReachabilityManager sharedManager].reachableViaWiFi;
}

#pragma mark - Log

+ (void)openLog
{
    isOpenLog = YES;
}

+ (void)closeLog
{
    isOpenLog = NO;
}

#pragma mark - Request Method

#pragma mark 链式调用

- (DKNetworking *(^)(NSString *))get
{
    return ^DKNetworking *(NSString *url){
        self.request.method = DKRequestMethodGET;
        self.request.urlStr = url;
        return self;
    };
}

- (DKNetworking *(^)(NSString *))post
{
    return ^DKNetworking *(NSString *url){
        self.request.method = DKRequestMethodPOST;
        self.request.urlStr = url;
        return self;
    };
}

- (DKNetworking *(^)(NSString *))put
{
    return ^DKNetworking *(NSString *url){
        self.request.method = DKRequestMethodPUT;
        self.request.urlStr = url;
        return self;
    };
}

- (DKNetworking *(^)(NSString *))delete
{
    return ^DKNetworking *(NSString *url){
        self.request.method = DKRequestMethodDELETE;
        self.request.urlStr = url;
        return self;
    };
}

- (DKNetworking *(^)(NSString *))patch
{
    return ^DKNetworking *(NSString *url){
        self.request.method = DKRequestMethodPATCH;
        self.request.urlStr = url;
        return self;
    };
}

- (DKNetworking *(^)(NSDictionary *))params
{
    return ^DKNetworking *(NSDictionary *params){
        self.request.params = params;
        return self;
    };
}

- (DKNetworking *(^)(NSDictionary *))header
{
    return ^DKNetworking *(NSDictionary *header){
        [DKNetworking setNetworkHeader:header];
        return self;
    };
}

- (DKNetworking *(^)(DKNetworkCacheType))cacheType
{
    return ^DKNetworking *(DKNetworkCacheType cacheType){
        [DKNetworking setupCacheType:cacheType];
        return self;
    };
}

- (DKNetworking *(^)(DKRequestSerializer requestSerializer))requestSerializer
{
    return ^DKNetworking *(DKRequestSerializer requestSerializer){
        [DKNetworking setRequestSerializer:requestSerializer];
        return self;
    };
}

- (DKNetworking *(^)(DKResponseSerializer responseSerializer))responseSerializer
{
    return ^DKNetworking *(DKResponseSerializer responseSerializer){
        [DKNetworking setResponseSerializer:responseSerializer];
        return self;
    };
}

- (DKNetworking *(^)(DKRequestTimeoutInterval requestTimeoutInterval))requestTimeoutInterval
{
    return ^DKNetworking *(DKRequestTimeoutInterval requestTimeoutInterval){
        [DKNetworking setRequestTimeoutInterval:requestTimeoutInterval];
        return self;
    };
}

- (void (^)(DKNetworkBlock))callback
{
    return ^void(DKNetworkBlock block){
        [self request:self.request callback:^(DKNetworkRequest *request, DKNetworkResponse *response) {
            block(request, response);
            self.request = nil;
        }];
    };
}

#ifdef RAC
- (RACSignal *)executeSignal
{
    RACSignal *resultSignal = [self rac_request:self.request];
    if (_flattenMapBlock)
        return [resultSignal flattenMap:_flattenMapBlock];

    return resultSignal;
}

- (RACSignal *)rac_request:(DKNetworkRequest *)request
{
    NSAssert(request.urlStr.length, @"DKNetworking Error: URL can not be nil");
    
    request.header = _networkHeader;
    request.cacheType = _networkCacheType;
    request.requestSerializer = _networkRequestSerializer;
    request.requestTimeoutInterval = _networkRequestTimeoutInterval;
    request.showHUDText=_hudText;

    NSString *URL = request.urlStr;
    NSDictionary *parameters = request.params;
    NSString *method = _methods[request.method];
    
    if (request.showHUDText) {
        //为了一个视图不会重复出现两个提示框则先隐藏一个
        [self hideHudView];
        [self showHudText:request.showHUDText View:[self activityViewController].view];
        
    }

    
    RACSignal *requestSignal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSURLSessionTask *sessionTask = [_sessionManager requestWithMethod:method URLString:URL parameters:parameters completion:^(NSURLSessionDataTask *task, DKNetworkResponse *response) {
            [DKNetworking.allSessionTask removeObject:task];
            [self hideHudView];


            if (response.rawData)
                [DKNetworkCache setCache:response.rawData URL:URL parameters:parameters];
            if (isOpenLog) {
                DKLog(@"DKN 请求: %@",[request.mj_keyValues dk_jsonString]);
                if (!response.error) {
                    DKLog(@"DKN 响应: %@",[response.rawData dk_jsonString]);
                } else {
                    [[DKNetworkLogManager defaultManager] showErrorLogWithResponse:response];
                }
            }
            [subscriber sendNext:RACTuplePack(request,response)];
            [subscriber sendCompleted];
        }];
        [DKNetworking.allSessionTask addObject:sessionTask];
        return nil;
    }];
    
    if (_networkCacheType == DKNetworkCacheTypeCacheNetwork) {
        [self hideHudView];

        RACSignal *cacheSignal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
            DKNetworkResponse *cacheResponse = [DKNetworkResponse responseWithRawData:DKCache(URL, parameters) error:nil];
            [subscriber sendNext:RACTuplePack(request,cacheResponse)];
            [subscriber sendCompleted];
            return nil;
        }];
        return [cacheSignal merge:requestSignal];
    }
    
    return requestSignal;
}
#endif

#pragma mark 常规调用

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

+ (NSURLSessionTask *)request:(DKNetworkRequest *)request callback:(DKNetworkBlock)callback
{
    NSAssert(request.urlStr.length, @"DKNetworking Error: URL can not be nil");
    
    request.header = _networkHeader;
    request.cacheType = _networkCacheType;
    request.requestSerializer = _networkRequestSerializer;
    request.requestTimeoutInterval = _networkRequestTimeoutInterval;
    request.showHUDText=_hudText;
    NSString *URL = request.urlStr;
    NSDictionary *parameters = request.params;
    NSString *method = _methods[request.method];
    if (request.showHUDText) {
        //为了一个视图不会重复出现两个提示框则先隐藏一个
        [self hideHudView];
        [self showHudText:request.showHUDText View:[DKNetworkManager activityViewController].view];
        
    }
    
    if (_networkCacheType == DKNetworkCacheTypeCacheNetwork && callback){
        if (request.showHUDText) {
            [self hideHudView];
        }
        callback(request, [DKNetworkResponse responseWithRawData:DKCache(URL, parameters) error:nil]);
    }
    
    
    NSURLSessionTask *sessionTask = [_sessionManager requestWithMethod:method URLString:URL parameters:parameters completion:^(NSURLSessionDataTask *task, DKNetworkResponse *response) {
        [self.allSessionTask removeObject:task];
        [self hideHudView];
        if (isOpenLog) {
            DKLog(@"DKN 请求: %@",[request.mj_keyValues dk_jsonString]);
            if (!response.error) {
                DKLog(@"DKN 响应: %@",[response.rawData dk_jsonString]);
            } else {
                [[DKNetworkLogManager defaultManager] showErrorLogWithResponse:response];
            }
        }
        //请求失败 超时没网等等
        if (response.error) {
            
            [[DKNetworkManager activityViewController].view makeToast:@"请求错误" duration:0.0 position:@"CSToastPositionCenter"];
            
        }
        if (_isNoAuthenticateResultStatus) {
            _isNoAuthenticateResultStatus=NO;
            if (response.rawData)
                [DKNetworkCache setCache:response.rawData URL:URL parameters:parameters];
            if (callback)
                callback(request, response);
        }else{
            //请求成功 状态正确 正确返回数据
            if ( [self isSuccess:response.rawData]) {
                if (response.rawData)
                    [DKNetworkCache setCache:response.rawData URL:URL parameters:parameters];
                if (callback)
                    callback(request, response);
            }
        }
        
    
      
       
    }];
    
    [self.allSessionTask addObject:sessionTask];
    
    return sessionTask;
}

#pragma mark showHud hideHud

+(void)hideHudView{
    [MBProgressHUD hideHUDForView:[DKNetworkManager activityViewController].view];

}

-(void)hideHudView{
  [MBProgressHUD hideHUDForView:[self activityViewController].view];
}
+(void)showHudText:(NSString *)text View:(UIView*)view
{
     [MBProgressHUD showMessage:text toView:view];
   
}

-(void)showHudText:(NSString *)text View:(UIView*)view
{
    [MBProgressHUD showMessage:text toView:view];

}
+ (void)setRequestStatusKeyName:(NSString *)keyName
{
    _networkStatusKeyName=keyName;
}
+ (void)setRequestStatusCode:(NSInteger )code
{
    _networkStatus=code;
}
+(void)setResultErrorKeyName:(NSString *)keyName
{
    _statusErrorKeyName=keyName;
}

+ (void)noAuthenticationRequests:(BOOL)special
{
    _isNoAuthenticateResultStatus = special;
}

+(void)isHideServerText:(BOOL)ishide
{
    _isHideServerErrorText=ishide;
}
+(BOOL)isSuccess:(id )responseObject
{
    
    if (_networkStatusKeyName!=nil) {
        if ([responseObject[_networkStatusKeyName]intValue] ==_networkStatus) {
            
            return YES;
        }
        else{
            [DKNetworkManager showLoadRequestSuccessButStatusError:responseObject];
            return NO;
        }
        
    }
    else{
        //必须设置一个用于标记成功或者失败的字段才知道请求是否成功  resultCount是ViewController苹果那个接口的标记  使用时请设置自己服务器的字段
        //    [NetworkManger shareManager].errorOrRightCode=@"resultCount";
        
        NSCAssert(_networkStatusKeyName!= nil, @"未设置标记与成功或者失败的字段");
        
        return NO;
        
    }
    
}
-(void)showLoadRequestSuccessButStatusError:(id )responseObject{
    
    if ([responseObject isKindOfClass:[NSDictionary class]]) {
        
        
        NSString *tip=responseObject[_statusErrorKeyName];
        //是否显示失败原因
        if (_isHideServerErrorText==YES) {
            
            _isHideServerErrorText=NO;
//            [DKNetworkManager isHideServerText:NO];
            
        }
        else{
            
            if ([tip  isKindOfClass:[NSNull class]]) {
                [self showTipMessage:@"数据错误"];
            }
            else{
                [self showTipMessage:tip];
                
            }
            
        }
    }
    else{
        
        NSLog(@"请求结果不是字典类型");
        
    }
    
    
    
}
-(void)showTipMessage:(NSString *)text{
    [KeyWindow makeToast:text duration:.5 position:@"CSToastPositionCenter"];

}

- (NSURLSessionTask *)request:(DKNetworkRequest *)request callback:(DKNetworkBlock)callback
{
    return [DKNetworking request:request callback:callback];
}

#pragma clang diagnostic pop

+ (NSURLSessionTask *)GET:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTask(DKRequestMethodGET);
}

- (NSURLSessionTask *)GET:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTaskInstance(GET);
}

+ (NSURLSessionTask *)POST:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTask(DKRequestMethodPOST);
}

- (NSURLSessionTask *)POST:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTaskInstance(POST);
}

+ (NSURLSessionTask *)PUT:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTask(DKRequestMethodPUT);
}

- (NSURLSessionTask *)PUT:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTaskInstance(PUT);
}

+ (NSURLSessionTask *)DELETE:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTask(DKRequestMethodDELETE);
}

- (NSURLSessionTask *)DELETE:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTaskInstance(DELETE);
}

+ (NSURLSessionTask *)PATCH:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTask(DKRequestMethodPATCH);
}

- (NSURLSessionTask *)PATCH:(NSString *)URL parameters:(NSDictionary *)parameters callback:(DKNetworkBlock)callback
{
    return KNetworkSessionTaskInstance(PATCH);
}

#pragma mark - Upload

+ (NSURLSessionTask *)uploadFileWithURL:(NSString *)URL parameters:(NSDictionary *)parameters name:(NSString *)name filePath:(NSString *)filePath progressBlock:(DKNetworkProgressBlock)progressBlock callback:(void (^)(DKNetworkResponse *))callback
{
    NSURLSessionTask *sessionTask = [_sessionManager uploadWithURLString:URL parameters:parameters constructingBodyWithBlock:^(id<DKMultipartFormData> formData) {
        NSError *error = nil;
        [formData appendPartWithFileURL:[NSURL URLWithString:filePath] name:name error:&error];
        if (error && callback) {
            callback([DKNetworkResponse responseWithRawData:nil error:error]);
        }
    } progress:^(NSProgress *uploadProgress) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (progressBlock)
                progressBlock(uploadProgress);
        });
    } completion:^(NSURLSessionDataTask *task, DKNetworkResponse *response) {
        [self.allSessionTask removeObject:task];
        if (isOpenLog)
            DKLog(@"%@",response.error ? response.error : [response.rawData dk_jsonString]);
        if (callback)
            callback(response);
    }];
    
    [self.allSessionTask addObject:sessionTask];
    
    return sessionTask;
}

+ (NSURLSessionTask *)uploadImagesWithURL:(NSString *)URL parameters:(NSDictionary *)parameters name:(NSString *)name images:(NSArray<UIImage *> *)images fileNames:(NSArray<NSString *> *)fileNames imageScale:(CGFloat)imageScale imageType:(NSString *)imageType progressBlock:(DKNetworkProgressBlock)progressBlock callback:(void (^)(DKNetworkResponse *))callback
{
    NSURLSessionTask *sessionTask = [_sessionManager uploadWithURLString:URL parameters:parameters constructingBodyWithBlock:^(id<DKMultipartFormData> formData) {
        for (NSUInteger i = 0; i < images.count; i++) {
            // 压缩图片
            NSData *imageData = UIImageJPEGRepresentation(images[i], imageScale ?: 1.f);
            // 图片名
            NSString *fileName = fileNames ? [NSString stringWithFormat:@"%@.%@", fileNames[i], imageType ?: @"jpg"] : [NSString stringWithFormat:@"%f%ld.%@",[[NSDate date] timeIntervalSince1970], (unsigned long)i, imageType ?: @"jpg"];
            // MIME类型
            NSString *mimeType = [NSString stringWithFormat:@"image/%@",imageType ?: @"jpg"];
            // 添加表单数据
            [formData appendPartWithFileData:imageData name:name fileName:fileName mimeType:mimeType];
        }
    } progress:^(NSProgress *uploadProgress) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (progressBlock)
                progressBlock(uploadProgress);
        });
    } completion:^(NSURLSessionDataTask *task, DKNetworkResponse *response) {
        [self.allSessionTask removeObject:task];
        if (isOpenLog)
            DKLog(@"%@",response.error ? response.error : [response.rawData dk_jsonString]);
        if (callback)
            callback(response);
    }];
    
    [self.allSessionTask addObject:sessionTask];
    
    return sessionTask;
}

#pragma mark - Download

+ (NSURLSessionTask *)downloadWithURL:(NSString *)URL fileDir:(NSString *)fileDir progressBlock:(DKNetworkProgressBlock)progressBlock callback:(void (^)(NSString *, NSError *))callback
{
    NSURLSessionDownloadTask *downloadTask = [_sessionManager downloadWithURLString:URL fileDir:fileDir progress:^(NSProgress *downloadProgress) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (progressBlock)
                progressBlock(downloadProgress);
        });
    } completion:^(NSString *filePath, NSError *error) {
        if (isOpenLog)
            DKLog(@"%@",error ? error : filePath);
        if (callback)
            callback(filePath, error);
    }];
    
    [self.allSessionTask addObject:downloadTask];
    
    return downloadTask;
}

#pragma mark - Cancel Request

+ (void)cancelAllRequest
{
    @synchronized(self) {
        [[self allSessionTask] enumerateObjectsUsingBlock:^(NSURLSessionTask  *_Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
            [task cancel];
        }];
        [self.allSessionTask removeAllObjects];
    }
}

+ (void)cancelRequestWithURL:(NSString *)URL
{
    if (!URL) return;
    @synchronized (self) {
        [self.allSessionTask enumerateObjectsUsingBlock:^(NSURLSessionTask  *_Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([task.currentRequest.URL.absoluteString hasPrefix:URL]) {
                [task cancel];
                [self.allSessionTask removeObject:task];
                *stop = YES;
            }
        }];
    }
}

#pragma mark - DKNetworkSessionManager

#pragma mark Init

+ (void)load
{
    // 开始监测网络状态
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
}

+ (void)initialize
{
    _methods = @[@"GET", @"POST", @"PUT", @"DELETE", @"PATCH"];
    
    // 所有请求共用一个SessionManager
    _sessionManager = [DKNetworkSessionManager manager];
    
    [self initSessionManager];
}

+ (void)initSessionManager
{
    _sessionManager.requestSerializer = _networkRequestSerializer == DKRequestSerializerHTTP ? [AFHTTPRequestSerializer serializer] : [AFJSONRequestSerializer serializer];
    _sessionManager.responseSerializer = _networkResponseSerializer == DKResponseSerializerHTTP ? [AFHTTPResponseSerializer serializer] : [AFJSONResponseSerializer serializer];
    _sessionManager.requestSerializer.timeoutInterval = _networkRequestTimeoutInterval ?: kDefaultTimeoutInterval;
    
    if (_networkHeader)
        [_networkHeader enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id obj, BOOL * _Nonnull stop) {
            [_sessionManager.requestSerializer setValue:obj forHTTPHeaderField:key];
        }];
}

#pragma mark - Result Config
#ifdef RAC
+ (void)setupResponseSignalWithFlattenMapBlock:(DKNetworkFlattenMapBlock)flattenMapBlock
{
    _flattenMapBlock = flattenMapBlock;
}
#endif

#pragma mark Reset

+ (void)setRequestSerializer:(DKRequestSerializer)requestSerializer
{
    _sessionManager.requestSerializer = requestSerializer == DKRequestSerializerHTTP ? [AFHTTPRequestSerializer serializer] : [AFJSONRequestSerializer serializer];
    _networkRequestSerializer = requestSerializer;
}

+ (void)setResponseSerializer:(DKResponseSerializer)responseSerializer
{
    _sessionManager.responseSerializer = responseSerializer == DKResponseSerializerHTTP ? [AFHTTPResponseSerializer serializer] : [AFJSONResponseSerializer serializer];
    _networkResponseSerializer = responseSerializer;
}

+ (void)setupSessionManager:(DKNetworkSessionManagerBlock)sessionManagerBlock
{
    if (sessionManagerBlock) {
        sessionManagerBlock(_sessionManager);
    }
}

+ (void)setRequestTimeoutInterval:(NSTimeInterval)time
{
    _sessionManager.requestSerializer.timeoutInterval = time;
    _networkRequestTimeoutInterval = time;
}
+ (void)setRequestHudText:(NSString *)text
{
    _hudText=text;
}

+ (void)setNetworkHeader:(NSDictionary *)_networkHeader
{
    if (_networkHeader) {
        [_networkHeader enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id obj, BOOL * _Nonnull stop) {
            [self setValue:obj forHTTPHeaderField:key];
        }];
    }
}

+ (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field
{
    [_sessionManager.requestSerializer setValue:value forHTTPHeaderField:field];
    
    if (!_networkHeader) {
        _networkHeader = [NSDictionary dictionaryWithObject:value forKey:field];
    } else {
        NSMutableDictionary *headerTemp = [NSMutableDictionary dictionaryWithDictionary:_networkHeader];
        headerTemp[field] = value;
        _networkHeader = [headerTemp copy];
    }
}

#pragma mark - Getters && Setters

/**
 存储所有请求task的数组
 */
+ (NSMutableArray *)allSessionTask
{
    if (!_allSessionTask) {
        _allSessionTask = [[NSMutableArray alloc] init];
    }
    return _allSessionTask;
}

/**
 链式调用时候保存每一步的request配置信息

 @return 链式调用的请求对象
 */
- (DKNetworkRequest *)request
{
    if (!_request) {
        _request = [[DKNetworkRequest alloc] init];
    }
    return _request;
}


#pragma mark - 查找当前活动窗口
- (UIViewController *)activityViewController
{
    UIViewController* activityViewController = nil;
    
    UIWindow * window = [[UIApplication sharedApplication] keyWindow];
    if(window.windowLevel != UIWindowLevelNormal)
    {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        for(UIWindow *tmpWin in windows)
        {
            if(tmpWin.windowLevel == UIWindowLevelNormal)
            {
                window = tmpWin;
                break;
            }
        }
    }
    
    NSArray *viewsArray = [window subviews];
    if([viewsArray count] > 0)
    {
        UIView *frontView = [viewsArray objectAtIndex:0];
        
        id nextResponder = [frontView nextResponder];
        
        if([nextResponder isKindOfClass:[UIViewController class]])
        {
            activityViewController = nextResponder;
        }
        else
        {
            activityViewController = window.rootViewController;
        }
    }
    
    return activityViewController;
}

@end
