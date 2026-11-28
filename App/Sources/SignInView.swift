import SwiftUI
import UIKit
import KeepCore

/// Email, then the 6-digit code. This device gets the manage tier. The brand's front is dark: this
/// page is black in both themes.
struct SignInView: View {
    @EnvironmentObject var model: AppModel
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var problem: String?
    @State private var showServer = false
    @State private var server = ""
    @FocusState private var focus: Field?

    enum Field { case email, code, server }

    var body: some View {
        ZStack {
            Theme.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        BrandMark(forceDark: true, size: 52)
                        BrandName(size: 28)
                    }
                    .padding(.top, 48)
                    if codeSent { codeStep } else { emailStep }
                    if let problem {
                        Text(problem).font(Theme.secondary).foregroundStyle(Theme.paper).accessibilityIdentifier("signin.problem")
                    }
                    serverRow.padding(.top, 32)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { server = model.store.serverURL.absoluteString }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("signin.email.prompt")).font(Theme.body).foregroundStyle(Theme.paper)
            TextField(L("signin.email"), text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.continue)
                .onSubmit { Task { await sendCode() } }
                .modifier(DarkField())
                .accessibilityIdentifier("signin.email")
            Button(L("signin.send_code")) { Task { await sendCode() } }
                .buttonStyle(SolidButton())
                .disabled(busy || !email.contains("@"))
                .opacity(email.contains("@") ? 1 : 0.5)
                .accessibilityIdentifier("signin.send")
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("signin.code.prompt", email)).font(Theme.body).foregroundStyle(Theme.paper)
            TextField(L("signin.code"), text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .modifier(DarkField())
                .accessibilityIdentifier("signin.code")
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                    if digits.count == 6 { Task { await signIn() } }
                }
            HStack(spacing: 16) {
                Button(L("signin.other_email")) {
                    codeSent = false
                    code = ""
                    problem = nil
                }
                Button(L("signin.resend")) { Task { await sendCode() } }
            }
            .buttonStyle(TextLink())
        }
    }

    /// Unobtrusive: for self-hosters, and for testing against a local core.
    private var serverRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showServer.toggle() } label: {
                Text(L("signin.server", URL(string: server)?.host ?? server))
            }
            .buttonStyle(TextLink())
            .accessibilityIdentifier("signin.server")
            if showServer {
                TextField("https://keepessence.app", text: $server)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .server)
                    .modifier(DarkField())
                    .accessibilityIdentifier("signin.server.field")
                    .onSubmit { applyServer() }
            }
        }
    }

    @discardableResult
    private func applyServer() -> Bool {
        guard let url = KeepStore.parseServer(server) else {
            problem = L("signin.server.bad")
            return false
        }
        model.store.serverURL = url
        server = url.absoluteString
        return true
    }

    private func client() -> APIClient { APIClient(baseURL: model.store.serverURL, credential: nil) }

    private func sendCode() async {
        guard !busy, email.contains("@"), applyServer() else { return }
        busy = true
        defer { busy = false }
        problem = nil
        do {
            try await client().requestLoginCode(email: email.trimmingCharacters(in: .whitespaces))
            codeSent = true
            focus = .code
        } catch {
            problem = model.message(for: error)
        }
    }

    private func signIn() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        problem = nil
        do {
            let grant = try await client().signIn(email: email.trimmingCharacters(in: .whitespaces), code: code,
                                                  deviceName: String(UIDevice.current.name.prefix(60)),
                                                  timezone: TimeZone.current.identifier)
            await model.signedIn(grant)
        } catch {
            problem = model.message(for: error)
            code = ""
        }
    }
}

private struct DarkField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.body)
            .foregroundStyle(Theme.white)
            .padding(12)
            .overlay(Theme.shape(.darkField).stroke(Theme.text3, lineWidth: 1))
    }
}
