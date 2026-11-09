import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            OccupancyView()
                .tabItem {
                    Label("Courts", systemImage: "sportscourt")
                }
            SessionsView()
                .tabItem {
                    Label("Sessions", systemImage: "person.crop.circle.badge.checkmark")
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
}
