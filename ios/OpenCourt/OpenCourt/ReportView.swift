import SwiftUI

struct ReportView: View {
    @State private var facilities: [Facility] = []
    @State private var courts: [Court] = []
    @State private var courtTypes: [String] = []
    @State private var facilityId = -1
    @State private var courtId = -1
    @State private var courtType = ""
    @State private var startDate = ReportView.monthStart()
    @State private var endDate = ReportView.monthEnd()
    @State private var report: CourtUsageReport?
    @State private var isLoadingFilters = true
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Filters") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("Through", selection: $endDate, displayedComponents: .date)
                    Picker("Facility", selection: $facilityId) {
                        Text("All facilities").tag(-1)
                        ForEach(facilities) { facility in
                            Text(facility.name).tag(facility.id)
                        }
                    }
                    Picker("Court", selection: $courtId) {
                        Text("All courts").tag(-1)
                        ForEach(courts) { court in
                            Text("\(court.facilityName) · Court \(court.courtNumber)")
                                .tag(court.id)
                        }
                    }
                    Picker("Court type", selection: $courtType) {
                        Text("All types").tag("")
                        ForEach(courtTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    Button {
                        Task { await runReport() }
                    } label: {
                        if isRunning {
                            ProgressView()
                        } else {
                            Text("Generate Report")
                        }
                    }
                    .disabled(isRunning || isLoadingFilters)
                    .buttonStyle(.borderedProminent)
                    .tint(Purdue.gold)
                }
                .listRowBackground(Purdue.card)

                if let report {
                    Section("Summary") {
                        LabeledContent("Sessions", value: "\(report.totalSessions)")
                        LabeledContent("Finished sessions", value: "\(report.finishedSessions)")
                        LabeledContent("Unique students", value: "\(report.uniqueUsers)")
                        LabeledContent("Average duration", value: averageText(report.averageDurationMinutes))
                    }
                    .listRowBackground(Purdue.card)

                    Section("By court") {
                        if report.byCourt.isEmpty {
                            Text("No sessions in this range.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.byCourt) { row in
                                LabeledContent(
                                    "\(row.facilityName) · Court \(row.courtNumber)",
                                    value: "\(row.sessionCount)"
                                )
                            }
                        }
                    }
                    .listRowBackground(Purdue.card)

                    Section("Matching sessions") {
                        if report.sessions.isEmpty {
                            Text("No sessions in this range.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.sessions) { session in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(session.facilityName) · Court \(session.courtNumber)")
                                        .font(.headline)
                                    Text("\(session.userName) · \(session.timeLabel)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .listRowBackground(Purdue.card)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Court Usage")
            .purdueScreen()
            .task {
                guard facilities.isEmpty else { return }
                await loadFiltersAndReport()
            }
            .onChange(of: facilityId) { _, _ in
                courtId = -1
                Task {
                    do {
                        try await loadCourts()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Could not generate report", isPresented: errorIsPresented) {
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

    private func averageText(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        return String(format: "%.1f min", minutes)
    }

    private func loadFiltersAndReport() async {
        do {
            facilities = try await API.facilities()
            courtTypes = try await API.courtTypes()
            try await loadCourts()
            isLoadingFilters = false
            await runReport()
        } catch {
            errorMessage = error.localizedDescription
            isLoadingFilters = false
        }
    }

    private func loadCourts() async throws {
        let facility = facilityId == -1 ? nil : facilityId
        courts = try await API.courts(facilityId: facility)
    }

    private func runReport() async {
        isRunning = true
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let through = calendar.startOfDay(for: endDate)
        let end = calendar.date(byAdding: .day, value: 1, to: through) ?? through
        do {
            report = try await API.courtUsage(
                start: start,
                end: end,
                facilityId: facilityId == -1 ? nil : facilityId,
                courtId: courtId == -1 ? nil : courtId,
                courtType: courtType.isEmpty ? nil : courtType
            )
            isRunning = false
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    private static func monthStart() -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: parts) ?? Date()
    }

    private static func monthEnd() -> Date {
        let calendar = Calendar.current
        let start = monthStart()
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return calendar.date(byAdding: .day, value: -1, to: next) ?? start
    }
}
