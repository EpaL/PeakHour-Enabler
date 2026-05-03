//
//  ProcessInformation_Objc.h
//  PeakHour Enabler
//
//  Created by Edward Lawford on 29/03/2015.
//  Copyright (c) 2015 Edward Lawford. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ProcessInformation_Objc : NSObject

- (NSArray*)getBSDProcessList;
- (NSDictionary *)infoForPID:(pid_t)pid;

@end
