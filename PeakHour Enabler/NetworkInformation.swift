//
//  NetworkInformation.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 28/03/2015.
//  Copyright (c) 2015 Edward Lawford. All rights reserved.
//

import Cocoa

class NetworkInformation: NSObject {

  class func getActiveNetworkInterfaceInfo() -> (ipAddress: String?, subnetMask: String?, subnetBits: Int, netAddress: String?, interfaceName: String?) {
    // Call the Objective C version of the function.
    let networkInfo = NetworkInformation_Objc.getActiveNetworkInterfaceInfo_ObjC() as! Dictionary<String, AnyObject>
    let ipAddress = networkInfo["ipAddress"] as! String?
    let subnetMask = networkInfo["subnetMask"] as! String?
    let subnetBits = networkInfo["subnetBits"] as! Int
    let netAddress = networkInfo["netAddress"] as! String?
    let interfaceName = networkInfo["interfaceName"] as! String?
    
    return (ipAddress:  ipAddress,
            subnetMask: subnetMask,
            subnetBits: subnetBits,
            netAddress: netAddress,
            interfaceName: interfaceName)
  }
}
