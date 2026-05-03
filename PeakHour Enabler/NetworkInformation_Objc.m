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
  SCDynamicStoreRef storeRef = SCDynamicStoreCreate(
      NULL, (CFStringRef) @"FindCurrentInterfaceIpMac", NULL, NULL);
  CFPropertyListRef global =
      SCDynamicStoreCopyValue(storeRef, CFSTR("State:/Network/Global/IPv4"));
  id primaryInterface =
      [(__bridge NSDictionary *)global valueForKey:@"PrimaryInterface"];

  if (primaryInterface) {
    NSString *interfaceState = @"State:/Network/Interface/";
    interfaceState =
        [[interfaceState stringByAppendingString:(NSString *)primaryInterface]
            stringByAppendingString:@"/IPv4"];
    CFPropertyListRef ipv4 =
        SCDynamicStoreCopyValue(storeRef, (__bridge CFStringRef)interfaceState);
    id ipArr = [(__bridge NSDictionary *)ipv4 valueForKey:@"Addresses"];
    id ip = [ipArr objectAtIndex:0];
    id netmaskArr = [(__bridge NSDictionary *)ipv4 valueForKey:@"SubnetMasks"];
    id netmask = [netmaskArr objectAtIndex:0];
    NSString *netAddress = nil;
    if (storeRef != nil) {
      CFRelease(storeRef);
    }
    if (ipv4 != nil) {
      CFRelease(ipv4);
    }
    if (global != nil) {
      CFRelease(global);
    }

    // Get the subnet address

    if ([ip length] && [netmask length]) {
      // Strings to in_addr:
      struct in_addr localAddr;
      struct in_addr netmaskAddr;
      struct in_addr netAddr;
      inet_aton([ip UTF8String], &localAddr);
      inet_aton([netmask UTF8String], &netmaskAddr);

      // Calculate properties of this local active subnet.
      // Starting IP: Invert mask (XOR with ones), AND it with IP. Add 1.
      netAddr.s_addr = (localAddr.s_addr & netmaskAddr.s_addr);
      netAddress = [NSString stringWithUTF8String:inet_ntoa(netAddr)];
    }

    // Get the number of bits for the subnet mask
    if (netmask && netAddress) {
      struct in_addr netmaskAddr;
      inet_aton([netmask UTF8String], &netmaskAddr);
      NSUInteger numberOfBits = [self numberOfBitsSetInMask:netmaskAddr];

      return @{
        NETWORKINFO_IPADDRESS : ip,
        NETWORKINFO_SUBNETMASK : netmask,
        NETWORKINFO_SUBNETBITS :
            [NSNumber numberWithUnsignedInteger:numberOfBits],
        NETWORKINFO_NETADDRESS : netAddress,
        NETWORKINFO_INTERFACENAME : primaryInterface
      };
    }
  }

  return @{
    NETWORKINFO_IPADDRESS : @"",
    NETWORKINFO_SUBNETMASK : @"",
    NETWORKINFO_SUBNETBITS : @0,
    NETWORKINFO_NETADDRESS : @"",
    NETWORKINFO_INTERFACENAME : @""
  };
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
