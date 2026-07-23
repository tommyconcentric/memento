import SwiftUI
import UIKit
import LocalAuthentication

/// App-lock settings and state. The PIN is the source of truth — Face ID/Touch
/// ID (when turned on) is a faster path to the same unlock, never a
/// replacement, so nobody can end up locked out with no way back in.
enum AppLock {
    static let enabledKey = "appLockEnabled"
    static let useBiometricsKey = "appLockUseBiometrics"
    private static let pinKeychainKey = "MementoAppLockPIN"

    static var storedPIN: String? {
        KeychainHelper.read(pinKeychainKey)
    }

    /// Returns true only once the PIN is verified to have actually landed in
    /// the Keychain — callers must not enable the lock on a false positive.
    @discardableResult
    static func savePIN(_ pin: String) -> Bool {
        KeychainHelper.save(pin, for: pinKeychainKey)
        return storedPIN == pin
    }

    static func clearPIN() {
        KeychainHelper.delete(pinKeychainKey)
    }

    static var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    static var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometrics"
        }
    }

    static var biometrySymbolName: String {
        switch biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock"
        }
    }
}

// MARK: - Lock window

/// Hosts AppLockView in its own high-level UIWindow. SwiftUI sheets are
/// separate UIKit presentations that render above the window's root view
/// hierarchy, so an in-hierarchy overlay leaves an open sheet (calendar,
/// settings, an editor mid-edit) visible and interactive while "locked".
/// A dedicated window above the alert level covers everything — including
/// the app-switcher snapshot — and keeps the sheets' state intact for
/// after the unlock.
@MainActor
enum LockScreenPresenter {
    private static var windows: [UIWindow] = []

    /// Covers EVERY connected window scene, not just one — on iPad and Mac
    /// the user can open several windows, and any scene left uncovered
    /// would show its content fully interactive while "locked". Safe to
    /// call repeatedly: scenes that already have a lock window are skipped,
    /// so each view's onAppear can re-invoke it as new windows open.
    static func show(onUnlock: @escaping () -> Void) {
        // Windows whose Mac/iPad window was closed hold a dead scene;
        // drop them so the array only tracks live coverage.
        windows.removeAll { $0.windowScene == nil }

        let covered = Set(windows.compactMap { $0.windowScene.map(ObjectIdentifier.init) })
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState != .unattached }

        for scene in scenes where !covered.contains(ObjectIdentifier(scene)) {
            // Only the first lock window auto-prompts biometrics — several
            // windows racing to evaluate Face ID/Touch ID at once would
            // stack prompts.
            let lockView = AppLockView(autoAttemptsBiometrics: windows.isEmpty, onUnlock: onUnlock)
            let lockWindow = UIWindow(windowScene: scene)
            lockWindow.rootViewController = UIHostingController(rootView: lockView)
            lockWindow.windowLevel = .alert + 1
            lockWindow.makeKeyAndVisible()
            windows.append(lockWindow)
        }
    }

    static func hide() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
    }
}

// MARK: - Shared PIN pad pieces

private struct PINDotsView: View {
    let filled: Int
    // A running failure count, not a Bool: ShakeEffect only animates when
    // its animatableData *changes*, so each failure must move the travel
    // by a full unit — collapsing to true/false pins it at 1 after the
    // first failure and every later wrong PIN would shake nothing.
    var shakeTick: CGFloat = 0

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .strokeBorder(Theme.aegean, lineWidth: 1.5)
                    .background(Circle().fill(index < filled ? Theme.aegean : .clear))
                    .frame(width: 16, height: 16)
            }
        }
        .modifier(ShakeEffect(travel: shakeTick))
    }
}

private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = travel == 0 ? 0 : sin(travel * .pi * 4) * 8
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

private struct NumberPad: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    private let rows: [[Int?]] = [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
        [nil, 0, -1]   // -1 marks the delete key
    ]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 28) {
                    ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                        key(rows[rowIndex][columnIndex])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func key(_ value: Int?) -> some View {
        switch value {
        case .some(-1):
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.title3)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
        case .some(let digit):
            Button {
                onDigit(digit)
            } label: {
                Text("\(digit)")
                    .font(.system(.title2, design: .serif))
                    .frame(width: 64, height: 64)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.aegean.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
        case .none:
            Color.clear.frame(width: 64, height: 64)
        }
    }
}

// MARK: - Lock screen shown over the app

struct AppLockView: View {
    // With one lock window per scene, only one instance should auto-prompt
    // biometrics on appear; the button still works on all of them.
    var autoAttemptsBiometrics = true
    let onUnlock: () -> Void

    @AppStorage(AppLock.useBiometricsKey) private var useBiometrics = false
    @State private var entered = ""
    @State private var shakeTick: CGFloat = 0
    @State private var biometricAttempted = false
    @State private var biometricNote: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.aegean)
            Text("Memento is Locked")
                .font(.system(.title2, design: .serif).weight(.semibold))

            PINDotsView(filled: entered.count, shakeTick: shakeTick)

            NumberPad(
                onDigit: { digit in
                    guard entered.count < 4 else { return }
                    entered.append(String(digit))
                    if entered.count == 4 { checkPIN() }
                },
                onDelete: {
                    if !entered.isEmpty { entered.removeLast() }
                }
            )

            if useBiometrics && AppLock.biometryType != .none {
                Button {
                    attemptBiometricUnlock()
                } label: {
                    Label("Unlock with \(AppLock.biometryName)", systemImage: AppLock.biometrySymbolName)
                        .font(.subheadline)
                }
                .padding(.top, 4)
                if let biometricNote {
                    Text(biometricNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.terracotta)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        // The lock window is created at the moment of *locking* — usually
        // while the app is leaving the foreground. An onAppear-only prompt
        // would fire (and be consumed) right then, latch, and never re-run
        // when the user actually comes back — so the advertised auto-unlock
        // effectively never happened on reopen. Attempt only while active,
        // and re-arm on every departure so each return gets one prompt.
        //
        // Those signals must come from UIApplication's lifecycle
        // notifications, not \.scenePhase: this view lives in
        // LockScreenPresenter's own UIWindow, outside the App's scene
        // graph, and a UIHostingController there never receives scenePhase
        // updates — the environment value stays frozen at its initial
        // (background) reading, so a scenePhase-driven attempt never fires
        // and its onChange never re-arms.
        .onAppear {
            autoAttemptBiometricsIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            autoAttemptBiometricsIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)) { _ in
            // Re-arm only on a genuine departure. The Face ID/Touch ID
            // system dialog itself dips the app to inactive and back to
            // active — re-arming on that dip meant every Cancel
            // re-presented the prompt instantly, an endless loop standing
            // between the user and the PIN pad. Real backgrounding always
            // reaches didEnterBackground, so each true return still gets
            // its one auto-prompt (the button covers everything else).
            biometricAttempted = false
        }
    }

    private func autoAttemptBiometricsIfReady() {
        // On a cold locked launch onAppear can run before the app is
        // active; the skipped attempt doesn't latch, and the
        // didBecomeActive notification moments later retries it.
        guard autoAttemptsBiometrics, useBiometrics, !biometricAttempted,
              UIApplication.shared.applicationState == .active else { return }
        biometricAttempted = true
        attemptBiometricUnlock()
    }

    private func checkPIN() {
        if entered == AppLock.storedPIN {
            onUnlock()
        } else {
            withAnimation(.default) { shakeTick += 1 }
            entered = ""
        }
    }

    private func attemptBiometricUnlock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Locked out (too many failed scans) or no longer enrolled: the
            // hardware check that shows the button can't see either state,
            // so without this the button (and the auto-attempt) is a silent
            // no-op that reads as broken. The PIN is the source of truth,
            // so don't widen the unlock to the device passcode
            // (.deviceOwnerAuthentication) — explain and point at the pad.
            biometricNote = Self.biometricUnavailableMessage(for: error)
            return
        }
        biometricNote = nil
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Memento"
        ) { success, _ in
            guard success else { return }
            Task { @MainActor in onUnlock() }
        }
    }

    private static func biometricUnavailableMessage(for error: NSError?) -> String {
        switch error.flatMap({ LAError.Code(rawValue: $0.code) }) {
        case .biometryLockout:
            return "\(AppLock.biometryName) is locked after too many tries — enter your PIN."
        case .biometryNotEnrolled:
            return "\(AppLock.biometryName) isn't set up on this device — enter your PIN."
        default:
            return "\(AppLock.biometryName) isn't available right now — enter your PIN."
        }
    }
}

// MARK: - PIN setup (Settings)

struct PINSetupView: View {
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    private enum Stage { case enter, confirm }

    @State private var stage: Stage = .enter
    @State private var firstEntry = ""
    @State private var entered = ""
    @State private var errorMessage: String?
    @State private var shakeTick: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                Text(stage == .enter ? "Enter a 4-digit PIN" : "Confirm your PIN")
                    .font(.system(.title3, design: .serif).weight(.semibold))

                PINDotsView(filled: entered.count, shakeTick: shakeTick)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.terracotta)
                }

                NumberPad(
                    onDigit: { digit in
                        guard entered.count < 4 else { return }
                        entered.append(String(digit))
                        if entered.count == 4 { advance() }
                    },
                    onDelete: {
                        if !entered.isEmpty { entered.removeLast() }
                    }
                )
                Spacer()
            }
            .padding()
            .navigationTitle("Set PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func advance() {
        switch stage {
        case .enter:
            firstEntry = entered
            entered = ""
            errorMessage = nil
            stage = .confirm
        case .confirm:
            if entered == firstEntry {
                onComplete(entered)
            } else {
                withAnimation(.default) { shakeTick += 1 }
                errorMessage = "PINs didn't match — try again."
                stage = .enter
                firstEntry = ""
                entered = ""
            }
        }
    }
}
