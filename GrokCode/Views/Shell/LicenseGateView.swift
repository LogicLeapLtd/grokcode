import SwiftUI

/// Wraps the main app UI and enforces the license/trial state from
/// `LicenseManager`. It is purely a *gate* — it renders whatever `content` you
/// give it (the real app shell), and layers on top of it:
///
///   • a subtle trial-countdown banner while `.trial`, and
///   • a full-bleed `PaywallView` once the trial has elapsed without a license.
///
/// It deliberately does NOT gate onboarding: `ContentView` shows onboarding first
/// (so the user sees the app's value), and only the post-onboarding shell is
/// wrapped in this gate. The paywall blocks interaction with the app behind it
/// but never the onboarding sheet.
struct LicenseGateView<Content: View>: View {
    @ObservedObject var license: LicenseManager
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            // Trial countdown banner — only while trialling and not yet locked.
            .safeAreaInset(edge: .top, spacing: 0) {
                if license.isInTrial {
                    TrialBanner(license: license)
                        .transition(CodexMotion.bannerTransition)
                }
            }
            // Hard paywall — covers everything once expired/invalid.
            .overlay {
                if license.isLocked {
                    PaywallView(license: license)
                        .transition(.opacity)
                        .zIndex(300)
                }
            }
            .animation(CodexMotion.modalSpring, value: license.isLocked)
            .animation(CodexMotion.panelSpring, value: license.isInTrial)
    }
}

// MARK: - Trial banner

/// A thin, non-intrusive strip pinned under the title bar during the trial. Reads
/// "N days left in your trial" with a quiet "Buy" affordance, in the app's tokens.
private struct TrialBanner: View {
    @ObservedObject var license: LicenseManager

    private var daysLeft: Int { license.trialDaysLeft }

    private var label: String {
        switch daysLeft {
        case 0: return "Last day of your free trial"
        case 1: return "1 day left in your free trial"
        default: return "\(daysLeft) days left in your free trial"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(CodexTheme.accentOrange)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)

            Spacer(minLength: 12)

            Button { license.openCheckout() } label: {
                HStack(spacing: 5) {
                    Text("Unlock — \(LicenseConfig.launchPriceLabel)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(CodexTheme.sendButtonActiveBackground)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(cornerRadius: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(CodexTheme.composerShellBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CodexTheme.divider)
                .frame(height: 1)
        }
    }
}

// MARK: - Paywall sheet

/// Full-window paywall presented once the trial has elapsed without a valid
/// license. Mirrors the `OnboardingView` card pattern (520pt centred card over a
/// dimmed backdrop, CodexTheme tokens, the chevron/orange-cursor identity mark)
/// so it feels native rather than bolted on.
struct PaywallView: View {
    @ObservedObject var license: LicenseManager

    @State private var keyField = ""
    @State private var appeared = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        ZStack {
            CodexTheme.modalBackdrop
                .opacity(0.9)
                .ignoresSafeArea()
                .transition(.opacity)

            card
                .frame(width: 520)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CodexTheme.mainBackground)
                        .shadow(color: CodexTheme.shadowColor, radius: 32, y: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
                )
                .scaleEffect(appeared ? 1 : 0.96)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
        }
        .onAppear {
            withAnimation(CodexMotion.modalSpring) { appeared = true }
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            Divider().background(CodexTheme.divider)

            VStack(alignment: .leading, spacing: 18) {
                buyBlock
                orDivider
                licenseKeyBlock
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }

    // MARK: Header

    /// True when the lock is caused by a rejected/invalid/refunded key rather than
    /// a simply-elapsed trial, so the headline doesn't contradict the inline error.
    private var isKeyProblem: Bool { license.status == .invalid }

    private var headerTitle: String {
        isKeyProblem ? "There's a problem with your license" : "Your free trial has ended"
    }

    private var headerSubtitle: String {
        isKeyProblem
            ? "We couldn't verify the key on this device. Check the key below, or buy a new license with a one-time purchase — no subscription."
            : "Unlock GrokCode for good with a one-time purchase — no subscription. Or paste a license key you already own."
    }

    private var header: some View {
        VStack(spacing: 16) {
            PaywallIdentityMark()

            VStack(spacing: 7) {
                Text(headerTitle)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)

                Text(headerSubtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)

                // Surface the manager's error prominently in the key-problem case so
                // the headline can never contradict the inline message below.
                if isKeyProblem, let error = license.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(error)
                            .font(.system(size: 12.5, weight: .medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(CodexTheme.errorForeground)
                    .frame(maxWidth: 400)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
    }

    // MARK: Buy

    private var buyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LicenseConfig.launchPriceLabel)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text(LicenseConfig.regularPriceLabel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .strikethrough(true, color: CodexTheme.textTertiary)
                Text("Founder's launch price")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexTheme.accentOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(CodexTheme.accentOrange.opacity(0.14))
                    )
                Spacer(minLength: 0)
            }

            Button { license.openCheckout() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Buy (\(LicenseConfig.launchPriceLabel) launch → \(LicenseConfig.regularPriceLabel))")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(CodexTheme.sendButtonActiveBackground)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(cornerRadius: 11)

            Text("One-time purchase · works on up to \(LicenseConfig.activationLimit) devices · lifetime updates for this major version.")
                .font(.system(size: 11.5))
                .foregroundStyle(CodexTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(CodexTheme.divider).frame(height: 1)
            Text("OR")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
                .kerning(0.5)
            Rectangle().fill(CodexTheme.divider).frame(height: 1)
        }
    }

    // MARK: License key

    private var licenseKeyBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("I have a license key")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)

            HStack(spacing: 8) {
                TextField("", text: $keyField)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .focused($keyFocused)
                    .placeholderOverlay(
                        "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
                        visible: keyField.isEmpty,
                        font: .system(size: 13, design: .monospaced)
                    )
                    .disabled(license.isWorking)
                    .onSubmit(activate)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.composerBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(keyFocused ? CodexTheme.textTertiary : CodexTheme.composerBorder, lineWidth: 1)
                    )

                Button(action: activate) {
                    HStack(spacing: 6) {
                        if license.isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(CodexTheme.sendButtonActiveForeground)
                        }
                        Text(license.isWorking ? "Checking…" : "Activate")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(canActivate ? CodexTheme.sendButtonActiveBackground : CodexTheme.sendButtonBackground)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 9)
                .disabled(!canActivate)
            }

            if let error = license.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(error)
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(CodexTheme.errorForeground)
            }

            Button { license.openCheckout() } label: {
                Text("Lost your key? Manage it in your account →")
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .onAppear { keyFocused = true }
    }

    private var canActivate: Bool {
        !license.isWorking && !keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func activate() {
        guard canActivate else { return }
        let key = keyField
        Task { await license.activate(licenseKey: key) }
    }
}

// MARK: - Identity mark (reuses the brand motif from onboarding)

/// The GrokCode chevron-prompt + orange block-cursor mark, sized for the paywall
/// header. Mirrors `OnboardingView`'s `ChevronPromptMark` (kept local so the two
/// surfaces stay visually identical without sharing a private type).
private struct PaywallIdentityMark: View {
    @State private var cursorOn = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CodexTheme.textPrimary)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CodexTheme.accentOrange)
                .frame(width: 13, height: 26)
                .opacity(cursorOn ? 1 : 0.18)
                .shadow(color: CodexTheme.accentOrange.opacity(cursorOn ? 0.5 : 0), radius: 8)
        }
        .frame(width: 76, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CodexTheme.composerShellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                cursorOn = false
            }
        }
    }
}
