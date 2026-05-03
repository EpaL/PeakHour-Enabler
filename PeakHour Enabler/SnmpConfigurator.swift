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
  static let SnmpConfigurationFilePath    = "/etc/snmp/snmpd.conf"
  let snmpConfigurationTemporaryFilePath  = "\(NSTemporaryDirectory())snmpd-out.conf"
  let snmpdServiceLabel                   = "org.net-snmp.snmpd"
  let snmpdLaunchAgentPath                = "/System/Library/LaunchDaemons/org.net-snmp.snmpd.plist"
  
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
    
    // Read the snmpd configuration file into a single string.
    do {
      fileContents = try String(contentsOfFile: SnmpConfigurator.SnmpConfigurationFilePath, encoding: String.Encoding.utf8 )
    } catch let error as NSError {
      print("An error occurred opening '\(SnmpConfigurator.SnmpConfigurationFilePath)': \(error)", terminator: "")
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
  func createNewSnmpdConfiguration() -> (Bool) {
    var outputLines: Array<String> = []
    
    // Read the existing snmpd configuration file into a single string.
    do {
      let fileContents = try String(contentsOfFile: SnmpConfigurator.SnmpConfigurationFilePath, encoding: String.Encoding.utf8 )
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
              if self.community != nil {
                outputLine = "com2sec local     localhost       \(self.community!)"
              }
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
              if (self.isNonLocalAccessEnabled == true && self.publicNetwork != nil && self.community != nil) {
                outputLine = "com2sec mynetwork \(self.publicNetwork!)       \(self.community!)"
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
          // Now write to to a file.
          print("writing new snmpd preferences to \(self.snmpConfigurationTemporaryFilePath)")
          try outputString.write(toFile: self.snmpConfigurationTemporaryFilePath, atomically: false, encoding: String.Encoding.utf8)
        } catch let error as NSError {
          print("Couldn't write to '\(self.snmpConfigurationTemporaryFilePath)' configuration file for writing: \(error)")
          return false;
        }
      }
    } catch let error as NSError {
      print("Couldn't open '\(SnmpConfigurator.SnmpConfigurationFilePath)' configuration file for reading: \(error)")

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
    let commandFileName             = "\(NSTemporaryDirectory())PeakHourEnabler-Control.command"
    let command                     = "/usr/bin/open"

    // Update the snmpd configuration
    _ = self.createNewSnmpdConfiguration()

    print("launching \(commandFileName)")
    // Update snmpd load status via launchctl.
    switch(serviceCommand) {
      case .start:
        commandFileContents = "#!/bin/bash\nclear\necho '▶️  Configuring and starting snmpd.'\necho 'ℹ️  This will allow your Mac to be monitored with PeakHour.'\necho\necho 'ℹ️  Enter your macOS password below.'\nsudo cp \(self.snmpConfigurationTemporaryFilePath) \(SnmpConfigurator.SnmpConfigurationFilePath)\necho '⏯  (Re)starting snmpd...'\nsudo \(snmpdStopAgentCommand)\nsudo \(snmpdLaunchAgentCommand)\necho '👍  snmpd started.\n'\necho 'Choose Terminal > Quit Terminal or press ⌘Q to continue.'\nosascript -e 'tell application \"System Events\" to keystroke \"q\" using command down'"
    case .startOnly:
      commandFileContents = "#!/bin/bash\nclear\necho '▶️  Starting snmpd.'\necho 'ℹ️  This will allow your Mac to be monitored with PeakHour.'\necho\necho 'ℹ️  Enter your macOS password below.'\necho '⏯  (Re)starting snmpd...'\nsudo \(snmpdStopAgentCommand)\nsudo \(snmpdLaunchAgentCommand)\necho '👍  snmpd started.\n'\necho 'Choose Terminal > Quit Terminal or press ⌘Q to continue.'\nosascript -e 'tell application \"System Events\" to keystroke \"q\" using command down'"
      case .stop:
        commandFileContents = "clear\necho '⏹  Stopping snmpd'\nsudo \(snmpdStopAgentCommand)\necho '👍  snmpd stopped.\n'\necho 'Press ⌘Q to continue.'\nosascript -e 'tell application \"System Events\" to keystroke \"q\" using command down'"
    }
    
    do {
      try commandFileContents.write(toFile: commandFileName,
                                    atomically: false,
                                    encoding: String.Encoding.utf8)
    } catch _ {
      print("An error occurred creating the service command script. Aborting.")
      return
    }
  
    // Make the script executable
    let attributes: [FileAttributeKey: Any] = [FileAttributeKey.posixPermissions: NSNumber(value: 0o750 as Int16)]
    let fileManager = FileManager.default
    do {
      try fileManager.setAttributes(attributes, ofItemAtPath: commandFileName)
    } catch _ {
      print("Error occurred making SNMP control script executable")
      return
    }

    _ = self.processInformation.ExecuteTask(command, arguments:["-W", commandFileName])
    
    // Store the configured SNMP community in shared defaults
    self.storeConfigurationInSharedDefaults()
    if (self.storeConfigurationInIcloud == true) {
      self.storeConfigurationIniCloud()
    }
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
  /// EnableDevices is meant to be semi-permanent record. Device records are never deleted. This is used to display in Configuration Assistant.
  /// NewDevices is a dictionary of newly-enabled devices that are removed as they are configured.
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
