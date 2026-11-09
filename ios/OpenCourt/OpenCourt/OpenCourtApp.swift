import SwiftUI

@main
struct OpenCourtApp: App {
    @StateObject private var player = CurrentPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
        }
    }
}
