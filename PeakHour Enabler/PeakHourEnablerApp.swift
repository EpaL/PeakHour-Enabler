//
//  PeakHourEnablerApp.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 17/04/2026.
//  Copyright © 2026 Digitician Inc. All rights reserved.
//

import SwiftUI

/// Forces the app to quit immediately when the window is closed.
final class EnablerAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Post willTerminate so the timer gets cleaned up, then force-exit
    // to skip SwiftUI's slow Spotlight/CSSearchableIndex state restoration.
    NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: sender)
    exit(0)
  }
  
  func applicationWillFinishLaunching(_ notification: Notification) {
    // Disable state restoration to prevent Spotlight indexing delay on quit
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
  }
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Delay activation slightly to ensure the SwiftUI window is ready
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      NSApplication.shared.activate(ignoringOtherApps: true)
      NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
    }
  }
}

@main
struct PeakHourEnablerApp: App {
  @NSApplicationDelegateAdaptor(EnablerAppDelegate.self) var appDelegate
  @StateObject private var snmpConfigurator = SnmpConfigurator()
  
  var body: some Scene {
    WindowGroup {
      ContentView(configurator: snmpConfigurator)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
          snmpConfigurator.stopStatusPolling()
        }
    }
    .windowStyle(.hiddenTitleBar)
  }
}
