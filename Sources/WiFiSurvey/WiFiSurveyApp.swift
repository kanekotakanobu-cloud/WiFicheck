import AppKit
import SwiftUI

@main
struct WiFiSurveyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recorder = Recorder()

    var body: some Scene {
        WindowGroup("Wi-Fi 現場調査") {
            ContentView(recorder: recorder, location: recorder.location)
                .frame(minWidth: 900, minHeight: 720)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
