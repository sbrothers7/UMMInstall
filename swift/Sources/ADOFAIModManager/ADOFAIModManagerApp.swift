import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ADOFAIModManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = InstallerViewModel()

    var body: some Scene {
        WindowGroup("macOS ADOFAI Mod Installer") {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 540, minHeight: 480)
                .task { vm.bootstrap() }
        }
    }
}
