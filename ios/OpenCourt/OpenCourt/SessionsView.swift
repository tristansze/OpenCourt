import SwiftUI

struct SessionsView: View {
    @State private var sessions: [CourtSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var creating = false
    @State private var editing: CourtSession?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && sessions.isEmpty {
                    ProgressView("Loading sessions")
                } else if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "figure.run",
                        description: Text("Check in when you start playing.")
                    )
                } else {
                    List {
                        ForEach(sessions) { session in
                            Button {
                                editing = session
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Purdue.card)
                        }
                        .onDelete(perform: delete)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Sessions")
            .scrollContentBackground(.hidden)
            .purdueScreen()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Check in")
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .alert("Could not update sessions", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $creating) {
                SessionFormView(existing: nil) { await load() }
            }
            .sheet(item: $editing) { session in
                SessionFormView(existing: session) { await load() }
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func sessionRow(_ session: CourtSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(session.facilityName) · Court \(session.courtNumber)")
                .font(.headline)
            Text(session.userName)
                .foregroundStyle(Purdue.gold)
            Text(session.timeLabel)
                .font(.subheadline)
                .foregroundStyle(Purdue.muted)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            sessions = try await API.sessions()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { sessions[$0] }
        Task {
            do {
                for session in removed {
                    try await API.deleteSession(id: session.id)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            await load()
        }
    }
}

struct SessionFormView: View {
    let existing: CourtSession?
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var users: [User] = []
    @State private var facilities: [Facility] = []
    @State private var courts: [Court] = []
    @State private var userId = 0
    @State private var facilityId = 0
    @State private var courtId = 0
    @State private var startedAt = Date()
    @State private var endedAt = Date()
    @State private var stillPlaying = true
    @State private var didLoad = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading courts")
                } else {
                    Form {
                        Section {
                        Picker("Student", selection: $userId) {
                            ForEach(users) { user in
                                Text(user.name).tag(user.id)
                            }
                        }
                        Picker("Facility", selection: $facilityId) {
                            ForEach(facilities) { facility in
                                Text(facility.name).tag(facility.id)
                            }
                        }
                        Picker("Court", selection: $courtId) {
                            ForEach(courts) { court in
                                Text("Court \(court.courtNumber) · \(court.courtType)")
                                    .tag(court.id)
                            }
                        }
                        if existing != nil {
                            DatePicker("Started", selection: $startedAt)
                            Toggle("Still playing", isOn: $stillPlaying)
                            if !stillPlaying {
                                DatePicker("Ended", selection: $endedAt)
                            }
                        }
                        if existing?.isActive == true {
                            Button("End session") {
                                Task { await endSession() }
                            }
                        }
                        if existing != nil {
                            Button("Delete Session", role: .destructive) {
                                confirmDelete = true
                            }
                        }
                        }
                        .listRowBackground(Purdue.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(existing == nil ? "Check in" : "Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .purdueScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Check in" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || isLoading || courtId == 0 || userId == 0)
                }
            }
            .task { await loadOptions() }
            .onChange(of: facilityId) { _, newValue in
                guard didLoad else { return }
                Task { await reloadCourts(facilityId: newValue) }
            }
            .alert("Could not save", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Delete this session?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await deleteSession() }
                }
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadOptions() async {
        do {
            users = try await API.users()
            facilities = try await API.facilities()
            if let existing {
                userId = existing.userId
                facilityId = existing.facilityId
                startedAt = existing.startedAt
                if let ended = existing.endedAt {
                    endedAt = ended
                    stillPlaying = false
                } else {
                    endedAt = Date()
                    stillPlaying = true
                }
                courts = try await API.courts(facilityId: existing.facilityId)
                courtId = existing.courtId
            } else {
                userId = users.first?.id ?? 0
                facilityId = facilities.first?.id ?? 0
                courts = try await API.courts(facilityId: facilityId == 0 ? nil : facilityId)
                courtId = courts.first?.id ?? 0
            }
            didLoad = true
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func reloadCourts(facilityId: Int) async {
        do {
            let loaded = try await API.courts(facilityId: facilityId)
            courts = loaded
            if !loaded.contains(where: { $0.id == courtId }) {
                courtId = loaded.first?.id ?? 0
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        do {
            if let existing {
                let input = SessionUpdate(
                    userId: userId,
                    courtId: courtId,
                    startedAt: startedAt,
                    endedAt: stillPlaying ? nil : endedAt
                )
                _ = try await API.updateSession(id: existing.id, input)
            } else {
                _ = try await API.startSession(userId: userId, courtId: courtId)
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func endSession() async {
        guard let existing else { return }
        do {
            _ = try await API.endSession(id: existing.id)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSession() async {
        guard let existing else { return }
        do {
            try await API.deleteSession(id: existing.id)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
