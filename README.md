# PeakHour Enabler

PeakHour Enabler is a small macOS utility that helps configure the built-in `snmpd` service so a Mac can be monitored by PeakHour from another Mac on the network.

The app is intentionally narrow: it reads the local SNMP configuration, can generate an SNMP community string, enables remote access for the current local network, starts or restarts `snmpd`, and automatically shares this Mac's monitoring configuration with PeakHour via iCloud configuration.

PeakHour Enabler is designed to work with PeakHour, the main macOS Internet performance monitoring app. Learn more about PeakHour at [peakhourapp.com](https://peakhourapp.com/).

## Requirements

- macOS 14.6 or later for the current Xcode project settings
- Xcode 17 or later
- Administrator privileges when enabling or restarting `snmpd`

## Building

Open `PeakHour Enabler.xcodeproj` in Xcode and build the `PeakHour Enabler` scheme.

For command-line verification without local signing:

```sh
xcodebuild build \
  -project "PeakHour Enabler.xcodeproj" \
  -scheme "PeakHour Enabler" \
  -configuration Debug \
  -derivedDataPath /tmp/PeakHourEnablerDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Official PeakHour builds use Digitician signing settings and the PeakHour app group. If you are building your own fork, set your own development team, bundle identifier, and app group before shipping a signed build.

## Notes

- PeakHour and PeakHour Enabler are trademarks of Digitician Inc.

## License

This project is released under the MIT License. See `LICENSE` for details.
