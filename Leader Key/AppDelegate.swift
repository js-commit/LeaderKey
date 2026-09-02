import Cocoa
import Defaults
import KeyboardShortcuts
import Settings
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var controller: Controller!

  let statusItem = StatusItem()
  let config = UserConfig()

  var state: UserState!

  lazy var settingsWindowController = SettingsWindowController(
    panes: [
      Settings.Pane(
        identifier: .general, title: "General",
        toolbarIcon: NSImage(named: NSImage.preferencesGeneralName)!,
        contentView: { GeneralPane().environmentObject(self.config) }
      ),
      Settings.Pane(
        identifier: .advanced, title: "Advanced",
        toolbarIcon: NSImage(named: NSImage.advancedName)!,
        contentView: {
          AdvancedPane().environmentObject(self.config)
        }),
    ],
    style: .segmentedControl,
  )

  func applicationDidFinishLaunching(_: Notification) {

    guard
      ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    else { return }
    guard !isRunningTests() else { return }

    NSApp.mainMenu = MainMenu()

    config.ensureAndLoad()
    state = UserState(userConfig: config)
    controller = Controller(userState: state, userConfig: config)

    statusItem.handlePreferences = {
      self.showSettings()
    }
    statusItem.handleAbout = {
      NSApp.orderFrontStandardAboutPanel(nil)
    }
    statusItem.handleReloadConfig = {
      self.config.reloadFromFile()
    }
    statusItem.handleRevealConfig = {
      NSWorkspace.shared.activateFileViewerSelecting([self.config.url])
    }

    Task {
      for await value in Defaults.updates(.showMenuBarIcon) {
        if value {
          self.statusItem.enable()
        } else {
          self.statusItem.disable()
        }
      }
    }

    // Initialize status item according to current preference
    if Defaults[.showMenuBarIcon] {
      statusItem.enable()
    } else {
      statusItem.disable()
    }

    // Activation policy is managed solely by the Settings window

    registerGlobalShortcuts()
  }

  func activate() {
    if self.controller.window.isKeyWindow {
      switch Defaults[.reactivateBehavior] {
      case .hide:
        self.hide()
      case .reset:
        self.controller.userState.clear()
      case .nothing:
        return
      }
    } else if self.controller.window.isVisible {
      // should never happen as the window will self-hide when not key
      self.controller.window.makeKeyAndOrderFront(nil)
    } else {
      self.show()
    }
  }

  public func registerGlobalShortcuts() {
    KeyboardShortcuts.removeAllHandlers()

    KeyboardShortcuts.onKeyDown(for: .activate) {
      self.activate()
    }

    for groupKey in Defaults[.groupShortcuts] {
      print("Registering shortcut for \(groupKey)")
      KeyboardShortcuts.onKeyDown(for: KeyboardShortcuts.Name("group-\(groupKey)")) {
        if !self.controller.window.isVisible {
          self.activate()
        }
        self.processKeys([groupKey])
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Config saves automatically on changes
  }

  @IBAction
  func settingsMenuItemActionHandler(_: NSMenuItem) {
    showSettings()
  }

  func show() {
    controller.show()
  }

  func hide() {
    controller.hide()
  }

  func isRunningTests() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    guard environment["XCTestSessionIdentifier"] != nil else { return false }
    return true
  }

  // MARK: - URL Scheme Handling

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      handleURL(url)
    }
  }

  private func handleURL(_ url: URL) {
    guard url.scheme == "leaderkey" else { return }

    if url.host == "settings" {
      showSettings()
      return
    }
    if url.host == "about" {
      NSApp.orderFrontStandardAboutPanel(nil)
      return
    }

    show()

    if url.host == "navigate",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let keysParam = queryItems.first(where: { $0.name == "keys" })?.value
    {
      let keys = keysParam.split(separator: ",").map(String.init)
      processKeys(keys)
    }
  }

  private func processKeys(_ keys: [String]) {
    guard !keys.isEmpty else { return }

    controller.handleKey(keys[0])

    if keys.count > 1 {
      let remainingKeys = Array(keys.dropFirst())

      var delayMs = 100
      for key in remainingKeys {
        delay(delayMs) { [weak self] in
          self?.controller.handleKey(key)
        }
        delayMs += 100
      }
    }
  }

  // MARK: - Activation Policy: Only Settings Visibility Controls It

  private func showSettings() {
    // Behave like a normal app while Settings is open
    NSApp.setActivationPolicy(.regular)
    settingsWindowController.show()
    NSApp.activate(ignoringOtherApps: true)
    settingsWindowController.window?.delegate = self
  }

  // Revert to accessory when Settings window closes
  func windowWillClose(_ notification: Notification) {
    guard let win = notification.object as? NSWindow,
      win == settingsWindowController.window
    else { return }
    NSApp.setActivationPolicy(.accessory)
  }
}
