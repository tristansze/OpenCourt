import SwiftUI

struct OccupancyView: View {
    @EnvironmentObject private var player: CurrentPlayer
    @State private var occupancy: Occupancy?
    @State private var checkInCourt: OccupancyCourt?
    @State private var showingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let occupancy {
                    ScrollView {
                        VStack(spacing: 22) {
                            hero(occupancy)
                            ForEach(occupancy.facilities) { facility in
                                facilityCard(facility)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                    }
                } else {
                    ProgressView("Loading courts")
                        .tint(Purdue.gold)
                }
            }
            .navigationTitle("OpenCourt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(player.user?.name ?? "Sign in") {
                        showingAccount = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .purdueScreen()
            .refreshable { await load() }
            .task {
                await player.restore()
                await load()
            }
            .alert("Could not update courts", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $checkInCourt) { court in
                CheckInSheet(court: court) { await load() }
            }
            .sheet(isPresented: $showingAccount) {
                AccountSheet()
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func hero(_ occupancy: Occupancy) -> some View {
        VStack(spacing: 16) {
            Text("PURDUE PICKLEBALL")
                .font(.caption.weight(.bold))
                .tracking(2.4)
                .foregroundStyle(Purdue.gold)
            UsageRing(percent: occupancy.inUsePercent)
                .frame(width: 230, height: 230)
            Text(Purdue.usageLabel(occupancy.inUsePercent))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Purdue.usageColor(occupancy.inUsePercent))
            Text("\(occupancy.courtsInUse) of \(occupancy.courtCount) courts in use")
                .font(.subheadline)
                .foregroundStyle(Purdue.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
        .background(cardBackground)
    }

    private func facilityCard(_ facility: OccupancyFacility) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(facility.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(facility.courtsInUse) of \(facility.courtCount) in use")
                        .font(.subheadline)
                        .foregroundStyle(Purdue.muted)
                }
                Spacer()
                UsageRing(percent: facility.inUsePercent, lineWidth: 6, showsCaption: false)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Text("\(facility.inUsePercent)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Purdue.gold)
                    }
            }
            ForEach(facility.courts) { court in
                courtRow(court)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func courtRow(_ court: OccupancyCourt) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(court.inUse ? Purdue.usageColor(100) : Purdue.openGreen)
                .frame(width: 4, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Court \(court.courtNumber)")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(court.inUse ? inUseDetail(court) : "Open · \(court.courtType)")
                    .font(.subheadline)
                    .foregroundStyle(court.inUse ? Purdue.muted : Purdue.gold)
            }
            Spacer(minLength: 8)
            if court.inUse, court.playerUserId == player.user?.id {
                VStack(spacing: 6) {
                    Button("End") {
                        Task { await end(court) }
                    }
                    .buttonStyle(PurdueOutlineButton())
                    Button("Cancel") {
                        Task { await cancel(court) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Purdue.muted)
                }
            } else if !court.inUse {
                Button("Play") {
                    if player.user == nil {
                        showingAccount = true
                    } else {
                        checkInCourt = court
                    }
                }
                .buttonStyle(PurdueGoldButton())
            }
        }
    }

    private func inUseDetail(_ court: OccupancyCourt) -> String {
        let name = court.playerName ?? "In use"
        let time = court.startedAt?.formatted(date: .omitted, time: .shortened) ?? ""
        return time.isEmpty ? name : "\(name) · since \(time)"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Purdue.card)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Purdue.gold.opacity(0.28), lineWidth: 1)
            }
    }

    private func load() async {
        do {
            occupancy = try await API.occupancy()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func end(_ court: OccupancyCourt) async {
        guard let sessionId = court.sessionId, let userId = player.user?.id else { return }
        do {
            _ = try await API.endSession(id: sessionId, userId: userId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel(_ court: OccupancyCourt) async {
        guard let sessionId = court.sessionId, let userId = player.user?.id else { return }
        do {
            try await API.deleteSession(id: sessionId, userId: userId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PurdueGoldButton: ButtonStyle {
    var color: Color = Purdue.gold

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(Purdue.black)
            .clipShape(Capsule())
    }
}

struct PurdueOutlineButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Purdue.gold)
            .overlay {
                Capsule().stroke(Purdue.gold.opacity(configuration.isPressed ? 0.5 : 1), lineWidth: 1)
            }
    }
}

struct CheckInSheet: View {
    let court: OccupancyCourt
    let onSaved: () async -> Void

    @EnvironmentObject private var player: CurrentPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var users: [User] = []
    @State private var taggedIds: Set<Int> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var others: [User] {
        users.filter { $0.id != player.user?.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .stroke(Purdue.gold.opacity(0.22), lineWidth: 14)
                        Circle()
                            .stroke(Purdue.gold, lineWidth: 2)
                        VStack(spacing: 2) {
                            Text("COURT")
                                .font(.caption.weight(.bold))
                                .tracking(2.2)
                                .foregroundStyle(Purdue.gold)
                            Text(court.courtNumber)
                                .font(.system(size: 54, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(court.courtType.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(1.6)
                                .foregroundStyle(Purdue.muted)
                        }
                    }
                    .frame(width: 156, height: 156)
                    .padding(.top, 8)

                    VStack(spacing: 4) {
                        Text("CHECKING IN AS")
                            .font(.caption.weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(Purdue.gold)
                        Text(player.user?.name ?? "Sign in first")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TAG YOUR GROUP")
                            .font(.caption.weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(Purdue.gold)
                        Text("Tagged students get a game on the leaderboard. The court still shows your name.")
                            .font(.footnote)
                            .foregroundStyle(Purdue.muted)
                        if others.isEmpty {
                            Text("No other students to tag yet.")
                                .font(.subheadline)
                                .foregroundStyle(Purdue.muted)
                                .padding(.top, 4)
                        } else {
                            ForEach(others) { user in
                                let selected = taggedIds.contains(user.id)
                                Button {
                                    if selected {
                                        taggedIds.remove(user.id)
                                    } else {
                                        taggedIds.insert(user.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.white)
                                            Text(user.email)
                                                .font(.caption)
                                                .foregroundStyle(Purdue.muted)
                                        }
                                        Spacer()
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(selected ? Purdue.gold : Purdue.muted)
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selected ? Purdue.gold.opacity(0.14) : Purdue.card)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(
                                                        selected ? Purdue.gold : Purdue.gold.opacity(0.22),
                                                        lineWidth: 1
                                                    )
                                            }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Task { await checkIn() }
                    } label: {
                        Text(isSaving ? "Checking in…" : "Check in")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PurdueGoldButton())
                    .disabled(isSaving || player.user == nil)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Start playing")
            .navigationBarTitleDisplayMode(.inline)
            .purdueScreen()
            .presentationDetents([.large])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                users = (try? await API.users()) ?? []
            }
            .alert("Could not check in", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func checkIn() async {
        guard let userId = player.user?.id else { return }
        isSaving = true
        do {
            _ = try await API.startSession(
                courtId: court.id,
                userId: userId,
                playerIds: Array(taggedIds)
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
