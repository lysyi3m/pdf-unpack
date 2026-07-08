import SwiftUI

struct PasswordSheet: View {
    @EnvironmentObject var state: AppState
    @State private var password = ""
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Password Required").font(.headline)
            Text("“\(state.fileName ?? "This PDF")” is encrypted. Enter its password to list the embedded files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .onChange(of: password) { showError = false }

            if showError {
                Label("Incorrect password. Try again.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { state.cancelPassword() }
                    .keyboardShortcut(.cancelAction)
                Button("Unlock", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        if !state.submitPassword(password) {
            showError = true
        }
    }
}
