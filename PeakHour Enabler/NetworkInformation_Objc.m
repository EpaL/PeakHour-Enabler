//
//  NetworkInformation_Objc.m
//  PeakHour Enabler
//
//  Created by Edward Lawford on 28/03/2015.
//  Copyright (c) 2015 Edward Lawford. All rights reserved.
//

#import "NetworkInformation_Objc.h"

#import <SystemConfiguration/SCDynamicStore.h>
#import <arpa/inet.h>

@implementation NetworkInformation_Objc

/**
 *  Returns the IP address and subnet mask of the current, active network
 * interface.
 *
 *  @return An NSDictionary containing the IP address and subnet mask of the
 * active interface.
 */
+ (NSDictionary *)getActiveNetworkInterfaceInfo_ObjC {
  // Default result returned whenever the active interface can't be determined.
  NSDictionary *result = @{
    NETWORKINFO_IPADDRESS : @"",
    NETWORKINFO_SUBNETMASK : @"",
    NETWORKINFO_SUBNETBITS : @0,
    NETWORKINFO_NETADDRESS : @"",
    NETWORKINFO_INTERFACENAME : @""
  };

  SCDynamicStoreRef storeRef = SCDynamicStoreCreate(
      NULL, (CFStringRef) @"FindCurrentInterfaceIpMac", NULL, NULL);
  if (storeRef == NULL) {
    return result;
  }

  CFPropertyListRef global =
      SCDynamicStoreCopyValue(storeRef, CFSTR("State:/Network/Global/IPv4"));
  id primaryInterface =
      global ? [(__bridge NSDictionary *)global valueForKey:@"PrimaryInterface"] : nil;

  CFPropertyListRef ipv4 = NULL;
  if ([primaryInterface isKindOfClass:[NSString class]]) {
    NSString *interfaceState = [NSString
        stringWithFormat:@"State:/Network/Interface/%@/IPv4", primaryInterface];
    ipv4 = SCDynamicStoreCopyValue(storeRef, (__bridge CFStringRef)interfaceState);
    NSDictionary *ipv4Dict = (__bridge NSDictionary *)ipv4;
    id ipArr = [ipv4Dict valueForKey:@"Addresses"];
    id netmaskArr = [ipv4Dict valueForKey:@"SubnetMasks"];

    // Guard against a missing or empty Addresses/SubnetMasks array; objectAtIndex:0
    // on an empty array would throw.
    if ([ipArr isKindOfClass:[NSArray class]] && [ipArr count] > 0 &&
        [netmaskArr isKindOfClass:[NSArray class]] && [netmaskArr count] > 0) {
      NSString *ip = [ipArr objectAtIndex:0];
      NSString *netmask = [netmaskArr objectAtIndex:0];

      if ([ip length] && [netmask length]) {
        struct in_addr localAddr;
        struct in_addr netmaskAddr;
        struct in_addr netAddr;

        // Only proceed if both strings parse as valid IPv4 addresses.
        if (inet_aton([ip UTF8String], &localAddr) != 0 &&
            inet_aton([netmask UTF8String], &netmaskAddr) != 0) {
          // Network address: IP AND netmask.
          netAddr.s_addr = (localAddr.s_addr & netmaskAddr.s_addr);
          NSString *netAddress =
              [NSString stringWithUTF8String:inet_ntoa(netAddr)];
          NSUInteger numberOfBits = [self numberOfBitsSetInMask:netmaskAddr];

          if (netAddress) {
            result = @{
              NETWORKINFO_IPADDRESS : ip,
              NETWORKINFO_SUBNETMASK : netmask,
              NETWORKINFO_SUBNETBITS :
                  [NSNumber numberWithUnsignedInteger:numberOfBits],
              NETWORKINFO_NETADDRESS : netAddress,
              NETWORKINFO_INTERFACENAME : primaryInterface
            };
          }
        }
      }
    }
  }

  if (ipv4 != NULL) {
    CFRelease(ipv4);
  }
  if (global != NULL) {
    CFRelease(global);
  }
  CFRelease(storeRef);

  return result;
}

/**
 *  Magic function that calculates the number of bits set in the subnet mask.
 *  This is known as the 'Hamming Weight', 'popcount' or 'sideways addition'.
 *
 *  @param mask The subnet mask in in_addr format
 *
 *  @return The number of bits in the mask
 */
+ (NSInteger)numberOfBitsSetInMask:(struct in_addr)mask {
  uint32 i = mask.s_addr;
  i = i - ((i >> 1) & 0x55555555);
  i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
  return (((i + (i >> 4)) & 0x0F0F0F0F) * 0x01010101) >> 24;
}

@end
