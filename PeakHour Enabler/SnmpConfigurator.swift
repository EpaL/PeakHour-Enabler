//
//  SnmpConfigurator.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 22/03/2015.
//  Copyright (c) 2015 Edward Lawford. All rights reserved.
//

import Cocoa
import Combine

@objc class SnmpConfigurator: NSObject, ObservableObject {
  
  // Constants
  static let SharedAppGroupIdentifier     = "SZZFX78PB5.group.com.digitician.peakhour"
  static let SnmpConfigurationFilePath        = "/etc/snmp/snmpd.conf"
  static let SnmpConfigurationDefaultFilePath = "/etc/snmp/snmpd.conf.default"

  /// The file to read the existing / seed configuration from: the live snmpd.conf
  /// if present, otherwise Apple's stock snmpd.conf.default (recent macOS ships only
  /// the latter until snmpd.conf is created, so reading snmpd.conf directly would
  /// fail and abort Enable on a clean system).
  static var snmpdTemplateReadPath: String {
    FileManager.default.fileExists(atPath: SnmpConfigurationFilePath)
      ? SnmpConfigurationFilePath
      : SnmpConfigurationDefaultFilePath
  }
  let snmpdServiceLabel                   = "org.net-snmp.snmpd"
  let snmpdLaunchAgentPath                = "/System/Library/LaunchDaemons/org.net-snmp.snmpd.plist"

  // Watchdog: a root LaunchDaemon that re-applies snmpd.conf and reloads snmpd so
  // monitoring survives macOS updates (which can reset /etc/snmp/snmpd.conf and
  // disable the daemon). Installed/removed by the privileged Enable/Disable steps.
  let watchdogSupportDirectory            = "/Library/Application Support/PeakHourEnabler"
  let watchdogDaemonLabel                 = "com.digitician.peakhour.enabler.watchdog"
  var watchdogSavedConfigPath: String     { "\(watchdogSupportDirectory)/snmpd.conf" }
  var watchdogScriptInstalledPath: String { "\(watchdogSupportDirectory)/watchdog.sh" }
  var watchdogDaemonPlistPath: String     { "/Library/LaunchDaemons/\(watchdogDaemonLabel).plist" }

  // Objects
  let processInformation = ProcessInformation()
  
  // Properties
  var hasReadConfiguredSnmpdProperties = false
  var networkAddrAndSubnetBits: String? = nil
  @objc var ipAddress: String? = nil
  var snmpdConfigurationPathURL: URL? = URL.init(string:SnmpConfigurator.SnmpConfigurationFilePath)
  @Published var community: String? = nil
  @Published var publicNetwork: String? = nil
  @Published var publicCommunity: String? = nil
  @Published var storeConfigurationInIcloud = true
  @Published var isSnmpdRunning = false
  @Published var autoGenerateSnmpCommunity = true

  /// User-facing error from the most recent Enable/Disable attempt, or nil. Shown
  /// in the UI; cleared when a new attempt starts and when monitoring succeeds.
  @Published var lastErrorMessage: String? = nil

  
  // Constant
  let SharedLocalSnmpCommunity = "SharedLocalSnmpCommunity";
  let PeakhourEnablerLastRunTime = "PeakhourEnablerLastRunTime";
  let PeakhourEnablerLastCheckTime = "PeakhourEnablerLastCheckTime";

  // App Group Defaults
  var sharedDefaults = UserDefaults.init(suiteName: SnmpConfigurator.SharedAppGroupIdentifier)
  
  // Enums
  enum Status {
    case notStarted
    case startedNotConfigured
    case configuredLocalhostOnly
    case configuredNetwork
  }
  
  enum ServiceCommand {
    case start
    case startOnly     // Start snmpd but don't configure.
    case stop
  }
  
  // Status polling timer
  private var statusPollingTimer: Timer?
  
  /// True if access from other machines is enabled.
  var isNonLocalAccessEnabled: Bool {
    get {
      if (self.publicNetwork == "NETWORK/24") {
          return false
      } else {
        return true
      }
    }
    set(newValue) {
      if (newValue == true) {
        self.publicNetwork = self.networkAddrAndSubnetBits
      } else {
        self.publicNetwork = "NETWORK/24"
      }
    }
  }
  /// Returns true if snmpd.conf is modified / configured.
  var snmpdConfigured: Bool {
    if (self.community == "COMMUNITY" &&
      self.publicNetwork == "NETWORK/24" &&
      self.publicCommunity == "COMMUNITY") {
        return false
    } else {
      return true
    }
  }
  // snmpdStarted
  //
  // Checks launchctl to see if org.net-snmp.snmpd.plist is running.
  var snmpdStarted: Bool
  {
    if (ProcessInformation.isProcessRunning("snmpd") == true) {
      return true
    } else {
      return false
    }
  }
  /// Return the current status of snmpd
  var status: Status {
    if self.snmpdStarted == false {
      return .notStarted
    } else {
      if self.snmpdConfigured == false {
        return .startedNotConfigured
      } else if self.isNonLocalAccessEnabled == false {
        return .configuredLocalhostOnly
      } else {
        return .configuredNetwork
      }
    }
  }
  
  /**
  Our init function, which takes an NSWindow optional. The window will be used to add an NSOpenPanel sheet when sandboxing is detected.
  
  - returns: Ourselves
  */
  override init() {
    super.init()
    
    // Get IP address and subnet information
    let (ipAddress, _, subnetBits, netAddress, _) = NetworkInformation.getActiveNetworkInterfaceInfo()
    if netAddress != nil {
      self.networkAddrAndSubnetBits = "\(netAddress!)/\(subnetBits)"
    }
    if ipAddress != nil {
      self.ipAddress = ipAddress!
    }
    
    _ = self.readConfiguredSnmpdProperties(false)
    
    // Enable access from non-local hosts
    self.isNonLocalAccessEnabled = true
    
    // Auto-generate SNMP community if not configured
    if self.community == "COMMUNITY" || self.community == nil {
      self.generateRandomSnmpCommunity()
      self.autoGenerateSnmpCommunity = true
    } else {
      self.autoGenerateSnmpCommunity = false
    }
    
    // Set initial snmpd status
    self.isSnmpdRunning = self.snmpdStarted
    
    // Start polling snmpd status
    self.startStatusPolling()
  }
  
  // MARK: - Status Polling
  
  /// Starts a timer that polls snmpd status every 2 seconds.
  private func startStatusPolling() {
    statusPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      let running = self.snmpdStarted
      if self.isSnmpdRunning != running {
        self.isSnmpdRunning = running
      }
    }
  }
  
  /// Stops the status polling timer.
  func stopStatusPolling() {
    statusPollingTimer?.invalidate()
    statusPollingTimer = nil
  }
  
  // MARK: - SNMP Community Management
  
  /// Generate a random alphanumeric SNMP community string.
  func generateRandomSnmpCommunity() {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    self.community = String((0..<12).map { _ in letters.randomElement()! })
  }
  
  /// Called when the auto-generate toggle changes.
  func toggleAutoGenerateCommunity() {
    if autoGenerateSnmpCommunity {
      generateRandomSnmpCommunity()
    }
  }

  /// A valid SNMP community for our purposes is non-empty, ASCII alphanumeric and
  /// of a reasonable length. This is enforced before the value is written into
  /// snmpd.conf (which is parsed by snmpd running as root), so that whitespace or
  /// other metacharacters can't change the meaning of, or inject, config directives.
  static func isValidSnmpCommunity(_ value: String) -> Bool {
    guard (1...32).contains(value.count) else { return false }
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    return value.allSatisfy { allowed.contains($0) }
  }

  /// A valid SNMP source network is composed only of digits, dots and a CIDR
  /// slash (e.g. "192.168.1.0/24"). The literal placeholder "NETWORK/24" is never
  /// passed through this check — it is written verbatim only when access is disabled.
  static func isValidSnmpNetwork(_ value: String) -> Bool {
    guard (7...18).contains(value.count) else { return false }
    let allowed = Set("0123456789./")
    return value.allSatisfy { allowed.contains($0) }
  }
  
  // readConfiguredSnmpdProperties
  //
  // Reads the snmpd configuration file and - if possible - returns the three
  // configured properties we're interested in.
  // The two lines we're reading look like this in the default configuration file:
  // #       sec.name  source          community
  // com2sec local     localhost       COMMUNITY
  // com2sec mynetwork NETWORK/24      COMMUNITY
  @objc func readConfiguredSnmpdProperties(_ force: Bool = false) -> (Bool)
  {
    var fileContents = ""
    
    if (self.hasReadConfiguredSnmpdProperties == true &&
      force == false) {
      return true
    }
    
    // Read the snmpd configuration file (or the stock default) into a single string.
    let templatePath = SnmpConfigurator.snmpdTemplateReadPath
    do {
      fileContents = try String(contentsOfFile: templatePath, encoding: String.Encoding.utf8 )
    } catch let error as NSError {
      print("An error occurred opening '\(templatePath)': \(error)", terminator: "")
      return false
    }
    
    // Split the string into lines.
    if let lines = fileContents.components(separatedBy: CharacterSet.newlines) as [String]? {
      for line in lines {
        // Split the lines into words
        if var lineWords = line.components(separatedBy: CharacterSet.whitespaces) as [String]? {
          
          // Delete any empty words from the array
          var i: Int = 0
          for word in lineWords {
            if word.utf16.count == 0 {
              lineWords.remove(at: i)
            } else {
              i += 1
            }
          }
          
          // Some lines will now have no words left.
          if lineWords.count == 0 {
            continue
          }
          
          // The two lines we care about both have at least four whitespace-
          // separated fields. Guard against malformed/short lines so we don't
          // index past the end of the array and crash.
          guard lineWords.count >= 4 else {
            continue
          }

          // Extract the information.
          if (lineWords[0] == "com2sec" &&
            lineWords[1] == "local" &&
            lineWords[2] == "localhost") {
              self.community = lineWords[3]
          }

          if (lineWords[0] == "com2sec" &&
            lineWords[1] == "mynetwork") {
              self.publicNetwork   = lineWords[2]
              self.publicCommunity = lineWords[3]
          }
        }
      }
    }
    
    // Should we enable the isNonLocalAccessEnabled checkbox?
    if (self.publicNetwork != nil && self.publicCommunity != nil) {
      if (self.publicNetwork! == "NETWORK/24" && self.publicCommunity! == "COMMUNITY") {
          self.isNonLocalAccessEnabled = false
      } else {
        self.isNonLocalAccessEnabled = true
      }
    } else {
      self.isNonLocalAccessEnabled = true
    }
    
    self.hasReadConfiguredSnmpdProperties = true
    
    return true
  }
  
  /**
  Creates an updated snmpd.conf configuration file, with the current set of parameters.
  Must be copied into place via sudo or other privileged task.
  
  - returns: Whether the file was written successfully.
  */
  func createNewSnmpdConfiguration(at stagingPath: String) -> (Bool) {
    var outputLines: Array<String> = []

    // Validate the community before we write it into a file that snmpd parses as
    // root. A community containing whitespace, '#' or other metacharacters could
    // otherwise change the meaning of the com2sec line or inject extra directives.
    guard let community = self.community, SnmpConfigurator.isValidSnmpCommunity(community) else {
      print("Refusing to write snmpd.conf: the SNMP community is missing or contains characters outside [A-Za-z0-9].")
      return false
    }

    // Read the existing (or stock default) snmpd configuration into a single string.
    let templatePath = SnmpConfigurator.snmpdTemplateReadPath
    do {
      let fileContents = try String(contentsOfFile: templatePath, encoding: String.Encoding.utf8 )
      // Read the input file and split into lines.
      if let lines = fileContents.components(separatedBy: CharacterSet.newlines) as [String]? {
        // Iterate through each line.
        for line in lines {
          // Split the lines into words
          if let lineWords = line.components(separatedBy: CharacterSet.whitespaces) as [String]? {
            // Assume we're going to write this same line back to the file, unless it is one we want to change.
            var outputLine = line

            // Some lines will now have no words left. Write this line and move on.
            if lineWords.count == 0 {
              outputLines.append(outputLine)
              continue
            }

            // Look for the keywords that indicate this is one of the lines we want to alter.
            let localResult = (lineWords as Array).enumerated().lazy.filter {(idx, constraint) in
              if lineWords[idx] == "com2sec" && idx == 0 {
                return true
              }
              if lineWords[idx] == "local" && idx == 1 {
                return true
              }
              return false
            }.map{$0.offset}

            // If this is the line, update it
            if (localResult.contains(0) && localResult.contains(1)) {
              outputLine = "com2sec local     localhost       \(community)"
            }

            let publicResult = (lineWords as Array).enumerated().lazy.filter {(idx, constant) in
              if lineWords[idx] == "com2sec" && idx == 0 {
                return true
              }
              if lineWords[idx] == "mynetwork" && idx == 1 {
                return true
              }
              return false
              }.map{$0.offset}
            // If this is the line, update it
            if (publicResult.contains(0) && publicResult.contains(1)) {
              if self.isNonLocalAccessEnabled == true,
                 let network = self.publicNetwork,
                 SnmpConfigurator.isValidSnmpNetwork(network) {
                outputLine = "com2sec mynetwork \(network)       \(community)"
              } else {
                outputLine = "com2sec mynetwork NETWORK/24       COMMUNITY"
              }
            }

            // Append to the line to the array that we're going to write later.
            outputLines.append(outputLine)
          }
        }

        // Write the new output lines to the file.
        // First, this little morsel of syntactic sugar reduces the array back to a single string.
        let outputString = outputLines.reduce("") { $0.isEmpty ? $1 : "\($0)\n\($1)" }
        do {
          // Now write to to a file (atomically, and readable only by us — it
          // carries the community string until the privileged copy runs).
          print("writing new snmpd preferences to \(stagingPath)")
          try outputString.write(toFile: stagingPath, atomically: true, encoding: String.Encoding.utf8)
          try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600 as Int16)],
                                                  ofItemAtPath: stagingPath)
        } catch let error as NSError {
          print("Couldn't write to '\(stagingPath)' configuration file for writing: \(error)")
          return false;
        }
      }
    } catch let error as NSError {
      print("Couldn't open '\(templatePath)' configuration file for reading: \(error)")

      return false
    }

    return true
  }
  
  /**
  Modifies snmpd startup configuration.
  
  - parameter command: Whether to start or stop the service. If command is start, the new snmpd.conf is copied into place as well.
  */
  func controlSnmpd(_ serviceCommand: ServiceCommand) {
    var commandFileContents         = ""
    let snmpdLaunchAgentCommand     = "/bin/launchctl load -F -w \(self.snmpdLaunchAgentPath)"
    let snmpdStopAgentCommand       = "/bin/launchctl unload -F -w \(self.snmpdLaunchAgentPath)"
    let command                     = "/usr/bin/open"
    let fileManager                 = FileManager.default

    // A new attempt clears any error shown from the previous one.
    self.lastErrorMessage = nil

    // Create a private, single-use working directory with an unpredictable name
    // that only the current user can read or write, so another process can't
    // pre-plant a symlink at a predictable path that the privileged `cp` below
    // would then follow into an arbitrary destination. A plain UUID-named subdir
    // of the temp dir (no spaces/parens, unlike itemReplacementDirectory) keeps
    // the paths simple to quote in the shell script.
    let workDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("PeakHourEnabler-\(UUID().uuidString)", isDirectory: true)
    do {
      try fileManager.createDirectory(at: workDirectory,
                                      withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: NSNumber(value: 0o700 as Int16)])
    } catch {
      print("Couldn't create a secure working directory: \(error). Aborting.")
      self.lastErrorMessage = "Couldn't create a temporary working directory. Please try again."
      return
    }

    let stagingConfigurationPath = workDirectory.appendingPathComponent("snmpd-out.conf").path
    let commandFileName          = workDirectory.appendingPathComponent("PeakHourEnabler-Control.command").path

    // Only the start case rewrites snmpd.conf; stage it (and the watchdog files)
    // now and bail if we can't produce a valid configuration (e.g. an invalid
    // community).
    var stagedWatchdog: (script: String, plist: String)? = nil
    if serviceCommand == .start {
      guard self.createNewSnmpdConfiguration(at: stagingConfigurationPath) else {
        print("Couldn't stage a valid snmpd configuration. Aborting.")
        self.lastErrorMessage = "Couldn't prepare the SNMP configuration. If you set a custom community, use only letters and numbers."
        try? fileManager.removeItem(at: workDirectory)
        return
      }
      guard let watchdog = self.stageWatchdogFiles(in: workDirectory) else {
        print("Couldn't stage the watchdog files. Aborting.")
        self.lastErrorMessage = "Couldn't prepare the watchdog files. Please try again."
        try? fileManager.removeItem(at: workDirectory)
        return
      }
      stagedWatchdog = watchdog
    }

    print("launching \(commandFileName)")

    // Build the body of the privileged script. snmpdStopAgentCommand /
    // snmpdLaunchAgentCommand already include the launchctl subcommand and plist.
    var scriptLines: [String] = ["#!/bin/bash", "clear"]
    switch serviceCommand {
    case .start:
      scriptLines += [
        "echo '▶️  Configuring and starting snmpd.'",
        "echo 'ℹ️  This will allow your Mac to be monitored with PeakHour.'",
        "echo",
        "echo 'ℹ️  Enter your macOS password below.'",
        "sudo cp '\(stagingConfigurationPath)' '\(SnmpConfigurator.SnmpConfigurationFilePath)'",
        // The staging file is 0600; the live snmpd.conf must be world-readable
        // (the OS default) so the Enabler — running as the user — can read it back.
        "sudo chmod 644 '\(SnmpConfigurator.SnmpConfigurationFilePath)'",
        "echo '⏯  (Re)starting snmpd...'",
        "sudo \(snmpdStopAgentCommand) 2>/dev/null",
        "sudo \(snmpdLaunchAgentCommand)",
        "sudo /bin/launchctl kickstart -k system/\(snmpdServiceLabel)"
      ]
      if let watchdog = stagedWatchdog {
        scriptLines += self.watchdogInstallScriptLines(stagedConfig: stagingConfigurationPath,
                                                       stagedScript: watchdog.script,
                                                       stagedPlist: watchdog.plist)
      }
      scriptLines += ["echo '👍  snmpd started.'", "echo"]
    case .startOnly:
      scriptLines += [
        "echo '▶️  Starting snmpd.'",
        "echo 'ℹ️  This will allow your Mac to be monitored with PeakHour.'",
        "echo",
        "echo 'ℹ️  Enter your macOS password below.'",
        "echo '⏯  (Re)starting snmpd...'",
        "sudo \(snmpdStopAgentCommand) 2>/dev/null",
        "sudo \(snmpdLaunchAgentCommand)",
        "sudo /bin/launchctl kickstart -k system/\(snmpdServiceLabel)",
        "echo '👍  snmpd started.'",
        "echo"
      ]
    case .stop:
      // Stop snmpd by label with `bootout` (reliably kills the running daemon —
      // `unload -w` was throwing I/O errors on this SIP daemon and could leave it
      // running, serving its in-memory config), then keep the legacy `unload -w`
      // to persist the disabled state across reboots.
      scriptLines += [
        "echo '⏹  Stopping snmpd'",
        "sudo /bin/launchctl bootout system/\(snmpdServiceLabel) 2>/dev/null",
        "sudo \(snmpdStopAgentCommand) 2>/dev/null"
      ]
      scriptLines += self.watchdogRemovalScriptLines()
      // Restore the default by removing the snmpd.conf we created, so /etc/snmp is
      // back to its shipped state (just snmpd.conf.default). The watchdog and its
      // saved copy are already gone (above), so nothing will re-apply it.
      scriptLines += [
        "echo '🧹  Restoring the default SNMP configuration...'",
        "sudo rm -f '\(SnmpConfigurator.SnmpConfigurationFilePath)'",
        "echo '👍  snmpd stopped.'",
        "echo"
      ]
    }

    // The script removes its own (user-owned) working directory as its final step.
    // Doing cleanup here rather than back in Swift avoids a race: we launch with
    // plain `open` (no -W), which returns as soon as Terminal starts, so deleting
    // the staged files from Swift could pull them out from under the still-running
    // `sudo cp`. The script removes its own working dir as its final step, and we
    // ask the user to quit Terminal — a scripted ⌘Q could quit the wrong app or
    // all Terminal windows.
    scriptLines += [
      "rm -rf '\(workDirectory.path)'",
      "echo",
      "echo '✅  All done — you can quit Terminal now (⌘Q).'"
    ]
    commandFileContents = scriptLines.joined(separator: "\n")

    do {
      try commandFileContents.write(toFile: commandFileName,
                                    atomically: true,
                                    encoding: String.Encoding.utf8)
    } catch _ {
      print("An error occurred creating the service command script. Aborting.")
      self.lastErrorMessage = "Couldn't create the helper script. Please try again."
      try? fileManager.removeItem(at: workDirectory)
      return
    }

    // Make the script executable (owner only).
    let attributes: [FileAttributeKey: Any] = [FileAttributeKey.posixPermissions: NSNumber(value: 0o700 as Int16)]
    do {
      try fileManager.setAttributes(attributes, ofItemAtPath: commandFileName)
    } catch _ {
      print("Error occurred making SNMP control script executable")
      self.lastErrorMessage = "Couldn't prepare the helper script. Please try again."
      try? fileManager.removeItem(at: workDirectory)
      return
    }

    _ = self.processInformation.ExecuteTask(command, arguments:[commandFileName])

    // Share or clear this Mac's configuration. `open` returns as soon as Terminal
    // launches — well before the privileged script finishes — so we don't assume
    // snmpd.conf is updated the instant ExecuteTask returns; shareConfigurationWhenReady()
    // re-checks for a while and only advertises once the live config carries our community.
    switch serviceCommand {
    case .start, .startOnly:
      self.shareConfigurationWhenReady(attempt: 0)
    case .stop:
      self.removeSharedConfiguration()
    }
  }

  /// Advertises this Mac once the on-disk snmpd.conf reflects the requested
  /// community, retrying for a short while because the privileged Terminal step
  /// may not have finished by the time `open` returns. Runs on the main queue.
  private func shareConfigurationWhenReady(attempt: Int) {
    if self.liveConfigUsesCurrentCommunity() {
      self.lastErrorMessage = nil
      self.storeConfigurationInSharedDefaults()
      if self.storeConfigurationInIcloud == true {
        self.storeConfigurationIniCloud()
      }
      return
    }
    if attempt >= 15 {
      print("snmpd.conf still doesn't reflect the requested SNMP community after waiting; not sharing this Mac's configuration.")
      self.lastErrorMessage = "Monitoring wasn't enabled. If you cancelled the password prompt, click Enable Monitoring to try again."
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      self?.shareConfigurationWhenReady(attempt: attempt + 1)
    }
  }

  // MARK: - Watchdog

  /// Writes the watchdog script and LaunchDaemon plist into the (user-only)
  /// working directory so the privileged step can copy them into place as root.
  private func stageWatchdogFiles(in workDirectory: URL) -> (script: String, plist: String)? {
    let scriptPath = workDirectory.appendingPathComponent("watchdog.sh").path
    let plistPath  = workDirectory.appendingPathComponent("watchdog.plist").path
    do {
      try self.watchdogScriptContents().write(toFile: scriptPath, atomically: true, encoding: .utf8)
      try self.watchdogDaemonPlistContents().write(toFile: plistPath, atomically: true, encoding: .utf8)
    } catch {
      print("Couldn't stage watchdog files: \(error)")
      return nil
    }
    return (script: scriptPath, plist: plistPath)
  }

  /// Privileged commands that install (or refresh) the watchdog: copy the saved
  /// config, script and LaunchDaemon into root-owned locations and (re)load it.
  private func watchdogInstallScriptLines(stagedConfig: String, stagedScript: String, stagedPlist: String) -> [String] {
    return [
      "echo '🛡  Installing the monitoring watchdog...'",
      "sudo mkdir -p '\(self.watchdogSupportDirectory)'",
      "sudo cp '\(stagedConfig)' '\(self.watchdogSavedConfigPath)'",
      "sudo cp '\(stagedScript)' '\(self.watchdogScriptInstalledPath)'",
      "sudo cp '\(stagedPlist)' '\(self.watchdogDaemonPlistPath)'",
      "sudo chown root:wheel '\(self.watchdogSavedConfigPath)' '\(self.watchdogScriptInstalledPath)' '\(self.watchdogDaemonPlistPath)'",
      "sudo chmod 600 '\(self.watchdogSavedConfigPath)'",
      "sudo chmod 755 '\(self.watchdogScriptInstalledPath)'",
      "sudo chmod 644 '\(self.watchdogDaemonPlistPath)'",
      "sudo /bin/launchctl unload -w '\(self.watchdogDaemonPlistPath)' 2>/dev/null",
      "sudo /bin/launchctl load -w '\(self.watchdogDaemonPlistPath)'"
    ]
  }

  /// Privileged commands that unload and delete the watchdog and its files.
  private func watchdogRemovalScriptLines() -> [String] {
    return [
      "echo '🛡  Removing the monitoring watchdog...'",
      // Bootout by label first — this works even if the plist file is already
      // gone, so the daemon can't be left loaded with no way to unload it.
      "sudo /bin/launchctl bootout system/\(self.watchdogDaemonLabel) 2>/dev/null",
      "sudo /bin/launchctl unload -w '\(self.watchdogDaemonPlistPath)' 2>/dev/null",
      "sudo rm -f '\(self.watchdogDaemonPlistPath)'",
      "sudo rm -rf '\(self.watchdogSupportDirectory)'"
    ]
  }

  /// The watchdog shell script, run as root by launchd at boot and hourly.
  private func watchdogScriptContents() -> String {
    return """
    #!/bin/bash
    # PeakHour Enabler watchdog.
    # Re-applies the saved SNMP configuration and ensures snmpd is running, so that
    # monitoring survives macOS updates (which can reset snmpd.conf and disable the
    # snmpd LaunchDaemon). Installed as a system LaunchDaemon; run at boot and hourly.

    DESIRED='\(self.watchdogSavedConfigPath)'
    TARGET='\(SnmpConfigurator.SnmpConfigurationFilePath)'
    SNMPD_PLIST='\(self.snmpdLaunchAgentPath)'

    if [ -f "$DESIRED" ]; then
      if ! /usr/bin/cmp -s "$DESIRED" "$TARGET"; then
        /bin/cp "$DESIRED" "$TARGET"
        /bin/chmod 644 "$TARGET"
        /bin/launchctl unload -F -w "$SNMPD_PLIST" 2>/dev/null
        /bin/launchctl load -F -w "$SNMPD_PLIST"
        /bin/launchctl kickstart -k system/\(self.snmpdServiceLabel)
        exit 0
      fi
    fi

    if ! /bin/launchctl list | /usr/bin/grep -q \(self.snmpdServiceLabel); then
      /bin/launchctl load -F -w "$SNMPD_PLIST"
    fi
    """
  }

  /// The system LaunchDaemon plist that runs the watchdog script.
  private func watchdogDaemonPlistContents() -> String {
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>Label</key>
    \t<string>\(self.watchdogDaemonLabel)</string>
    \t<key>ProgramArguments</key>
    \t<array>
    \t\t<string>/bin/bash</string>
    \t\t<string>\(self.watchdogScriptInstalledPath)</string>
    \t</array>
    \t<key>RunAtLoad</key>
    \t<true/>
    \t<key>StartInterval</key>
    \t<integer>3600</integer>
    </dict>
    </plist>
    """
  }

  /// Returns true if the on-disk snmpd.conf has an active `com2sec` line carrying
  /// the community we intend to publish. Used to confirm the privileged step took
  /// effect before we advertise this Mac to other PeakHours.
  private func liveConfigUsesCurrentCommunity() -> Bool {
    guard let community = self.community,
          let contents = try? String(contentsOfFile: SnmpConfigurator.SnmpConfigurationFilePath, encoding: .utf8)
    else { return false }
    for line in contents.components(separatedBy: CharacterSet.newlines) {
      let words = line.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
      if words.first == "com2sec", words.contains(community) {
        return true
      }
    }
    return false
  }
  
  /// Stores the SNMP community in shared defaults so that it can be retrieved by the main PeakHour app.
  func storeConfigurationInSharedDefaults()
  {
    if let community = self.community {
      self.sharedDefaults?.set(community, forKey: self.SharedLocalSnmpCommunity)
      self.sharedDefaults?.set(Date.init(), forKey: self.PeakhourEnablerLastRunTime)
      self.sharedDefaults?.synchronize()
    }
  }

  /// Clears this Mac's shared SNMP configuration when monitoring is disabled, so
  /// the main PeakHour app and other Macs stop treating it as an enabled device.
  func removeSharedConfiguration()
  {
    // Clear the App Group community so the main app no longer reports SNMP enabled.
    self.sharedDefaults?.removeObject(forKey: self.SharedLocalSnmpCommunity)
    self.sharedDefaults?.removeObject(forKey: self.PeakhourEnablerLastRunTime)
    self.sharedDefaults?.synchronize()

    // Disable fully removes this Mac's shared configuration from iCloud, from both
    // the "new devices" list and the persistent enabled-devices list.
    if let deviceName = Host.current().localizedName {
      NSUbiquitousKeyValueStore.default.synchronize()
      for key in ["NewDevices", "EnabledDevices"] {
        if var devices = NSUbiquitousKeyValueStore.default.object(forKey: key) as? [String: Any] {
          devices.removeValue(forKey: deviceName)
          NSUbiquitousKeyValueStore.default.set(devices, forKey: key)
        }
      }
      NSUbiquitousKeyValueStore.default.synchronize()
    }
  }
  
  /// Returns true if PeakHour Enabler has been run and the SNMP community has been stored in Shared User Defaults.
  /// Typically called from the main PeakHour app.
  ///
  /// - Returns: YES if PeakHour Enabler has been run and SNMP has been enabled.
  @objc func hasPeakHourEnablerRun() -> Bool {
    self.sharedDefaults = UserDefaults.init(suiteName: SnmpConfigurator.SharedAppGroupIdentifier)
    self.sharedDefaults?.synchronize()
    
    if let peakhourEnablerLastRunTime = self.sharedDefaults?.value(forKey: self.PeakhourEnablerLastRunTime) as! Date? {
      if let peakhourEnablerLastCheckTime = self.sharedDefaults?.value(forKey: self.PeakhourEnablerLastCheckTime) as! Date? {
        if peakhourEnablerLastCheckTime < peakhourEnablerLastRunTime {
          self.sharedDefaults?.set(Date.init(), forKey: self.PeakhourEnablerLastCheckTime)
          return true
        }
      } else {
        self.sharedDefaults?.set(Date.init(), forKey: self.PeakhourEnablerLastCheckTime)
        return true
      }
    }
    self.sharedDefaults?.set(Date.init(), forKey: self.PeakhourEnablerLastCheckTime)
    return false
  }

  /// Stores this machine's configuration in iCloud.
  /// We store the machine in two dictionaries: EnabledDevices and NewDevices.
  /// EnabledDevices is the list shown in PeakHour's Configuration Assistant; NewDevices
  /// is the subset of newly-enabled devices that are removed as they are configured.
  /// Both entries for this Mac are removed when monitoring is disabled (see removeSharedConfiguration()).
  func storeConfigurationIniCloud()
  {
    if let community = self.community,
       let deviceName = Host.current().localizedName,
       let ipAddress = NetworkInformation.getActiveNetworkInterfaceInfo().ipAddress {
      let machineConfiguration: Dictionary<String, Any>? = ["ipAddress": ipAddress,
                                                            "snmpCommunity": community,
                                                            "lastUpdated": Date.init(),
                                                            "deviceName": deviceName]
      print("Storing info in iCloud for '\(deviceName)': \(String(describing: machineConfiguration))")
      
      // Get the existing array of enabled defaults from iCloud
      if (NSUbiquitousKeyValueStore.default.synchronize() == false) {
        print("Error synchronising iCloud key/value store.")
      }
      
      // Set Enabled Devices dictionary
      var enabledDevices = NSUbiquitousKeyValueStore.default.object(forKey: "EnabledDevices") as? [String: Dictionary<String, Any>?]
      print("Enabled devices: \(String(describing: enabledDevices))")
      if (enabledDevices == nil) {
        // Configuration doesn't exist; initialise with defaults.
        enabledDevices = [String: Dictionary?]()
      }
      enabledDevices?[deviceName] = machineConfiguration

      // Set New Devices dictionary
      var newDevices = NSUbiquitousKeyValueStore.default.object(forKey: "NewDevices") as? [String: Dictionary<String, Any>?]
      print("New devices: \(String(describing: newDevices))")
      if (newDevices == nil) {
        // Configuration doesn't exist; initialise with defaults.
        newDevices = [String: Dictionary?]()
      }
      newDevices?[deviceName] = machineConfiguration

      // Store in iCloud.
      NSUbiquitousKeyValueStore.default.set(enabledDevices, forKey: "EnabledDevices")
      NSUbiquitousKeyValueStore.default.set(newDevices, forKey: "NewDevices")
      NSUbiquitousKeyValueStore.default.synchronize()
      enabledDevices  = NSUbiquitousKeyValueStore.default.object(forKey: "EnabledDevices") as? [String: Dictionary<String, Any>?]
      newDevices      = NSUbiquitousKeyValueStore.default.object(forKey: "NewDevices") as? [String: Dictionary<String, Any>?]
      print("New iCloud configuration: EnabledDevices \(String(describing: enabledDevices))")
      print("New iCloud configuration: NewDevices \(String(describing: newDevices))")
    }
  }
  
  /// Signals the main PeakHour app (if it's running) to say Enabler was successfully run.
  func signalPeakHourApp()
  {
    if let url = URL(string: "PeakHourEnablerComplete:EnablerComplete"),
      NSWorkspace.shared.open(url) {
      print("URL was delivered successfully")
    }
  }

  /// Reads the SNMP community (set by PeakHour Enabler) from shared defaults.
  @objc func readCommunityFromSharedDefaults() -> String?
  {
    self.sharedDefaults = UserDefaults.init(suiteName: SnmpConfigurator.SharedAppGroupIdentifier)
    self.sharedDefaults?.synchronize()
    if let sharedLocalSnmpCommunity = self.sharedDefaults?.value(forKey: SharedLocalSnmpCommunity) as! String? {
      return sharedLocalSnmpCommunity
    } else {
      return nil
    }
  }
}
