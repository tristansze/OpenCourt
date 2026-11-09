import SwiftUI

@MainActor
final class CurrentPlayer: ObservableObject {
    @Published var user: User?
    private let storageKey = "opencourt.userId"

    func restore() async {
        let saved = UserDefaults.standard.integer(forKey: storageKey)
        guard saved != 0 else { return }
        guard let users = try? await API.users() else { return }
        user = users.first { $0.id == saved }
    }

    func signIn(_ user: User) {
        self.user = user
        UserDefaults.standard.set(user.id, forKey: storageKey)
    }
}

struct AccountSheet: View {
    @EnvironmentObject private var player: CurrentPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var users: [User] = []
    @State private var name = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose your name") {
                    ForEach(users) { user in
                        Button {
                            player.signIn(user)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .foregroundStyle(.white)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(Purdue.muted)
                            }
                        }
                    }
                }
                .listRowBackground(Purdue.card)

                Section("Or add yourself") {
                    TextField("Name", text: $name)
                    TextField("Purdue email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    Button(isSaving ? "Saving…" : "Create and sign in") {
                        Task { await create() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || email.isEmpty)
                }
                .listRowBackground(Purdue.card)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Who is playing?")
            .navigationBarTitleDisplayMode(.inline)
            .purdueScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadUsers() }
            .alert("Could not add you", isPresented: errorIsPresented) {
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() async {
        isSaving = true
        do {
            let created = try await API.createUser(name: name, email: email)
            player.signIn(created)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
