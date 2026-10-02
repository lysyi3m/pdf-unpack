import SwiftUI

struct PasswordSheet: View {
    @EnvironmentObject var state: AppState
    @State private var password = ""
    @State private var showError = false
    #if os(iOS)
    @FocusState private var fieldFocused: Bool
    #endif

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    private var message: String {
        "“\(state.fileName ?? "This PDF")” is encrypted. Enter its password to list the embedded files."
    }

    private var errorLabel: some View {
        Label("Incorrect password. Try again.", systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
    }

    #if os(macOS)
    private var macBody: some View {
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
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(submit)
                    .onChange(of: password) { showError = false }

                if showError { errorLabel }

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
    #else
    private var iosBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Password Required")
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("Password", text: $password)
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit(submit)
                .onChange(of: password) { showError = false }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(.fill.tertiary, in: .rect(cornerRadius: 14))

            if showError { errorLabel }

            VStack(spacing: 8) {
                Button(action: submit) {
                    Text("Unlock").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(password.isEmpty)

                Button("Cancel") { state.cancelPassword() }
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .onAppear { fieldFocused = true }
        .presentationDetents([.medium])
        // A swipe down would hide the sheet without resetting the document; Cancel does both.
        .interactiveDismissDisabled()
    }
    #endif

    private func submit() {
        guard !password.isEmpty else { return }
        if !state.submitPassword(password) {
            showError = true
        }
    }
}
