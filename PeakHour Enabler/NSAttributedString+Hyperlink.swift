//
//  NSAttributedString+Hyperlink.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 8/01/2016.
//  Copyright © 2016 Edward Lawford. All rights reserved.
//

import Foundation

extension NSAttributedString {
  @objc class func hyperlinkFromString(_ inString:NSString, withURL:URL) -> AnyObject {
    let attrString = NSMutableAttributedString.init(string: inString as String)
    let range = NSMakeRange(0, attrString.length)
    
    attrString.beginEditing()
    attrString.addAttribute(NSAttributedString.Key.link, value:withURL.absoluteString, range:range)
    
    // make the text appear in blue
//    if #available(OSX 11.0, *) {
//      attrString.addAttribute(NSAttributedString.Key.foregroundColor, value:NSColor.init(named:"AccentColor") as Any, range:range)
//    } else {
//      attrString.addAttribute(NSAttributedString.Key.foregroundColor, value:NSColor.blue, range:range)
//    }
    
    // next make the text appear with an underline
    attrString.addAttribute(NSAttributedString.Key.underlineStyle, value:NSUnderlineStyle.single.rawValue, range:range)
    
    attrString.endEditing()
    
    return attrString
  }
}
