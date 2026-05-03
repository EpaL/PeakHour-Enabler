//
//  NSTextView+DetectAndAddClicks.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 8/01/2016.
//  Copyright © 2016 Edward Lawford. All rights reserved.
//

import AppKit

extension NSTextView {
  /**
   Detects URLs and convert them to hyperlinks.
   */
  func detectAndAddLinks() {
    if let linkLocations = self.string.locationOfLinks(),
      let links = self.string.arrayOfLinks() {
        var i: Int = 0
        for link in links {
          if let url = URL.init(string:link as! String) {
            let linkString: NSAttributedString = NSAttributedString.hyperlinkFromString(link as! String as NSString, withURL: url) as! NSAttributedString
            self.textStorage?.replaceCharacters(in: (linkLocations.object(at: i) as AnyObject).range, with:linkString)
            i += 1;
          }
        }
    }
  }
}
