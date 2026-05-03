//
//  StringExtensions.swift
//  PeakHour
//
//  Created by Edward Lawford on 6/29/17.
//
//

import AppKit

extension NSAttributedString {
  
  /// Creates an NSMutableAttributedString with a URL inserted between beforeString and afterString.
  ///
  /// - Parameters:
  ///   - beforeString: The string to place before the URL.
  ///   - afterString: The string to place after the URL.
  ///   - url: The URL.
  ///   - urlTitle: The title of the URL.
  @objc class func sentanceWithHyperlink(beforeString: String, afterString: String, url: URL, urlTitle: String, font: NSFont, foregroundColor: NSColor) -> NSMutableAttributedString {
    let attributedString: NSMutableAttributedString = NSMutableAttributedString(string: beforeString)
    attributedString.append(NSAttributedString.hyperlinkFromString(NSString(string: urlTitle), withURL: url) as! NSAttributedString)
    attributedString.append(NSAttributedString.init(string: afterString))
    
    attributedString.addAttribute(NSAttributedString.Key.font, value: font , range: NSMakeRange(0,attributedString.length-1))
    attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: foregroundColor, range: NSMakeRange(0,attributedString.length-1))
    
    return attributedString
  }
  
}
