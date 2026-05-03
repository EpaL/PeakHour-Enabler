//
//  ProcessInformation.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 29/03/2015.
//  Copyright (c) 2015 Edward Lawford. All rights reserved.
//

import Cocoa

class ProcessInformation: NSObject {

  class func getBsdProcessList() -> NSArray? {
    let processInformation = ProcessInformation_Objc()
    return processInformation.getBSDProcessList() as NSArray?
  }
  
  class func isProcessRunning(_ processName: String) -> Bool {
    if let processList = ProcessInformation.getBsdProcessList() as? [[String:Any]] {
      for process in processList {
        if let theProcessName = process["pname"] as? String {
          if theProcessName == processName {
            return true
          }
        }
      }
    }
    return false
  }
  
  /**
  Executes the given command and arguments and returns the output as a string.
  
  - parameter command:   The full path to the command to execute.
  - parameter arguments: An array of arguments
  
  - returns: The output returned by the command.
  */
  func ExecuteTask(_ launchPath: String, arguments: [String]) -> String {
    let task = Process()
    task.launchPath = launchPath
    task.arguments = arguments
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
      return output as String
    } else {
      return ""
    }
  }
}
