//
//  NetworkInformation_Objc.h
//  PeakHour Enabler
//
//  Created by Edward Lawford on 28/03/2015.
//  Copyright (c) 2015 Edward Lawford. All rights reserved.
//

#import <Foundation/Foundation.h>

#define NETWORKINFO_IPADDRESS @"ipAddress"
#define NETWORKINFO_SUBNETMASK @"subnetMask"
#define NETWORKINFO_SUBNETBITS @"subnetBits"
#define NETWORKINFO_NETADDRESS @"netAddress"
#define NETWORKINFO_INTERFACENAME @"interfaceName"

@interface NetworkInformation_Objc : NSObject

+ (NSDictionary *)getActiveNetworkInterfaceInfo_ObjC;

@end
