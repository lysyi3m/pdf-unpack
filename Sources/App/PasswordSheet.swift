import SwiftUI

struct PasswordSheet: View {
    @EnvironmentObject var state: AppState
    @State private var password = ""
    @State private var showError = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password Required")
                        .font(.headline)
                    Text("“\(state.fileName ?? "This PDF")” is encrypted. Enter its password to list the embedded files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(submit)
                    .onChange(of: password) { showError = false }

                if showError {
                    Label("Incorrect password. Try again.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { state.cancelPassword() }
                        .keyboardShortcut(.cancelAction)
                    Button("Unlock", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(password.isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        if !state.submitPassword(password) {
            showError = true
        }
    }
}
