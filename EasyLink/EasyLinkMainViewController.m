//
//  EasyLinkMainViewController.m
//  EMW ToolBox
//
//  Created by William Xu on 13-7-28.
//  Copyright (c) 2013年 MXCHIP Co;Ltd. All rights reserved.
//

#import "EasyLinkMainViewController.h"
#import "PulsingHaloLayer.h"
#import "EasyLinkFTCTableViewController.h"
#import "EasyLinkIpConfigTableViewController.h"
#import "easylinkModeConfigTableViewController.h"
#import "newModuleTableViewCell.h"

typedef enum{
    ePage_StartEasyLink = 0,
    ePage_ConnectingToModule,
    ePage_SendingConfig,
    ePage_ConnectingToTargetWlan,
    ePage_ScanNewDevice,
    maxEasyLinkSoftPages,
} EasyLinkSoftPage;

#define WIDTH_ALERT_VIEW    290
#define HEIGHT_ALERT_VIEW   300

NSString * const easylinkModeFieldText[] = { @"EasyLink V1", @"EasyLink V2", @"EasyLink Plus", @"EasyLink Combo", @"EasyLink AWS", @"EasyLink Soft AP"};
NSString * const easylinkSendingText[] = { @"EasyLink V1 sending...", @"EasyLink V2 sending...", @"EasyLink Plus sending...", @"EasyLink Combo sending...", @"EasyLink AWS sending...", @"EsyLink Soft AP sending..."};

@interface EasyLinkMainViewController ()

@end

@interface EasyLinkMainViewController (Private)

/* button action, where we need to start or stop the request 
 @param: button ... tag value defines the action 
 */
- (void)updateDeviceCountLable;
- (IBAction)easyLinkV2ButtonAction:(UIButton*)button;
- (IBAction)easyLinkuAPButtonAction:(UIButton*)button;

/*
 This method start the transmitting the data to connected
 AP. Nerwork validation is also done here. All exceptions from
 library is handled.
 */
- (void)startTransmitting: (EasyLinkMode)mode;

/*
 Prepare a cell that is created with respect to the indexpath
 @param cell is an object of UITableViewcell which is newly created 
 @param indexpath  is respective indexpath of the cell of the row. 
*/
-(UITableViewCell *) prepareCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;

/* 
 Notification method handler when app enter in forground
 @param the fired notification object
 */
- (void)appEnterInforground:(NSNotification*)notification;

/* 
 Notification method handler when app enter in background
 @param the fired notification object
 */
- (void)appEnterInBackground:(NSNotification*)notification;

/* 
 Notification method handler when status of wifi changes 
 @param the fired notification object
 */
- (void)wifiStatusChanged:(NSNotification*)notification;

@end

@implementation EasyLinkMainViewController
@synthesize foundModules;

- (void)awakeFromNib
{
    [super awakeFromNib];
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle -

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSString *title = [NSString stringWithFormat:@"EasyLink v%@", [EASYLINK version]];
    [self setTitle:title];

    // Do any additional setup after loading the view from its nib.
    bgView.showsVerticalScrollIndicator = NO;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = [paths objectAtIndex:0];
    apInforRecordFile = [docPath stringByAppendingPathComponent:@"ApInforRecord.plist"];
    apInforRecord = [[NSMutableDictionary alloc] initWithContentsOfFile:apInforRecordFile];
    if(apInforRecord == nil)
        apInforRecord = [NSMutableDictionary dictionaryWithCapacity:10];    
    
    if( easylink_config == nil){
        easylink_config = [[EASYLINK alloc]initForDebug:YES WithDelegate:self];
    }
    if( self.foundModules == nil)
        self.foundModules = [[NSMutableArray alloc]initWithCapacity:10];
    
    deviceIPConfig = [[NSMutableDictionary alloc] initWithCapacity:5];
    targetSsid = [NSData data];
    easylinkMode = EASYLINK_AWS;
    //startEasyLinkBTN.titleLabel.text = [[NSString alloc] initWithFormat:@"Start %@ Mode", easylinkModeFieldText[easylinkMode]];

    //配置表格加边框
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGColorRef colorref = CGColorCreate(colorSpace,(CGFloat[]){ 0, 122.0/255, 1, 1 });
    
    [configTableView.layer setCornerRadius:8.0];
    [configTableView.layer setBorderWidth:1.5];
    [configTableView.layer setBorderColor:colorref];
    CGColorRelease (colorref);
    CGColorSpaceRelease(colorSpace);
    self.automaticallyAdjustsScrollViewInsets = NO;
        
    // wifi notification when changed.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wifiStatusChanged:) name:kReachabilityChangedNotification object:nil];
    
    wifiReachability = [Reachability reachabilityForLocalWiFi];  //监测Wi-Fi连接状态
	[wifiReachability startNotifier];
    
    NetworkStatus netStatus = [wifiReachability currentReachabilityStatus];
    if ( netStatus != NotReachable ) {
        [deviceIPConfig setObject:@YES forKey:@"DHCP"];
        [deviceIPConfig setObject:[EASYLINK getIPAddress] forKey:@"IP"];
        [deviceIPConfig setObject:[EASYLINK getNetMask] forKey:@"NetMask"];
        [deviceIPConfig setObject:[EASYLINK getGatewayAddress] forKey:@"GateWay"];
        [deviceIPConfig setObject:[EASYLINK getGatewayAddress] forKey:@"DnsServer"];
    }
    
    [self updateDeviceCountLable];
    
    // stoping the process in app backgroud state
    NSLog(@"regisister notificationcenter");
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appEnterInforground:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    /*Update IP config cell*/
    [ipAddress setUserInteractionEnabled:NO];
    if(ipAddress != nil){
        if([[deviceIPConfig objectForKey:@"DHCP"] boolValue] == YES)
            [ipAddress setText:@"Automatic"];
        else
            [ipAddress setText:[deviceIPConfig objectForKey:@"IP"]];
    }
    if(easylinkModeField != nil){
        [easylinkModeField setText:easylinkModeFieldText[easylinkMode]];
    }
    
    [startEasyLinkBTN setTitle:[[NSString alloc] initWithFormat:@"Start %@ Mode", easylinkModeFieldText[easylinkMode]]
                      forState:UIControlStateNormal];
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated{
    if([self.navigationController.viewControllers indexOfObject:self] == NSNotFound){
        [easylink_config unInit];
        easylink_config = nil;
        self.foundModules = nil;
    }
    
    // Retain the UI access for the user.
    [super viewWillDisappear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    CGRect appFrame = [ UIScreen mainScreen ].applicationFrame;
    float contentWidth = appFrame.size.width;
    float contentHeight = appFrame.size.height - self.navigationController.navigationBar.frame.size.height;
    NSUInteger count = [foundModules count];
    if (count != 0)
        [bgView setContentSize:CGSizeMake(contentWidth, foundModuleTableView.frame.origin.y + 120 * [foundModules count])];
    else
        [bgView setContentSize:CGSizeMake(contentWidth, contentHeight)];
}

- (void)dealloc {
    NSLog(@"%s=>dealloc", __func__);
}

#pragma mark - New Devices Lable -

- (void)updateDeviceCountLable
{
    CGRect appFrame = [ UIScreen mainScreen ].applicationFrame;
    float contentWidth = appFrame.size.width;
    float contentHeight = appFrame.size.height - self.navigationController.navigationBar.frame.size.height;
    
    [newDeviceCount setText:[[NSString alloc]initWithFormat:@"(%lu)",(unsigned long)[foundModules count]]];
    NSUInteger count = [foundModules count];
    if (count != 0){
        NSLog(@"bounds.y = %f, %f", foundModuleTableView.bounds.origin.y, foundModuleTableView.frame.origin.y);
        [bgView setContentSize:CGSizeMake(contentWidth, foundModuleTableView.frame.origin.y + 120 * [foundModules count])];
    }
    else
        [bgView setContentSize:CGSizeMake(contentWidth, contentHeight)];

}

#pragma mark - TRASMITTING DATA -

/*
 This method begins configuration transmit
 In case of a failure the method throws an OSFailureException.
 */
-(void) sendAction{
    [easylink_config transmitSettings];
}

/*
 This method stop the sending of the configuration to the remote device
  In case of a failure the method throws an OSFailureException.
 */
-(void) stopAction{
    [easylink_config stopTransmitting];
}

/*
 This method start the transmitting the data to connected 
 AP. Nerwork validation is also done here. All exceptions from
 library is handled. 
 */
- (void)startTransmitting: (EasyLinkMode)mode {
    NSMutableDictionary *wlanConfig = [NSMutableDictionary dictionaryWithCapacity:20];

    if([targetSsid length] > 0) [wlanConfig setObject:targetSsid forKey:KEY_SSID];
    else [wlanConfig setObject:[ssidField.text dataUsingEncoding:NSUTF8StringEncoding] forKey:KEY_SSID];
    if([passwordField.text length] > 0) [wlanConfig setObject:passwordField.text forKey:KEY_PASSWORD];
    [wlanConfig setObject:[NSNumber numberWithBool:[[deviceIPConfig objectForKey:@"DHCP"] boolValue]] forKey:KEY_DHCP];
    
    if([[deviceIPConfig objectForKey:@"IP"] length] > 0)  [wlanConfig setObject:[deviceIPConfig objectForKey:@"IP"] forKey:KEY_IP];
    if([[deviceIPConfig objectForKey:@"NetMask"] length] > 0)  [wlanConfig setObject:[deviceIPConfig objectForKey:@"NetMask"] forKey:KEY_NETMASK];
    if([[deviceIPConfig objectForKey:@"GateWay"] length] > 0)  [wlanConfig setObject:[deviceIPConfig objectForKey:@"GateWay"] forKey:KEY_GATEWAY];
    if([[deviceIPConfig objectForKey:@"DnsServer"] length] > 0)  [wlanConfig setObject:[deviceIPConfig objectForKey:@"DnsServer"] forKey:KEY_DNS1];

    NSString *userInfo = [userInfoField.text length]? userInfoField.text : @"";

    const char *temp = [userInfo cStringUsingEncoding:NSUTF8StringEncoding];
    [easylink_config prepareEasyLink:wlanConfig info:[NSData dataWithBytes:temp length:strlen(temp)] mode:mode ];
    [self sendAction];
    targetSsid = [wlanConfig objectForKey:KEY_SSID];
}

- (IBAction)easyLinkV2ButtonAction:(UIButton*)button{
    
    if( easylinkMode == EASYLINK_SOFT_AP ) {
        [self easyLinkuAPButtonAction: button];
        return;
    }
    
    CATransition *animation = [CATransition animation];
    animation.delegate = (id)self;
    animation.duration = 0.5 ;
    animation.timingFunction = UIViewAnimationCurveEaseInOut;
    animation.type = kCATransitionFade;
    NSArray *easyLinkModeStrArray = [NSArray arrayWithObjects:@"EasyLink V1 sending...", @"EasyLink V2 sending...", @"EasyLink Plus sending...", @"EasyLink V2/Plus sending...", @"EasyLink AWS sending...", nil];
    

    
    NetworkStatus netStatus = [wifiReachability currentReachabilityStatus];
    if ( netStatus == NotReachable) {// No activity if no wifi
        alertView = [[UIAlertView alloc] initWithTitle:@"Connection Error" message:@"WiFi not available. Please check your WiFi connection" delegate:Nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alertView show];
        return;
    }
    
    if([ssidField.text length] == 0){
        alertView = [[UIAlertView alloc] initWithTitle:@"Wi-Fi Settings Error" message:@"SSID field is empry." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alertView show];
        return;
    }
    
    if([ssidField.text hasPrefix:@"EasyLink_"]){
        alertView = [[UIAlertView alloc] initWithTitle:@"Wi-Fi Settings Error" message:@"You should not using a \"EasyLink_XXXXXX\" as a Wi-Fi's ssid, this name is used internally by MXCHIP module." delegate:Nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alertView show];
        return;
    }
    
    [self startTransmitting: easylinkMode];
    
    /*Pop up a Easylink sending dialog*/
    easyLinkSendingView = [[CustomIOSAlertView alloc] init];
    
    UIView *alertContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 290, 300)];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 20, 260, 25)];
    title.text = [easyLinkModeStrArray objectAtIndex: easylink_config.mode];
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineSpacing = 5.0f;
    
    UIFont *font = [UIFont systemFontOfSize:14.0];
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:paragraphStyle,
                                                                    font,
                                                                    nil]
                                                           forKeys:[NSArray arrayWithObjects:NSParagraphStyleAttributeName,
                                                                    NSFontAttributeName,
                                                                    nil]];

    [easyLinkSendingView setContainerView:alertContentView];
    
    /*EasyLink button image*/
    UIImageView *easyLinkButtonView = [[UIImageView alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-45, 76, 90, 90)];
    easyLinkButtonView.image = [UIImage imageNamed:@"EasyLinkBtn" ];
    [alertContentView addSubview:easyLinkButtonView];
    
    /*EasyLink pres image*/
    UIImageView *buttonPressView = [[UIImageView alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2+80, 180, 120, 120)];
    buttonPressView.image = [UIImage imageNamed:@"EasyLinkBtnPress" ];
    [alertContentView addSubview:buttonPressView];
    
    [UIView animateWithDuration:0.5
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         [buttonPressView setFrame:CGRectMake(alertContentView.frame.size.width/2-15, 130, 40, 40)];
                     }
                     completion:^(BOOL finished){
                         ;
                     }];

    /*Add Line 1*/
    UILabel *content = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 15, 260, 100)];
    NSAttributedString *contentText =  [[NSAttributedString alloc] initWithString:@"Press EasyLink button on your device!"
                                                                       attributes:attributes];
    content.attributedText = contentText;
    content.numberOfLines = 1;
    [alertContentView addSubview:content];
    
    UIImageView *phoneImageView = [[UIImageView alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-100, 180, 200, 200)];
    [phoneImageView setImage:[UIImage imageNamed:@"EasyLinkSearching"]];
    [alertContentView addSubview:phoneImageView];
    [phoneImageView setContentMode:UIViewContentModeScaleAspectFit];
    alertContentView.clipsToBounds = true;
    
    PulsingHaloLayer *pulsingHalo = [PulsingHaloLayer layer];
    pulsingHalo.position = CGPointMake(alertContentView.frame.size.width/2, phoneImageView.center.y-25);
    [alertContentView.layer insertSublayer:pulsingHalo above:phoneImageView.layer];
    pulsingHalo.radius = 300;
    pulsingHalo.backgroundColor = [UIColor colorWithRed:0 green:122.0/255 blue:1.0 alpha:1.0].CGColor;
    
    
    [easyLinkSendingView setButtonTitles:[NSMutableArray arrayWithObjects:@"Stop", nil]];
    __weak EasyLinkMainViewController *_self = self;
    [easyLinkSendingView setOnButtonTouchUpInside:^(CustomIOSAlertView *customIOS7AlertView, int buttonIndex) {
        [_self stopAction];
        //[_imagePhoneView setImage:[UIImage imageNamed:@"EasyLinkPhone.png"]];
        NSLog(@"Block: Button at position %ld is clicked on alertView %ld.", (long)buttonIndex, (long)[customIOS7AlertView tag]);
        [customIOS7AlertView close];
    }];
    
    [easyLinkSendingView setUseMotionEffects:true];
    [easyLinkSendingView show];
    
}

- (IBAction)easyLinkuAPButtonAction:(UIButton*)button
{
    if([ssidField.text length] == 0){
        alertView = [[UIAlertView alloc] initWithTitle:@"Wi-Fi Settings Error" message:@"SSID field is empry." delegate:Nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alertView show];
        return;
    }
    
    if([ssidField.text hasPrefix:@"EasyLink_"]){
        alertView = [[UIAlertView alloc] initWithTitle:@"Wi-Fi Settings Error" message:@"You should not using a \"EasyLink_XXXXXX\" as a Wi-Fi's ssid, this name is used internally by MXCHIP module." delegate:Nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alertView show];
        return;
    }
    
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineSpacing = 5.0f;
    
    UIFont *font = [UIFont systemFontOfSize:14.0];
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:paragraphStyle,
                                                                    font,
                                                                    nil]
                                                           forKeys:[NSArray arrayWithObjects:NSParagraphStyleAttributeName,
                                                                    NSFontAttributeName,
                                                                    nil]];
    
    /*Pop up a Easylink sending dialog*/
    easyLinkUAPSendingView = [[CustomIOSAlertView alloc] init];
    
    UIScrollView *alertContentView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 290, 300)];
    
    alertContentView.tag = 0x1000;
    alertContentView.pagingEnabled = YES;
    alertContentView.userInteractionEnabled = false;
    alertContentView.showsHorizontalScrollIndicator = NO;
    alertContentView.contentSize = CGSizeMake(WIDTH_ALERT_VIEW * maxEasyLinkSoftPages, HEIGHT_ALERT_VIEW);
    
    [alertContentView scrollRectToVisible:CGRectMake(0, 0, WIDTH_ALERT_VIEW, HEIGHT_ALERT_VIEW) animated:YES];
    
    /* ======================================== uAP config Page 1 ===========================================*/
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-130 + ePage_StartEasyLink* WIDTH_ALERT_VIEW , 20, 260, 25)];
    title.text = @"Start EasyLink uAP mode...";
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    UIImageView *startEasyLinkView = [[UIImageView alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-145 + ePage_StartEasyLink * WIDTH_ALERT_VIEW, 45, 290, 255)];
    startEasyLinkView.image = [UIImage imageNamed:@"uAPPhase1.1" ];
    [alertContentView addSubview:startEasyLinkView];
    
    /*EasyLink pres image*/
    UIImageView *buttonPressView = [[UIImageView alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2+80, 180, 120, 120)];
    buttonPressView.image = [UIImage imageNamed:@"EasyLinkBtnPress" ];
    [alertContentView addSubview:buttonPressView];
    
    [UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         [buttonPressView setFrame:CGRectMake(alertContentView.frame.size.width/2-15, 130, 40, 40)];
                     } completion:^(BOOL finished){}];
    
    /*Add Line 1*/
    UILabel *content = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 15, 260, 100)];
    content.attributedText = [[NSAttributedString alloc] initWithString:@"Press EasyLink button on your device!"
                                                             attributes:attributes];
    [alertContentView addSubview:content];
    
    content = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 140, 260, 100)];
    content.numberOfLines = 2;
    content.attributedText = [[NSAttributedString alloc] initWithString:@"Wait until uAP is established on device!\r\n (RF led is turned on)"
                                                             attributes:attributes];
    [alertContentView addSubview:content];
    
    /* ======================================== uAP config Page 2 ===========================================*/
    title = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-130 + ePage_ConnectingToModule * WIDTH_ALERT_VIEW, 20, 260, 25)];
    title.text = @"Connecting to module...";
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    UIImageView *homeButtonView = [[UIImageView alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-145 + ePage_ConnectingToModule * WIDTH_ALERT_VIEW, 45, 290, 255)];
    homeButtonView.image = [UIImage imageNamed:@"uAPPhase1.2" ];
    [alertContentView addSubview:homeButtonView];
    
    content = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-130 + ePage_ConnectingToModule * WIDTH_ALERT_VIEW, 45, 260, 25)];
    content.attributedText = [[NSAttributedString alloc] initWithString:@"Press Next to Wi-Fi Setting!"
                                                             attributes:attributes];;
    [alertContentView addSubview:content];
    
    content = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-130 + ePage_ConnectingToModule * WIDTH_ALERT_VIEW, 150, 260, 50)];
    content.numberOfLines = 2;
    content.attributedText = [[NSAttributedString alloc] initWithString:@"Select network: EasyLink_XXXXXX."
                                                             attributes:attributes];
    [alertContentView addSubview:content];
    
    /* ======================================== uAP config Page 3 ===========================================*/
    title = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-130 + ePage_SendingConfig * WIDTH_ALERT_VIEW, 20, 260, 25)];
    title.text = @"Transmitting Data...";
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    UIImageView *sendingConfigView = [[UIImageView alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-145 + ePage_SendingConfig * WIDTH_ALERT_VIEW, 45, 290, 255)];
    sendingConfigView.image = [UIImage imageNamed:@"uAPPhase2" ];
    [alertContentView addSubview:sendingConfigView];
    
    /* ======================================== uAP config Page 4 ===========================================*/
    title = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-130 + ePage_ConnectingToTargetWlan * WIDTH_ALERT_VIEW, 20, 260, 25)];
    title.text = [[NSString alloc] initWithFormat: @"Reconnect to %@...", [[NSString alloc]initWithData:targetSsid encoding:NSUTF8StringEncoding] ] ;
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    UIImageView *connectingToTargetWlanView = [[UIImageView alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-145 + ePage_ConnectingToTargetWlan * WIDTH_ALERT_VIEW, 45, 290, 255)];
    connectingToTargetWlanView.image = [UIImage imageNamed:@"uAPPhase3" ];
    [alertContentView addSubview:connectingToTargetWlanView];
    
    /* ======================================== uAP config Page 5 ===========================================*/
    title = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW/2-130 + ePage_ScanNewDevice * WIDTH_ALERT_VIEW, 20, 260, 25)];
    title.text = @"Scaning for new device...";
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    UIView *pulsingHaloView = [[UIView alloc] initWithFrame:CGRectMake(WIDTH_ALERT_VIEW * ePage_ScanNewDevice,0, 290, 300)];
    pulsingHaloView.clipsToBounds = YES;
    
    UIImageView *phoneImageView = [[UIImageView alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 60, 260, 260)];
    [phoneImageView setImage:[UIImage imageNamed:@"EasyLinkSearching"]];
    [pulsingHaloView addSubview:phoneImageView];
    [phoneImageView setContentMode:UIViewContentModeScaleAspectFit];

    PulsingHaloLayer *pulsingHalo = [PulsingHaloLayer layer];
    pulsingHalo.position = CGPointMake(phoneImageView.center.x, phoneImageView.center.y-25);
    [pulsingHaloView.layer insertSublayer:pulsingHalo above:phoneImageView.layer];
    pulsingHalo.radius = 300;
    pulsingHalo.backgroundColor = [UIColor colorWithRed:0 green:122.0/255 blue:1.0 alpha:1.0].CGColor;
    [alertContentView addSubview:pulsingHaloView];

    /* ==================================================================================================*/
    
    [easyLinkUAPSendingView setContainerView:alertContentView];
    
    [easyLinkUAPSendingView setButtonTitles:[NSMutableArray arrayWithObjects:@"Stop", @"Previous", @"Next", nil]];
    
    __weak EasyLinkMainViewController *_self = self;
    
    [easyLinkUAPSendingView setOnButtonTouchUpInside:^(CustomIOSAlertView *customIOS7AlertView, int buttonIndex) {
        NSUInteger currentPage;
        UIScrollView *containerView = (UIScrollView *)customIOS7AlertView.containerView;
        currentPage = containerView.contentOffset.x / 290;
        if(buttonIndex == 0){
            [_self stopAction];
            [customIOS7AlertView close];
        }else if(buttonIndex == 1){
            [containerView scrollRectToVisible:CGRectMake( --currentPage * 290, 0, 290, 300) animated:YES];
        }else if(buttonIndex == 2){
            if (currentPage == 1){
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=WIFI"]];
            }
            else if(currentPage == 2) {
                return;
            }
            else {
                [containerView scrollRectToVisible:CGRectMake( ++currentPage * 290, 0, 290, 300) animated:YES];
            }
        }
        
        if(buttonIndex == 1 && currentPage == 1){
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"prefs:root=WIFI"]];
        }
        
        if(currentPage == 0) {// This is the first page
            [(UIButton *)[customIOS7AlertView.dialogView viewWithTag: 1] setEnabled:NO];
        }else{
            [(UIButton *)[customIOS7AlertView.dialogView viewWithTag: 1] setEnabled:YES];
        };
        
        [(UIButton *)[customIOS7AlertView.dialogView viewWithTag: 2] setEnabled:YES];

        //[_imagePhoneView setImage:[UIImage imageNamed:@"EasyLinkPhone.png"]];
        NSLog(@"Block: Button at position %ld is clicked on alertView %ld.", (long)buttonIndex, (long)[customIOS7AlertView tag]);
        
    }];
    
    [easyLinkUAPSendingView setUseMotionEffects:true];
    [easyLinkUAPSendingView show];
    
    
    if([[EASYLINK ssidForConnectedNetwork] hasPrefix:@"EasyLink_"]){
        [(UIScrollView *)easyLinkUAPSendingView.containerView scrollRectToVisible:CGRectMake( 2 * 290, 0, 290, 300) animated:YES];
        [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 3] setEnabled:NO];
        
    }else{
        [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 1] setEnabled:NO];
    }
    
    [self startTransmitting: EASYLINK_SOFT_AP];
}


#pragma mark - UITableview Delegate -

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
        return 1;

}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell *cell;
    newModuleTableViewCell *newModuleCell;
    NSString *newModuleCellIdentifier;
    
    if(tableView == configTableView){
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"APInfo"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [cell setBackgroundColor:[UIColor colorWithRed:0.100 green:0.478 blue:1.000 alpha:0.1]];
        cell = [self prepareCell:cell atIndexPath:indexPath];
        return cell;
    }
    else{
        if( [[[foundModules objectAtIndex: indexPath.row] objectForKey:@"FTC"] boolValue] == NO ){
            newModuleCellIdentifier = @"New Module";
            
        }
        else{
            newModuleCellIdentifier = @"New Module FTC";
        }
        
        newModuleCell = (newModuleTableViewCell *)[tableView dequeueReusableCellWithIdentifier:newModuleCellIdentifier];
        if(newModuleCell == nil)
            newModuleCell = [[newModuleTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:newModuleCellIdentifier];
        newModuleCell.moduleInfo = [foundModules objectAtIndex: indexPath.row];
        [newModuleCell setDelegate:self];
        return newModuleCell;
    }
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    newModuleTableViewCell *newModuleCell = (newModuleTableViewCell *)cell;
    if(tableView == foundModuleTableView){
        newModuleCell.delegate = nil;
    }
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
#if 0
    if(tableView == configTableView && indexPath.row == IP_ADDRESS_ROW){
        [self performSegueWithIdentifier:@"IP config" sender:configTableView];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
#endif
    if(tableView == configTableView && indexPath.row == EASYLINK_MODE_ROW){
        [self performSegueWithIdentifier:@"EasyLink Mode" sender:configTableView];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    if(tableView == configTableView)
        return 4;
    else
        return [self.foundModules count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return nil;
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger row = [indexPath row];
    NSMutableDictionary *deleteModule = nil;
    deleteModule = [foundModules objectAtIndex:row];
    [easylink_config closeFTCClient: [deleteModule objectForKey:@"client"]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return NO;
}

#pragma mark - UITextfiled delegate -

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - EasyLink delegate -

- (void)onFound:(NSNumber *)client withName:(NSString *)name mataData: (NSDictionary *)mataDataDict
{
    NSLog(@"Found new device using bonjour==================");
    NSIndexPath* indexPath;
    NSMutableDictionary *foundModule = [NSMutableDictionary dictionaryWithDictionary:mataDataDict];
    NSMutableDictionary *updateSettings;
    NSData *tempData;
    NSUInteger index = 0xFF;
    
    [foundModule setValue:name forKey:@"N"];
    [foundModule setObject:@NO forKey:@"FTC"];
    
    tempData = [mataDataDict objectForKey:@"FW"];
    if( tempData != nil ) [foundModule setValue:[[NSString alloc] initWithData:tempData encoding:NSUTF8StringEncoding] forKey:@"FW"];
    
    tempData = [mataDataDict objectForKey:@"HD"];
    if( tempData != nil ) [foundModule setValue:[[NSString alloc] initWithData:tempData encoding:NSUTF8StringEncoding] forKey:@"HD"];
    
    tempData = [mataDataDict objectForKey:@"PO"];
    if( tempData != nil ) [foundModule setValue:[[NSString alloc] initWithData:tempData encoding:NSUTF8StringEncoding] forKey:@"PO"];
    
    tempData = [mataDataDict objectForKey:@"RF"];
    if( tempData != nil ) [foundModule setValue:[[NSString alloc] initWithData:tempData encoding:NSUTF8StringEncoding] forKey:@"RF"];
    
    [foundModule setValue:client forKey:@"client"];
    updateSettings = [NSMutableDictionary dictionaryWithCapacity:10];
    [foundModule setValue:updateSettings forKey:@"update"];
    
    /* Device already existed */
    for( NSDictionary *object in self.foundModules){
        if ([[object objectForKey:@"N"] isEqualToString:[foundModule objectForKey:@"N"]] ){
            index = [self.foundModules indexOfObject:object];
            [self.foundModules replaceObjectAtIndex:index withObject:object];
            indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [foundModuleTableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                                        withRowAnimation:UITableViewRowAnimationLeft];
        }
    }
    
    /* Find a new device */
    if (index == 0xFF){
        [foundModule setObject: [NSNumber numberWithInteger:arc4random()] forKey:@"tag"];
        [self.foundModules addObject:foundModule];
        indexPath = [NSIndexPath indexPathForRow:[self.foundModules indexOfObject:foundModule] inSection:0];
        
        [foundModuleTableView insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                                    withRowAnimation:UITableViewRowAnimationRight];
    }
    
    
    /*Correct AP info input, save to file*/
    if([[apInforRecord objectForKey:ssidField.text] isEqualToString:passwordField.text] == NO){
        [apInforRecord setObject:passwordField.text forKey:ssidField.text];
        [apInforRecord writeToFile:apInforRecordFile atomically:YES];
    }
    
    [easyLinkSendingView close];
    [easyLinkUAPSendingView close];
    [self updateDeviceCountLable];
    [self stopAction];
    
    if(otaAlertView != nil){
        [otaAlertView close];
        otaAlertView = nil;
    }
}


- (void)onFoundByFTC:(NSNumber *)ftcClientTag withConfiguration: (NSDictionary *)configDict;
{
    NSIndexPath* indexPath;
    NSMutableDictionary *foundModule = [NSMutableDictionary dictionaryWithDictionary:configDict];
    NSMutableDictionary *updateSettings;
    BOOL reloadTable = NO;
    NSUInteger reloadIndex;
    
    [foundModule setValue:ftcClientTag forKey:@"client"];
    updateSettings = [NSMutableDictionary dictionaryWithCapacity:10];
    [foundModule setValue:updateSettings forKey:@"update"];
    [foundModule setObject:@YES forKey:@"FTC"];
    [foundModule setObject: [NSNumber numberWithInteger:arc4random()] forKey:@"tag"];
    
    /*Replace an old device*/
    for( NSDictionary *object in self.foundModules){
        if ([[object objectForKey:@"N"] isEqualToString:[foundModule objectForKey:@"N"]] ){
            if( [ftcClientTag isEqualToNumber: [object objectForKey:@"client"] ]== NO )
                /* This is a same device using a new connection, disconnect the old one */
                [easylink_config closeFTCClient:[object objectForKey:@"client"]];
            else{
                reloadTable = YES;
                reloadIndex = [self.foundModules indexOfObject:object];
                [foundModule setObject:[object objectForKey:@"tag"] forKey:@"tag"];
            }
            
        }
    }

    if (reloadTable == YES) {
        indexPath = [NSIndexPath indexPathForRow:[self.foundModules indexOfObject:foundModule] inSection:0];
        [self.foundModules replaceObjectAtIndex:reloadIndex withObject:foundModule];
        [foundModuleTableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                                    withRowAnimation:UITableViewRowAnimationNone];
    }
    else{
        [self.foundModules addObject:foundModule];
        indexPath = [NSIndexPath indexPathForRow:[self.foundModules indexOfObject:foundModule] inSection:0];
        [foundModuleTableView insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                                    withRowAnimation:UITableViewRowAnimationRight];
    }
    
    
    /*Correct AP info input, save to file*/
    if([[apInforRecord objectForKey:ssidField.text] isEqualToString:passwordField.text] == NO){
        [apInforRecord setObject:passwordField.text forKey:ssidField.text];
        [apInforRecord writeToFile:apInforRecordFile atomically:YES];
    }
    
    [easyLinkSendingView close];

    [easyLinkUAPSendingView close];
    [self updateDeviceCountLable];
    [self stopAction];
    
    if(otaAlertView != nil){
        [otaAlertView close];
        otaAlertView = nil;
    }
}

- (void)onDisconnectFromFTC:(NSNumber *)ftcClientTag withError:(bool)err;

{
    NSIndexPath* indexPath;
    NSDictionary *disconnectedClient;
    NSLog(@"View: Disconnect from FTC");

    for( NSDictionary *object in self.foundModules){
        if ([[object objectForKey:@"client"] isEqualToNumber:ftcClientTag] ){
            indexPath = [NSIndexPath indexPathForRow:[self.foundModules indexOfObject:object] inSection:0];
            disconnectedClient = object;
            break;
        }
    }
    
    if(disconnectedClient != nil){
        [self.foundModules removeObject: disconnectedClient ];
        [foundModuleTableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                                    withRowAnimation:UITableViewRowAnimationAutomatic];
    }

    if(customAlertView != nil){
        [customAlertView close];
        customAlertView = nil;
    }
    
    
    if(otaAlertView != nil){
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByCharWrapping;
        paragraphStyle.alignment = NSTextAlignmentCenter;
        paragraphStyle.lineSpacing = 5.0f;
        NSDictionary *attributes = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:paragraphStyle,
                                                                        nil]
                                                               forKeys:[NSArray arrayWithObjects:NSParagraphStyleAttributeName,
                                                                        nil]];
        NSAttributedString *contentText =  [[NSAttributedString alloc] initWithString:@"OTA processing..."
                                                                           attributes:attributes];
        
        for(UIView *object in [[otaAlertView containerView] subviews]){
            if(object.tag == 0x1001){
                [(UILabel *)object setAttributedText:contentText];
                [(UILabel *)object setNumberOfLines: 2];
                break;
            }
        }
    }
    
    [self updateDeviceCountLable];

    [self.navigationController popToViewController:self animated:YES];
}

- (void)onEasyLinkSoftApStageChanged: (EasyLinkSoftApStage)stage
{
    NSString *message;
    UIAlertView *wrongWlanAlertView;
    
    switch (stage) {
        case eState_connect_to_uap:
            [(UIScrollView *)easyLinkUAPSendingView.containerView scrollRectToVisible:CGRectMake( 2 * 290, 0, 290, 300) animated:YES];
            [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 2] setEnabled:NO];
            [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 1] setEnabled:NO];
            break;
        case eState_configured_by_uap:
            [(UIScrollView *)easyLinkUAPSendingView.containerView scrollRectToVisible:CGRectMake( 3 * 290, 0, 290, 300) animated:YES];
            [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 2] setEnabled:NO];
            [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 1] setEnabled:NO];
            break;
        case eState_connect_to_target_wlan:
            [(UIScrollView *)easyLinkUAPSendingView.containerView scrollRectToVisible:CGRectMake( 4 * 290, 0, 290, 300) animated:YES];
            [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 2] setEnabled:NO];
            [(UIButton *)[easyLinkUAPSendingView.dialogView viewWithTag: 1] setEnabled:NO];
            break;
        case eState_connect_to_wrong_wlan:
            message =  [[NSString alloc] initWithFormat:@"Current connected wlan is %@. You should connect to target wlan %@ manually.",[EASYLINK ssidForConnectedNetwork],  ssidField.text];
            wrongWlanAlertView = [[UIAlertView alloc] initWithTitle:@"Wrong Wlan Connected" message:message delegate:self cancelButtonTitle:@"Dismiss" otherButtonTitles: nil];
            [wrongWlanAlertView show];
            break;
        default:
            break;
    }
}

#pragma mark - EasyLinkFTCTableViewController delegate-

- (void)onConfigured:(NSMutableDictionary *)configData
{    
    customAlertView = [[CustomIOSAlertView alloc] init];
    
    UIView *alertContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 290, 140)];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 20, 260, 25)];
    title.text = @"Please wait...";
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    UILabel *content = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 50, 260, 25)];
    content.text = @"Setting Wi-Fi module";
    content.font= [UIFont systemFontOfSize:16.0];
    content.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:content];
    
    CGRect frame = CGRectMake(0, 0, 50, 50);
    UIActivityIndicatorView* spinner = [[UIActivityIndicatorView alloc] initWithFrame:frame];
    [spinner startAnimating];
    spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    [spinner sizeToFit];
    [spinner setColor: [UIColor colorWithRed:0 green:122.0/255 blue:1 alpha:1]];
    spinner.frame = CGRectMake(alertContentView.frame.size.width/2-17, 80, 50, 50);
    [alertContentView addSubview:spinner];
    [customAlertView setContainerView:alertContentView];
    

    [customAlertView setButtonTitles:[NSMutableArray arrayWithCapacity:3]];

    [customAlertView setUseMotionEffects:true];
    [customAlertView show];
    
    [easylink_config configFTCClient:[configData objectForKey:@"client"]
                   withConfiguration:[configData objectForKey:@"update"] ];
}

- (void)onIgnored:(NSMutableDictionary *)configData
{
    if( [[configData objectForKey:@"FTC"] boolValue] == YES ){
        [self onConfigured: configData];
        [easylink_config closeFTCClient: [configData objectForKey:@"client"]];
    }
    else{
        [self onDisconnectFromFTC:[configData objectForKey:@"client"] withError:NO];
    }
}

#pragma mark - EasyLinkOTATableViewController delegate-

- (void)onStartOTA:(NSString *)otaFilePath toFTCClient:(NSNumber *)client
{
    otaAlertView = [[CustomIOSAlertView alloc] init];
    
    UIView *alertContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 290, 170)];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 20, 260, 25)];
    title.text = @"Please wait...";
    title.font= [UIFont boldSystemFontOfSize:19.0];
    title.textAlignment = NSTextAlignmentCenter;
    [alertContentView addSubview:title];
    
    UILabel *content = [[UILabel alloc] initWithFrame:CGRectMake(alertContentView.frame.size.width/2-130, 65, 260, 25)];
    
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = NSLineBreakByCharWrapping;
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineSpacing = 5.0f;
    NSDictionary *attributes = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:paragraphStyle,
                                                                    nil]
                                                           forKeys:[NSArray arrayWithObjects:NSParagraphStyleAttributeName,
                                                                    nil]];
    NSAttributedString *contentText =  [[NSAttributedString alloc] initWithString:@"Sending OTA data to module..."
                                                                       attributes:attributes];
    
    content.attributedText = contentText;
    content.numberOfLines = 2;
    [content setTag:0x1001];
    [alertContentView addSubview:content];
    
    CGRect frame = CGRectMake(0, 0, 50, 50);
    UIActivityIndicatorView* spinner = [[UIActivityIndicatorView alloc] initWithFrame:frame];
    [spinner startAnimating];
    spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    [spinner sizeToFit];
    [spinner setColor: [UIColor colorWithRed:0 green:122.0/255 blue:1 alpha:1]];
    spinner.frame = CGRectMake(alertContentView.frame.size.width/2-17, 110, 50, 50);
    [alertContentView addSubview:spinner];
    [otaAlertView setContainerView:alertContentView];
    
    [otaAlertView setButtonTitles:[NSMutableArray arrayWithObjects:@"Cancel",nil]];
    __weak EASYLINK *_easylink_config = easylink_config;
    __weak CustomIOSAlertView *_otaAlertView = otaAlertView;
    [otaAlertView setOnButtonTouchUpInside:^(CustomIOSAlertView *customIOS7AlertView, int buttonIndex) {
      //  self.requestsManager = nil;
    [_easylink_config closeFTCClient: client];
      //  [self.navigationController popToViewController:[self.navigationController.viewControllers objectAtIndex:2] animated:YES];
        NSLog(@"Block: Button at position %ld is clicked on alertView %ld.", (long)buttonIndex, (long)[customIOS7AlertView tag]);
        [_otaAlertView close];
    }];
    
    [otaAlertView setUseMotionEffects:true];
    [otaAlertView show];
    
    [easylink_config otaFTCClient:client withOTAData: [NSData dataWithContentsOfFile:otaFilePath]];
}
#pragma mark - Private Methods -

/* 
 Prepare a cell that is created with respect to the indexpath 
 @param cell is an object of UITableViewcell which is newly created 
 @param indexpath  is respective indexpath of the cell of the row. 
 */
-(UITableViewCell *) prepareCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    CGRect tableFrame = configTableView.frame;
    float textWidth = tableFrame.size.width - CELL_IPHONE_FIELD_X;
    
    if ( indexPath.row == SSID_ROW ){/// this is SSID row
        NSString *SSID = [EASYLINK ssidForConnectedNetwork];
        targetSsid = [EASYLINK ssidDataForConnectedNetwork];
        if(SSID == nil) SSID = @"";
        
        ssidField = [[UITextField alloc] initWithFrame:CGRectMake(CELL_IPHONE_FIELD_X,
                                                                  CELL_iPHONE_FIELD_Y,
                                                                  textWidth,
                                                                  CELL_iPHONE_FIELD_HEIGHT)];
        [ssidField setDelegate:self];
        [ssidField setClearButtonMode:UITextFieldViewModeNever];
        [ssidField setPlaceholder:@"SSID"];
        [ssidField setBackgroundColor:[UIColor clearColor]];
        [ssidField setReturnKeyType:UIReturnKeyDone];
        [ssidField setText:SSID];
        
        [cell addSubview:ssidField];
        
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
        cell.textLabel.text = @"SSID";
    }else if(indexPath.row == PASSWORD_ROW ){// this is password field
        passwordField = [[UITextField alloc] initWithFrame:CGRectMake(CELL_IPHONE_FIELD_X,
                                                                      CELL_iPHONE_FIELD_Y,
                                                                      textWidth,
                                                                      CELL_iPHONE_FIELD_HEIGHT)];
        [passwordField setDelegate:self];
        [passwordField setClearButtonMode:UITextFieldViewModeNever];
        [passwordField setPlaceholder:@"Password"];
        [passwordField setReturnKeyType:UIReturnKeyDone];
        [passwordField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
        [passwordField setAutocorrectionType:UITextAutocorrectionTypeNo];
        [passwordField setBackgroundColor:[UIColor clearColor]];
        [cell addSubview:passwordField];
        NSString *password = [apInforRecord objectForKey:ssidField.text];
        if(password == nil) password = @"";
        [passwordField setText:password];

        
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
        cell.textLabel.text = @"Password";
    }
    else if ( indexPath.row == USER_INFO_ROW){
        /// this is Gateway Address field
        userInfoField = [[UITextField alloc] initWithFrame:CGRectMake(CELL_IPHONE_FIELD_X,
                                                                       CELL_iPHONE_FIELD_Y,
                                                                       textWidth,
                                                                       CELL_iPHONE_FIELD_HEIGHT)];
        [userInfoField setDelegate:self];
        [userInfoField setClearButtonMode:UITextFieldViewModeNever];
        [userInfoField setPlaceholder:@"Authenticator(Optional)"];
        [userInfoField setReturnKeyType:UIReturnKeyDone];
        [userInfoField setBackgroundColor:[UIColor clearColor]];
        
        [cell addSubview:userInfoField];
        
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
        cell.textLabel.text = @"Extra Data";
    }
#if 0
    else if ( indexPath.row == IP_ADDRESS_ROW){
        /// this is Gateway Address field
        ipAddress = [[UITextField alloc] initWithFrame:CGRectMake(CELL_IPHONE_FIELD_X,
                                                                  CELL_iPHONE_FIELD_Y,
                                                                  textWidth,
                                                                  CELL_iPHONE_FIELD_HEIGHT)];
        [ipAddress setDelegate:self];
        [ipAddress setClearButtonMode:UITextFieldViewModeNever];
        [ipAddress setPlaceholder:@"Auto"];
        [ipAddress setReturnKeyType:UIReturnKeyDone];
        [ipAddress setBackgroundColor:[UIColor clearColor]];
        [ipAddress setUserInteractionEnabled:NO];

        if([[deviceIPConfig objectForKey:@"DHCP"] boolValue] == YES)
            [ipAddress setText:@"Automatic"];
        else
            [ipAddress setText:[deviceIPConfig objectForKey:@"IP"]];

        [cell addSubview:ipAddress];
        
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
        cell.textLabel.text = @"IP Address";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
#endif
    else if ( indexPath.row == EASYLINK_MODE_ROW){
        /// this is Gateway Address field
        easylinkModeField = [[UITextField alloc] initWithFrame:CGRectMake(CELL_IPHONE_FIELD_X,
                                                                  CELL_iPHONE_FIELD_Y,
                                                                  textWidth,
                                                                  CELL_iPHONE_FIELD_HEIGHT)];
        [easylinkModeField setDelegate:self];
        [easylinkModeField setClearButtonMode:UITextFieldViewModeNever];
        [easylinkModeField setPlaceholder:@"EasyLink AWS"];
        [easylinkModeField setReturnKeyType:UIReturnKeyDone];
        [easylinkModeField setBackgroundColor:[UIColor clearColor]];
        [easylinkModeField setUserInteractionEnabled:NO];
        
        [easylinkModeField setText:easylinkModeFieldText[easylinkMode]];
        
        [cell addSubview:easylinkModeField];
        
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
        cell.textLabel.text = @"Mode";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
    return cell;
}


/* 
 Notification method handler when app enter in forground
 @param the fired notification object
 */
- (void)appEnterInforground:(NSNotification*)notification{
    NetworkStatus netStatus = [wifiReachability currentReachabilityStatus];
    
    if ( netStatus != NotReachable && ![[EASYLINK ssidForConnectedNetwork] hasPrefix:@"EasyLink_"] && easylink_config.softAPSending == false) {
        ssidField.text = [EASYLINK ssidForConnectedNetwork];
        targetSsid = [EASYLINK ssidDataForConnectedNetwork];
        ipAddress.text = @"Automatic";
        ssidField.userInteractionEnabled = NO;
        
        NSString *password = [apInforRecord objectForKey:ssidField.text];
        if(password == nil) password = @"";
        [passwordField setText: password];
        
        [deviceIPConfig setObject:@YES forKey:@"DHCP"];
        [deviceIPConfig setObject:[EASYLINK getIPAddress] forKey:@"IP"];
        [deviceIPConfig setObject:[EASYLINK getNetMask] forKey:@"NetMask"];
        [deviceIPConfig setObject:[EASYLINK getGatewayAddress] forKey:@"GateWay"];
        [deviceIPConfig setObject:[EASYLINK getGatewayAddress] forKey:@"DnsServer"];
    }
}

/*
 Notification method handler when status of wifi changes
 @param the fired notification object
 */
- (void)wifiStatusChanged:(NSNotification*)notification{
    NetworkStatus netStatus = [wifiReachability currentReachabilityStatus];
    
    /* iOS has connect to a wireless router */
    if ( netStatus != NotReachable && ![[EASYLINK ssidForConnectedNetwork] hasPrefix:@"EasyLink_"] && easylink_config.softAPSending == false) {
        ssidField.text = [EASYLINK ssidForConnectedNetwork];
        targetSsid = [EASYLINK ssidDataForConnectedNetwork];
        NSString *password = [apInforRecord objectForKey:ssidField.text];
        if(password == nil) password = @"";
        [passwordField setText:password];
        
        [deviceIPConfig setObject:@YES forKey:@"DHCP"];
        [deviceIPConfig setObject:[EASYLINK getIPAddress] forKey:@"IP"];
        [deviceIPConfig setObject:[EASYLINK getNetMask] forKey:@"NetMask"];
        [deviceIPConfig setObject:[EASYLINK getGatewayAddress] forKey:@"GateWay"];
        [deviceIPConfig setObject:[EASYLINK getGatewayAddress] forKey:@"DnsServer"];
    }
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"IP config"]) {
        [[segue destinationViewController] setDeviceIPConfig: deviceIPConfig];
    }else if ([[segue identifier] isEqualToString:@"EasyLink Mode"]) {
        [[segue destinationViewController] setMode: &easylinkMode];
    }else if ([[segue identifier] isEqualToString:@"First Time Configuration"]){
        for( NSMutableDictionary *object in foundModules){
            if([[object objectForKey:@"tag"] isEqualToNumber:[NSNumber numberWithLong:[sender tag] ]]){
                [object removeObjectsForKeys:[NSArray arrayWithObjects:@"FW", @"PO", @"HD", nil]];
                [[segue destinationViewController] setConfigData:object];
                [(EasyLinkFTCTableViewController *)[segue destinationViewController] setDelegate:self];
                break;
            }
        }
    }else if ([[segue identifier] isEqualToString:@"OTA"]){
        for( NSMutableDictionary *object in foundModules){
            if([[object objectForKey:@"tag"] isEqualToNumber:[NSNumber numberWithLong:[sender tag] ]]){
                [[segue destinationViewController] setProtocol:[object objectForKey:@"PO"]];
                [[segue destinationViewController] setClient:[object objectForKey:@"client"]];
                [[segue destinationViewController] setHardwareVersion: [object objectForKey:@"HD"]];
                [[segue destinationViewController] setFirmwareVersion: [object objectForKey:@"FW"]];
                [[segue destinationViewController] setRfVersion: [object objectForKey:@"RF"]];
                [[segue destinationViewController] setDelegate:self];
                break;
            }
        }
    }
}


@end
