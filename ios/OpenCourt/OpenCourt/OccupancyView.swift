import SwiftUI

struct OccupancyView: View {
    @State private var occupancy: Occupancy?
    @State private var checkInCourt: OccupancyCourt?
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
            .purdueScreen()
            .refreshable { await load() }
            .task { await load() }
            .alert("Could not update courts", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $checkInCourt) { court in
                CheckInSheet(court: court) { await load() }
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
                .fill(court.inUse ? Purdue.usageColor(100) : Purdue.gold.opacity(0.45))
                .frame(width: 4, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Court \(court.courtNumber)")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(court.inUse ? inUseDetail(court) : "Open · \(court.courtType)")
                    .font(.subheadline)
                    .foregroundStyle(Purdue.muted)
            }
            Spacer(minLength: 8)
            if court.inUse {
                Button("End") {
                    Task { await end(court) }
                }
                .buttonStyle(PurdueOutlineButton())
            } else {
                Button("Play") {
                    checkInCourt = court
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
        guard let sessionId = court.sessionId else { return }
        do {
            _ = try await API.endSession(id: sessionId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PurdueGoldButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Purdue.gold.opacity(configuration.isPressed ? 0.75 : 1))
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

    @Environment(\.dismiss) private var dismiss
    @State private var users: [User] = []
    @State private var userId = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Court", value: court.courtNumber)
                    Picker("Student", selection: $userId) {
                        ForEach(users) { user in
                            Text(user.name).tag(user.id)
                        }
                    }
                }
                .listRowBackground(Purdue.card)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Start playing")
            .navigationBarTitleDisplayMode(.inline)
            .purdueScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Check in") { Task { await checkIn() } }
                        .disabled(isSaving || userId == 0)
                }
            }
            .task { await loadUsers() }
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

    private func loadUsers() async {
        do {
            users = try await API.users()
            userId = users.first?.id ?? 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkIn() async {
        isSaving = true
        do {
            _ = try await API.startSession(userId: userId, courtId: court.id)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
