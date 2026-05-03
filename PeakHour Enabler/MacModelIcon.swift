//
//  MacModelIcon.swift
//  PeakHour Enabler
//
//  Lightweight model-identifier-to-SF-Symbol mapping for the Enabler target.
//

import Foundation
import AppKit

enum MacModelIcon {

  /// Returns the SF Symbol name for the current Mac's hardware type.
  static func currentMacSymbolName() -> String {
    let id = modelIdentifier()

    // Legacy prefixed identifiers
    if id?.hasPrefix("iMac") == true { return "display" }
    if id?.hasPrefix("MacBook") == true { return "laptopcomputer" }
    if id?.hasPrefix("Macmini") == true { return "macmini.fill" }
    if id?.hasPrefix("MacPro") == true { return "macpro.gen3.fill" }
    if id?.hasPrefix("Xserve") == true { return "xserve" }

    // Generic "MacXX,Y" — check for known laptops by IOKit built-in display
    guard let id = id, id.hasPrefix("Mac") else {
      return fallbackSymbol()
    }

    // Known laptop IDs
    let laptopIDs: Set<String> = [
      "Mac14,2", "Mac14,5", "Mac14,6", "Mac14,7", "Mac14,9", "Mac14,10", "Mac14,15",
      "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
      "Mac15,12", "Mac15,13",
      "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8", "Mac16,12", "Mac16,13",
      "Mac17,2", "Mac17,3", "Mac17,4", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9",
    ]
    if laptopIDs.contains(id) { return "laptopcomputer" }

    // Known iMacs
    let iMacIDs: Set<String> = ["Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3"]
    if iMacIDs.contains(id) { return "display" }

    // Known Mac minis
    let miniIDs: Set<String> = ["Mac16,10", "Mac16,11"]
    if miniIDs.contains(id) { return "macmini.fill" }

    // Known Mac Studios
    let studioIDs: Set<String> = ["Mac13,1", "Mac13,2", "Mac14,13", "Mac14,14", "Mac15,14", "Mac16,9"]
    if studioIDs.contains(id) { return "macstudio.fill" }

    // Known Mac Pros
    let proIDs: Set<String> = ["Mac14,8"]
    if proIDs.contains(id) { return "macpro.gen3.fill" }

    return fallbackSymbol()
  }

  // MARK: - Private

  private static func modelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("IOPlatformExpertDevice"))
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    guard let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else {
      return nil
    }
    return String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
  }

  private static func fallbackSymbol() -> String {
    // Macs with a built-in display are laptops
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                              IOServiceMatching("IODisplayConnect"),
                                              &iterator)
    guard result == KERN_SUCCESS else { return "desktopcomputer" }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != IO_OBJECT_NULL {
      defer {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
      }
      if let prop = IORegistryEntryCreateCFProperty(service, "IODisplayIsBuiltIn" as CFString, kCFAllocatorDefault, 0) {
        if let isBuiltIn = prop.takeRetainedValue() as? Bool, isBuiltIn {
          return "laptopcomputer"
        }
      }
    }
    return "desktopcomputer"
  }
}
