import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            OccupancyView()
                .tabItem {
                    Label("Courts", systemImage: "sportscourt")
                }
            LeaderboardView()
                .tabItem {
                    Label("Leaders", systemImage: "trophy")
                }
            ReportView()
                .tabItem {
                    Label("Usage", systemImage: "chart.bar")
                }
        }
        .tint(Purdue.gold)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(CurrentPlayer())
}
