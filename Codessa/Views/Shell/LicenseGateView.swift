import SwiftUI

/// Wraps the main app UI with license-aware animation hooks. Licensing no longer
/// hard-blocks the shell: expired/invalid states show as limited mode in the
/// top banner, while the app itself stays usable.
struct LicenseGateView<Content: View>: View {
    @ObservedObject var license: LicenseManager
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .animation(CodexMotion.panelSpring, value: license.isInTrial)
            .animation(CodexMotion.panelSpring, value: license.isInLimitedMode)
    }
}

// MARK: - Trial banner

/// A thin, non-intrusive strip pinned at the top of the main page for trial and
/// limited-mode states. Matches the in-composer banner pattern (`HooksBanner`)
/// so it reads as native chrome rather than a bolted-on upsell bar.
struct TrialBanner: View {
    @ObservedObject var license: LicenseManager

    private var daysLeft: Int { license.trialDaysLeft }

    private var label: String {
        if license.isInLimitedMode {
            switch license.status {
            case .invalid:
                return "Limited mode: license needs attention"
            default:
                return "Limited mode: core chat stays available"
            }
        }

        switch daysLeft {
        case 0: return "Last day of your free trial"
        case 1: return "1 day left in your free trial"
        default: return "\(daysLeft) days left in your free trial"
        }
    }

    private var iconName: String {
        license.isInLimitedMode ? "exclamationmark.triangle" : "clock"
    }

    private var actionTitle: String {
        license.isInLimitedMode ? "Unlock full app" : "Buy — \(LicenseConfig.launchPriceLabel)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CodexTheme.accentOrange)

            Text(label)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(CodexTheme.textSecondary)

            Spacer(minLength: 8)

            Button {
                license.openCheckout()
            } label: {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .buttonStyle(CodexPillButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .liquidGlass(in: Rectangle(), fallback: CodexTheme.composerShellBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CodexTheme.divider)
                .frame(height: 1)
        }
    }
}

// MARK: - Paywall sheet

/// Full-window paywall presented once the trial has elapsed without a valid
/// license. Uses the same CodexTheme tokens and chevron/orange-cursor identity
/// mark as onboarding, but keeps the purchase flow compact and decision-led.
struct PaywallView: View {
    @ObservedObject var license: LicenseManager

    @State private var keyField = ""
    @State private var keyEntryOpen = false
    @State private var appeared = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        ZStack {
            CodexTheme.modalBackdrop
                .opacity(0.82)
                .ignoresSafeArea()
                .transition(.opacity)

            card
                .frame(width: 500)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CodexTheme.menuBackground)
                        .shadow(color: CodexTheme.shadowColor, radius: 28, y: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(CodexTheme.menuBorder, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(CodexTheme.composerShellHighlight.opacity(0.55), lineWidth: 1)
                        .padding(1)
                        .allowsHitTesting(false)
                }
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
        VStack(alignment: .leading, spacing: 18) {
            header
            buyBlock
            licenseKeyBlock
        }
        .padding(24)
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
            ? "We couldn't verify the key on this device. Check it below, or buy a fresh license with a one-time purchase."
            : "Keep using Codessa with a one-time purchase. No subscription, no monthly meter."
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            PaywallIdentityMark()

            VStack(alignment: .leading, spacing: 6) {
                Text(isKeyProblem ? "License check failed" : "Trial ended")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.accentOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(CodexTheme.accentOrange.opacity(0.14)))

                Text(headerTitle)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(2)

                Text(headerSubtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360, alignment: .leading)

                // Surface the manager's error prominently in the key-problem case so
                // the headline can never contradict the inline message below.
                if isKeyProblem, let error = license.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(error)
                            .font(.system(size: 12.5, weight: .medium))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(CodexTheme.errorForeground)
                    .frame(maxWidth: 400, alignment: .leading)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Buy

    private var buyBlock: some View {
        VStack(alignment: .leading, spacing: 13) {
            Rectangle().fill(CodexTheme.divider).frame(height: 1)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(LicenseConfig.launchPriceLabel)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(CodexTheme.textPrimary)
                        Text(LicenseConfig.regularPriceLabel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .strikethrough(true, color: CodexTheme.textTertiary)
                    }

                    Text("Founder's launch price")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.accentOrange)
                }

                Spacer(minLength: 8)

                Button { license.openCheckout() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Buy once")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CodexTheme.sendButtonActiveBackground)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 10)
            }

            HStack(spacing: 12) {
                benefit("No subscription")
                benefit("\(LicenseConfig.activationLimit) devices")
                benefit("Updates included")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: License key

    private var licenseKeyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(CodexTheme.divider).frame(height: 1)

            Button {
                withAnimation(CodexMotion.quickSpring) {
                    keyEntryOpen.toggle()
                }
                if !keyEntryOpen {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        keyFocused = true
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: keyEntryOpen || isKeyProblem ? "chevron.down" : "key")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                    Text(keyEntryOpen || isKeyProblem ? "Use a license key" : "Already purchased? Use a license key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CodexTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if keyEntryOpen || isKeyProblem {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        TextField("", text: $keyField)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .focused($keyFocused)
                            .placeholderOverlay(
                                "Paste license key",
                                visible: keyField.isEmpty,
                                font: .system(size: 12.5, design: .monospaced)
                            )
                            .disabled(license.isWorking)
                            .onSubmit(activate)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(CodexTheme.composerBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(keyFocused ? CodexTheme.textTertiary : CodexTheme.composerBorder, lineWidth: 1)
                            )

                        Button(action: activate) {
                            HStack(spacing: 6) {
                                if license.isWorking {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(CodexTheme.sendButtonActiveForeground)
                                }
                                Text(license.isWorking ? "Checking..." : "Activate")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(canActivate ? CodexTheme.sendButtonActiveForeground : CodexTheme.sendButtonForeground)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(canActivate ? CodexTheme.sendButtonActiveBackground : CodexTheme.sendButtonBackground)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CodexPressableStyle())
                        .codexHoverOverlay(cornerRadius: 8)
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
                        Text("Lost your key? Manage it in your account")
                            .font(.system(size: 11))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CodexTheme.accentOrange)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)
        }
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

/// The Codessa chevron-prompt + orange block-cursor mark, sized for the paywall
/// header. Mirrors `OnboardingView`'s `ChevronPromptMark` (kept local so the two
/// surfaces stay visually identical without sharing a private type).
private struct PaywallIdentityMark: View {
    @State private var cursorOn = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CodexTheme.textPrimary)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CodexTheme.accentOrange)
                .frame(width: 10, height: 22)
                .opacity(cursorOn ? 1 : 0.18)
                .shadow(color: CodexTheme.accentOrange.opacity(cursorOn ? 0.5 : 0), radius: 8)
        }
        .frame(width: 58, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CodexTheme.composerShellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                cursorOn = false
            }
        }
    }
}
