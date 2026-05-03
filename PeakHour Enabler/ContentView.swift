//
//  ContentView.swift
//  PeakHour Enabler
//
//  Created by Edward Lawford on 17/04/2026.
//  Copyright © 2026 Digitician Inc. All rights reserved.
//

import SwiftUI
import SystemConfiguration

struct ContentView: View {
  @ObservedObject var configurator: SnmpConfigurator
  @State private var showAdvanced = false
  @State private var isCommunityVisible = false
  @State private var showManualDetails = false
  private let hostname: String = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "This Mac"

  var appVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    return "\(version) (\(build))"
  }

  var body: some View {
    ZStack {
      Rectangle()
        .fill(.thinMaterial)
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      VStack(spacing: 0) {
        if configurator.isSnmpdRunning {
          activeView
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
          setupView
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
      }
      .padding(32)
    }
    .frame(width: 460, height: 540)
    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: configurator.isSnmpdRunning)
    .onAppear {
      // Ensure the window comes to front on launch
      DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
      }
    }
  }

  // MARK: - Setup View (snmpd not running)

  private var setupView: some View {
    VStack(spacing: 0) {
      // Hero group: Connection visual + Headline + Subheadline
      VStack(spacing: 12) {
        VStack(spacing: 12) {
          HStack(alignment: .center, spacing: 24) {
            // PeakHour Icon (master app icon)
            Image(nsImage: NSImage(named: NSImage.applicationIconName)!)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 64, height: 64)
              .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)

            // Network Connection Line
            Path { path in
              path.move(to: CGPoint(x: 0, y: 0))
              path.addLine(to: CGPoint(x: 40, y: 0))
            }
            .stroke(Color.secondary.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            .frame(width: 40, height: 3)

            // This Mac Icon (dynamic per hardware type)
            VStack(spacing: 6) {
              Image(systemName: MacModelIcon.currentMacSymbolName())
                .font(.system(size: 42, weight: .light))
                .foregroundColor(.accentColor)

              // Dynamic Hostname
              Text(hostname)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .padding(.bottom, 16)

        Text("Enable Remote Monitoring")
          .font(.largeTitle)
          .fontWeight(.bold)

        Text("Monitor this Mac from another Mac running PeakHour.")
          .font(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.bottom, 24)

      // Watchdog feature bullet
      HStack(spacing: 6) {
        Image(systemName: "checkmark.shield.fill")
          .foregroundColor(.green)
        Text("Includes a self-healing watchdog to survive macOS updates.")
          .foregroundColor(.secondary)
          .font(.subheadline)
      }
      .padding(.bottom, 16)

      // Advanced Configuration toggle
      HStack(spacing: 4) {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .rotationEffect(.degrees(showAdvanced ? 90 : 0))
        Text("Advanced Configuration")
      }
      .font(.subheadline)
      .foregroundColor(.accentColor)
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          showAdvanced.toggle()
        }
      }
      .padding(.bottom, 12)

      // Advanced fields
      if showAdvanced {
        VStack(alignment: .leading, spacing: 6) {
          Text("SNMP Community String")
            .font(.caption)
            .foregroundColor(.secondary)
          HStack(spacing: 12) {
            TextField("Community", text: Binding(
              get: { configurator.community ?? "" },
              set: { configurator.community = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(configurator.autoGenerateSnmpCommunity)

            Toggle("Auto-generate", isOn: $configurator.autoGenerateSnmpCommunity)
              .fixedSize()
              .onChange(of: configurator.autoGenerateSnmpCommunity) { _ in
                configurator.toggleAutoGenerateCommunity()
              }
          }
        }
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      // Push footer to bottom
      Spacer(minLength: 20)

      // Footer: iCloud info + Enable button
      VStack(spacing: 12) {
        HStack(spacing: 4) {
          Image(systemName: "icloud.fill")
          Text("This Mac will be visible to other PeakHours via iCloud.")
        }
        .font(.caption)
        .foregroundColor(.secondary)

        Button {
          configurator.controlSnmpd(.start)
        } label: {
          Text("Enable Monitoring")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }

      // Version
      Text("PeakHour Enabler v\(appVersion)")
        .font(.caption2)
        .foregroundColor(.secondary.opacity(0.6))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 16)
    }
  }

  // MARK: - Active View (snmpd running)

  private var activeView: some View {
    VStack(spacing: 0) {
      // Hero group
      VStack(spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 72, weight: .light))
          .foregroundColor(.green)
          .shadow(color: .green.opacity(0.25), radius: 16, y: 6)

        Text("This Mac is Ready")
          .font(.largeTitle)
          .fontWeight(.bold)

        Text("This Mac will now appear in PeakHour's Configuration Assistant on other Macs.")
          .font(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.bottom, 24)

      // "Mental Model Bridge" card — simulates PeakHour's device list
      Text("Look for this device in PeakHour:")
        .font(.caption)
        .foregroundColor(.secondary.opacity(0.8))
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(alignment: .center, spacing: 12) {
        Image(systemName: MacModelIcon.currentMacSymbolName())
          .font(.title2)
          .foregroundColor(.accentColor)

        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Text(hostname)
              .fontWeight(.medium)
          }
          Text(configurator.ipAddress ?? "Unknown IP")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        Text("SNMP")
          .font(.caption2)
          .fontWeight(.semibold)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.2))
          .cornerRadius(4)
      }
      .padding(14)
      .background(.regularMaterial)
      .cornerRadius(10)
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
      .padding(.bottom, 12)

      // "Break Glass" manual connection details toggle
      HStack(alignment: .center, spacing: 4) {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .rotationEffect(.degrees(showManualDetails ? 90 : 0))
        Text("SNMP Configuration Details")
      }
      .font(.subheadline)
      .foregroundColor(.secondary)
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          showManualDetails.toggle()
        }
      }
      .padding(.bottom, 8)

      if showManualDetails {
        VStack(alignment: .leading, spacing: 8) {
          detailRow(label: "Hostname", value: configurator.ipAddress ?? "Unknown", copyable: true, font: .callout)
          Divider()
          detailRow(label: "SNMP Version", value: "v2c", copyable: false, font: .callout)
          Divider()
          HStack {
            Text("Community")
              .font(.callout)
              .foregroundColor(.secondary)
              .frame(width: 100, alignment: .trailing)
            if isCommunityVisible {
              Text(configurator.community ?? "")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            } else {
              Text(String(repeating: "•", count: configurator.community?.count ?? 8))
                .font(.system(.callout, design: .monospaced))
            }
            Spacer()
            Button {
              isCommunityVisible.toggle()
            } label: {
              Image(systemName: isCommunityVisible ? "eye.slash" : "eye")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help(isCommunityVisible ? "Hide community string" : "Show community string")
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(configurator.community ?? "", forType: .string)
            } label: {
              Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
          }
        }
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      // Push footer to bottom
      Spacer(minLength: 20)

      // Bottom group: Watchdog status + Disable button
      VStack(spacing: 12) {
        HStack(spacing: 6) {
          Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundColor(.green)
          Text("Watchdog Active: Protecting config from OS updates.")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Button(action: {
          configurator.controlSnmpd(.stop)
        }) {
          Text("Disable Monitoring")
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }

      // Version
      Text("PeakHour Enabler v\(appVersion)")
        .font(.caption2)
        .foregroundColor(.secondary.opacity(0.6))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 16)
    }
  }

  // MARK: - Helpers

  private func detailRow(label: String, value: String, copyable: Bool, font: Font = .footnote) -> some View {
    HStack {
      Text(label)
        .font(font)
        .foregroundColor(.secondary)
        .frame(width: 100, alignment: .trailing)
      Text(value)
        .font(.system(font == .callout ? .callout : .footnote, design: .monospaced))
        .textSelection(.enabled)
      Spacer()
      if copyable {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(value, forType: .string)
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Copy to clipboard")
      }
    }
  }
}
