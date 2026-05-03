//
//  NSString+FindURLs.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 9/01/2016.
//  Copyright © 2016 Edward Lawford. All rights reserved.
//

import Foundation

extension NSString {
  func arrayOfLinks() -> NSArray? {
    var regex:NSRegularExpression? = nil
    let links = NSMutableArray()
    let regexToReplaceRawLinks = "(\\b(https?):\\/\\/[-A-Z0-9+&@#\\/%?=~_|!:,.;]*[-A-Z0-9+&@#\\/%=~_|])"
    do {
      regex = try NSRegularExpression.init(pattern: regexToReplaceRawLinks, options:NSRegularExpression.Options.caseInsensitive)
    } catch _ {
      print("Error parsing NSRegularExpression: \(regex)")
      return links;
    }
    
    if (regex != nil) {
      let results = regex!.matches(in: self as String, options:[], range:NSMakeRange(0, self.length))

      for result in results {
        links.add(self.substring(with: result.range))
      }
    }
  
    return links;
  }

  func locationOfLinks() -> NSArray? {
    var regex:NSRegularExpression? = nil
    let regexToReplaceRawLinks = "(\\b(https?):\\/\\/[-A-Z0-9+&@#\\/%?=~_|!:,.;]*[-A-Z0-9+&@#\\/%=~_|])"
    
    do {
      regex = try NSRegularExpression.init(pattern: regexToReplaceRawLinks, options:NSRegularExpression.Options.caseInsensitive)
    } catch _ {
      print("Error parsing NSRegularExpression: \(regex)")
      return nil
    }
    
    if (regex != nil) {
      let results = regex!.matches(in: self as String, options:[], range:NSMakeRange(0, self.length))
      
      return results as NSArray?
    }
    
    return nil
  }
}
