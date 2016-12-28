//
//  ViewController.m
//  ZHWeChatPay
//
//  Created by 周昊 on 2016/12/28.
//  Copyright © 2016年 Cloud. All rights reserved.
//

#import "ViewController.h"
#import "WXApi.h"
#import <CommonCrypto/CommonDigest.h> // MD5加密需要导此包
// ------------获取终端IP地址需要以下引入及定义
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
#define IOS_VPN         @"utun0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"
// -------------
#import "XMLReader.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIButton *payServerBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [payServerBtn setTitle:@"包括服务器端操作的支付" forState:UIControlStateNormal];
    [payServerBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [payServerBtn addTarget:self action:@selector(zh_weChatPayIncludeServer) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:payServerBtn];
    [payServerBtn sizeToFit];
    payServerBtn.frame = CGRectMake((self.view.frame.size.width - payServerBtn.frame.size.width) / 2.0, 200, payServerBtn.frame.size.width, payServerBtn.frame.size.height);
    
    UIButton *payBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [payBtn setTitle:@"微信支付" forState:UIControlStateNormal];
    [payBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [payBtn addTarget:self action:@selector(zh_weChatPay) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:payBtn];
    [payBtn sizeToFit];
    payBtn.frame = CGRectMake((self.view.frame.size.width - payBtn.frame.size.width) / 2.0, CGRectGetMaxY(payServerBtn.frame) + 100, payBtn.frame.size.width, payBtn.frame.size.height);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(zh_handleWeChatPayResult:) name:@"doWeChatPayResult" object:nil];
}

- (void)zh_handleWeChatPayResult:(NSNotification *)notification
{
    BaseResp *resp = notification.object;
    switch (resp.errCode)
    {
        case WXSuccess:
            
            NSLog(@"支付成功");
            break;
            
        default:
            
            NSLog(@"支付失败");
            break;
    }
}

#pragma mark - 微信支付(包括服务器端的操作)
- (void)zh_weChatPayIncludeServer
{
    if (![WXApi isWXAppInstalled])
    {
        NSLog(@"未安装微信客户端");
        return;
    }
    if (![WXApi isWXAppSupportApi])
    {
        NSLog(@"不支持微信支付");
        return;
    }
    NSString *url = @"https://api.mch.weixin.qq.com/pay/unifiedorder"; // 请求腾讯服务器
    
    // 拼接详细的订单数据
    NSDictionary *postDict = [self zh_getProductArgs]; // 服务器端拼接数据及签名
    
    // 拼接调用支付接口所需要的参数(拼接成XML格式)
    NSString *string = [NSString stringWithFormat:@"<xml><sign>%@</sign><appid>%@</appid><body>%@</body><mch_id>%@</mch_id><nonce_str>%@</nonce_str><notify_url>%@</notify_url><out_trade_no>%@</out_trade_no><spbill_create_ip>%@</spbill_create_ip><total_fee>%d</total_fee><trade_type>APP</trade_type></xml>",[postDict objectForKey:@"sign"], WeChatAppID, [postDict objectForKey:@"body"], PartnerID, [postDict objectForKey:@"nonce_str"], [postDict objectForKey:@"notify_url"], [postDict objectForKey:@"out_trade_no"], [postDict objectForKey:@"spbill_create_ip"],[[postDict objectForKey:@"total_fee"] intValue]];
    
    
    // 创建网络请求
    NSURL *requestURL = [NSURL URLWithString:url];
    NSMutableURLRequest *request  = [[NSMutableURLRequest alloc]initWithURL:requestURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:[string dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSHTTPURLResponse* urlResponse = nil;
    NSError *error = [[NSError alloc] init];
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&error];
    NSString *result = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    
    if ([urlResponse statusCode] >= 200 && [urlResponse statusCode] < 300)
    {
        
        NSError *error2 = [NSError alloc];
        
        // 从腾讯服务器请求回来的数据将XML格式解析成字典
        NSDictionary *xmlDict = [[XMLReader dictionaryForXMLString:result error:&error2] objectForKey:@"xml"];
        
        // 调用支付接口
        PayReq *payRequest = [[PayReq alloc]init];
        payRequest.partnerId = [[xmlDict objectForKey:@"mch_id"] objectForKey:@"text"];
        payRequest.prepayId = [[xmlDict objectForKey:@"prepay_id"] objectForKey:@"text"];
        payRequest.package = @"Sign=WXPay";
        payRequest.nonceStr = [[xmlDict objectForKey:@"nonce_str"] objectForKey:@"text"];
        payRequest.timeStamp = [[NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]] intValue];
        
        // 构造参数列表,再次签名
        NSMutableDictionary *payDict = [NSMutableDictionary dictionary];
        [payDict setObject:WeChatAppID forKey:@"appid"];
        [payDict setObject:payRequest.nonceStr forKey:@"noncestr"];
        [payDict setObject:payRequest.package forKey:@"package"];
        [payDict setObject:payRequest.partnerId forKey:@"partnerid"];
        [payDict setObject:payRequest.prepayId forKey:@"prepayid"];
        [payDict setObject:[NSString stringWithFormat:@"%u", (unsigned int)payRequest.timeStamp]forKey:@"timestamp"];
        payRequest.sign = [self zh_genSign:payDict];
        
        [WXApi sendReq:payRequest];
    }
}

// 构造预付订单参数列表
- (NSDictionary *)zh_getProductArgs
{
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    
    NSString *timeStamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]]; // 获取时间戳
    NSString *nonceStr = [[self zh_md5:[NSString stringWithFormat:@"%d", arc4random() % 10000]] uppercaseString]; // 获取32位内的随机串, 防重发
    // 获取商家对用户的唯一标识
    
    NSString *outTradNo = [NSString stringWithFormat:@"%d", arc4random() % 10000];
    NSString *out_trade_no= [NSString stringWithFormat:@"%@%@",timeStamp,outTradNo];//获取商户订单号
    
    [params setObject:WeChatAppID forKey:@"appid"];//必填
    [params setObject:nonceStr forKey:@"nonce_str"];//随机字符串，必填
    [params setObject:@"APP" forKey:@"trade_type"]; //交易类型 必填
    [params setObject:@"有逼格的程序员" forKey:@"body"];//商品描述，必填
    [params setObject:@"这里是你本地接收回调通知的地址" forKey:@"notify_url"]; // 此处填可以让后台写个接口，如果支付成功，则微信后台调用此接口，返回yes,失败则返回no；
    [params setObject:out_trade_no forKey:@"out_trade_no"];//商户订单号，必填
    [params setObject:PartnerID forKey:@"mch_id"]; // 商户ID
    [params setObject:[self zh_getIPAddress:YES] forKey:@"spbill_create_ip"];//终端ip，必填
    [params setObject:@"1" forKey:@"total_fee"];
    //签名
    [params setObject:[self zh_genSign:params] forKey:@"sign"];
    
    return params;
}

// 将字符串MD5加密
- (NSString *)zh_md5:(NSString *)str
{
    // #import <CommonCrypto/CommonDigest.h> // MD5加密需要导此包
    const char *cStr = str.UTF8String;
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, strlen(cStr), digest);
    NSMutableString *md5Str = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
    {
        [md5Str appendFormat:@"%02x", digest[i]];
    }
    return md5Str;
}

// 签名
- (NSString *)zh_genSign:(NSDictionary *)signParams
{
    // 排序
    NSArray *keys = [signParams allKeys];
    NSArray *sortedKeys = [keys sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1 compare:obj2 options:NSNumericSearch];
    }];
    
    // 生成
    NSMutableString *sign = [NSMutableString string];
    for (NSString *key in sortedKeys) {
        [sign appendString:key];
        [sign appendString:@"="];
        [sign appendString:[signParams objectForKey:key]];
        [sign appendString:@"&"];
    }
    [sign appendString:@"key="];
    [sign appendString:APISignKey];// 注意:不能hardcode在客户端,建议genPackage这个过程都由服务器端完成
    
    NSString *result = [[self zh_md5:sign] uppercaseString];
    
    return result;
}

// 获取终端IP地址
- (NSString *)zh_getIPAddress:(BOOL)preferIPv4
{
    /*
     需要引入一下头文件及定义宏
     #include <ifaddrs.h>
     #include <arpa/inet.h>
     #include <net/if.h>
     #define IOS_CELLULAR    @"pdp_ip0"
     #define IOS_WIFI        @"en0"
     #define IOS_VPN         @"utun0"
     #define IP_ADDR_IPv4    @"ipv4"
     #define IP_ADDR_IPv6    @"ipv6"
     */
    NSArray *searchArray = preferIPv4 ?
    @[ IOS_WIFI @"/" IP_ADDR_IPv4, IOS_WIFI @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6 ] :
    @[ IOS_WIFI @"/" IP_ADDR_IPv6, IOS_WIFI @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4 ] ;
    
    NSDictionary *addresses = [self zh_getIPAddresses];
    
    __block NSString *address;
    [searchArray enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop)
     {
         address = addresses[key];
         if(address) *stop = YES;
     } ];
    return address ? address : @"0.0.0.0";
}

- (NSDictionary *)zh_getIPAddresses
{
    NSMutableDictionary *addresses = [NSMutableDictionary dictionaryWithCapacity:8];
    // retrieve the current interfaces - returns 0 on success
    //  导入ifaddrs.h
    struct ifaddrs *interfaces;
    if(!getifaddrs(&interfaces))
    {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for(interface=interfaces; interface; interface=interface->ifa_next)
        {
            if(!(interface->ifa_flags & IFF_UP) || (interface->ifa_flags & IFF_LOOPBACK))
            {
                continue; // deeply nested code harder to read  IFF_UP需要导入头文件
            }
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            if(addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6))
            {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                char addrBuf[INET6_ADDRSTRLEN];
                if(inet_ntop(addr->sin_family, &addr->sin_addr, addrBuf, sizeof(addrBuf)))
                {
                    NSString *key = [NSString stringWithFormat:@"%@/%@", name, addr->sin_family == AF_INET ? IP_ADDR_IPv4 : IP_ADDR_IPv6];
                    addresses[key] = [NSString stringWithUTF8String:addrBuf];
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    // The dictionary keys have the form "interface" "/" "ipv4 or ipv6"
    return [addresses count] ? addresses : nil;
}

#pragma mark - 微信支付(不包括服务器, 正常的操作流程就需要这一个方法即可)
- (void)zh_weChatPay
{
    if (![WXApi isWXAppInstalled])
    {
        NSLog(@"未安装微信客户端");
        return;
    }
    if (![WXApi isWXAppSupportApi])
    {
        NSLog(@"不支持微信支付");
        return;
    }
    // 此处的请求可以替换为AFNetworking的请求
    NSString *urlString = @"http://xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; // 向自己的服务器请求订单生成预支付订单信息
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    [request setHTTPMethod:@"POST"];
    // body: 商品描述
    // out_trade_no: 商品订单流水号
    // spbill_create_ip: 终端IP地址
    // total_fee: 商品价格 单位: 分
    NSString *outTradNo = [NSString stringWithFormat:@"%d", arc4random() % 10000];
    NSString *out_trade_no= [NSString stringWithFormat:@"%@%@",[NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]],outTradNo]; // 随机生成商户订单号
    NSString *bodyString = [NSString stringWithFormat:@"body=商品的描述&out_trade_no=%@&spbill_create_ip=%@&total_fee=1", out_trade_no, [self zh_getIPAddress:YES]];
    NSData *bodyData = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:bodyData];
    
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    
    if ([[NSString stringWithFormat:@"%@", result[@"opflag"]] isEqualToString:@"1"])
    {
        
        NSError *error = nil;
        NSDictionary *xmlDict = [[XMLReader dictionaryForXMLString:result[@"weixinPost"] error:&error] objectForKey:@"xml"];
        
        //调用支付接口
        PayReq *payRequest = [[PayReq alloc]init];
        payRequest.partnerId = [[xmlDict objectForKey:@"mch_id"] objectForKey:@"text"];
        payRequest.prepayId = [[xmlDict objectForKey:@"prepay_id"] objectForKey:@"text"];
        payRequest.package = @"Sign=WXPay";
        payRequest.nonceStr = [[xmlDict objectForKey:@"nonce_str"] objectForKey:@"text"];
        payRequest.timeStamp = [[NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]] intValue];
        
        //构造参数列表,再次签名
        NSMutableDictionary *payDict = [NSMutableDictionary dictionary];
        [payDict setObject:WeChatAppID forKey:@"appid"];
        [payDict setObject:payRequest.nonceStr forKey:@"noncestr"];
        [payDict setObject:payRequest.package forKey:@"package"];
        [payDict setObject:payRequest.partnerId forKey:@"partnerid"];
        [payDict setObject:payRequest.prepayId forKey:@"prepayid"];
        [payDict setObject:[NSString stringWithFormat:@"%u", (unsigned int)payRequest.timeStamp] forKey:@"timestamp"];
        payRequest.sign = [self zh_genSign:payDict];
        
        if ([WXApi sendReq:payRequest]) // 调起微信客户端支付
        {
            NSLog(@"调起微信支付成功!");
        }
        else
        {
            NSLog(@"调起微信支付失败!");
        }
    }
    else
    {
        NSLog(@"调起微信支付失败!");
    }
}

#pragma mark -
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

@end
