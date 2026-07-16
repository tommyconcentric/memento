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
    private static var window: UIWindow?

    static func show(onUnlock: @escaping () -> Void) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState != .unattached }) ?? scenes.first else { return }
        let lockWindow = UIWindow(windowScene: scene)
        lockWindow.rootViewController = UIHostingController(rootView: AppLockView(onUnlock: onUnlock))
        lockWindow.windowLevel = .alert + 1
        lockWindow.makeKeyAndVisible()
        window = lockWindow
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }
}

// MARK: - Shared PIN pad pieces

private struct PINDotsView: View {
    let filled: Int
    var shake: Bool = false

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .strokeBorder(Theme.aegean, lineWidth: 1.5)
                    .background(Circle().fill(index < filled ? Theme.aegean : .clear))
                    .frame(width: 16, height: 16)
            }
        }
        .modifier(ShakeEffect(travel: shake ? 1 : 0))
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
    let onUnlock: () -> Void

    @AppStorage(AppLock.useBiometricsKey) private var useBiometrics = false
    @State private var entered = ""
    @State private var shakeTick: CGFloat = 0
    @State private var biometricAttempted = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.aegean)
            Text("Memento is Locked")
                .font(.system(.title2, design: .serif).weight(.semibold))

            PINDotsView(filled: entered.count, shake: shakeTick > 0)

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
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            guard useBiometrics, !biometricAttempted else { return }
            biometricAttempted = true
            attemptBiometricUnlock()
        }
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
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Memento"
        ) { success, _ in
            guard success else { return }
            Task { @MainActor in onUnlock() }
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

                PINDotsView(filled: entered.count, shake: shakeTick > 0)

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
