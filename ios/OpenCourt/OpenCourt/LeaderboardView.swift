import SwiftUI

struct LeaderboardView: View {
    @State private var entries: [LeaderboardEntry] = []
    @State private var didLoad = false
    @State private var errorMessage: String?

    private var podium: [LeaderboardEntry] {
        Array(entries.prefix(3))
    }

    private var rest: [LeaderboardEntry] {
        Array(entries.dropFirst(min(entries.count, 3)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !didLoad && errorMessage == nil {
                    ProgressView("Loading leaderboard")
                        .tint(Purdue.gold)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            header
                            if entries.isEmpty {
                                Text("Check in or get tagged to show up here.")
                                    .font(.subheadline)
                                    .foregroundStyle(Purdue.muted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 28)
                            } else if podium.count == 3 {
                                podiumRow
                                if !rest.isEmpty {
                                    standings
                                }
                            } else {
                                standingsList(entries)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("OPENCOURT")
                        .font(.caption.weight(.bold))
                        .tracking(2.2)
                        .foregroundStyle(Purdue.gold)
                }
            }
            .purdueScreen()
            .refreshable { await load() }
            .task { await load() }
            .alert("Could not load leaderboard", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Purdue.gold.opacity(0.22), lineWidth: 10)
                Circle()
                    .stroke(Purdue.gold, lineWidth: 2)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Purdue.gold)
            }
            .frame(width: 92, height: 92)
            Text("PURDUE PICKLEBALL")
                .font(.caption.weight(.bold))
                .tracking(2.4)
                .foregroundStyle(Purdue.gold)
            Text("Leaderboard")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Most games played")
                .font(.subheadline)
                .foregroundStyle(Purdue.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(cardBackground)
    }

    private var podiumRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            podiumPlace(podium[1], height: 168)
            podiumPlace(podium[0], height: 196)
            podiumPlace(podium[2], height: 152)
        }
    }

    private var standings: some View {
        standingsList(rest)
    }

    // Lists the ranks below the podium.
    private func standingsList(_ rows: [LeaderboardEntry]) -> some View {
        VStack(spacing: 8) {
            ForEach(rows) { entry in
                HStack(spacing: 14) {
                    Text("\(entry.rank)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(entry.rank == 1 ? Purdue.gold : Purdue.muted)
                        .frame(width: 28, alignment: .leading)
                    Text(entry.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(gamesLabel(entry.games))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Purdue.gold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(cardBackground)
            }
        }
    }

    // Draws one of the top three places.
    private func podiumPlace(_ entry: LeaderboardEntry, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(medal(entry.rank))
                .font(.title2)
            Text(entry.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(gamesLabel(entry.games))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Purdue.gold)
            Spacer(minLength: 0)
            Text("\(entry.rank)")
                .font(.title.weight(.black))
                .foregroundStyle(Purdue.black)
                .frame(maxWidth: .infinity)
                .frame(height: entry.rank == 1 ? 46 : 36)
                .background(rankColor(entry.rank))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(cardBackground)
    }

    // Formats a count as "1 game" or "n games".
    private func gamesLabel(_ games: Int) -> String {
        games == 1 ? "1 game" : "\(games) games"
    }

    // Picks the medal for a rank.
    private func medal(_ rank: Int) -> String {
        switch rank {
        case 1: "🥇"
        case 2: "🥈"
        case 3: "🥉"
        default: ""
        }
    }

    // Picks the podium color for a rank.
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Purdue.gold
        case 2: Color(red: 0.78, green: 0.78, blue: 0.76)
        default: Color(red: 0.72, green: 0.48, blue: 0.28)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Purdue.card)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Purdue.gold.opacity(0.28), lineWidth: 1)
            }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // Reloads the leaderboard from the API.
    private func load() async {
        do {
            entries = try await API.leaderboard()
            didLoad = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
