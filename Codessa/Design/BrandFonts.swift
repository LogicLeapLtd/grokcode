import CoreText
import Foundation

/// Registers the bundled brand typefaces (Fraunces + Manrope) with the process
/// font manager at launch, so `Font.custom("Fraunces-SemiBold", …)` etc. resolve.
///
/// The app uses an Xcode-generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`),
/// so there is no `ATSApplicationFontsPath` key to lean on — we register at
/// runtime instead. `Font.custom` falls back to a system face for any family
/// that failed to register, so a missing/renamed file degrades gracefully rather
/// than rendering blank text.
enum BrandFonts {
    /// PostScript-named faces we ship under `Resources/Fonts/`.
    private static let faces = [
        "Fraunces-Regular",
        "Fraunces-SemiBold",
        "Manrope-Regular",
        "Manrope-Medium",
        "Manrope-Bold",
    ]

    /// Register all bundled faces exactly once. Idempotent — re-registering an
    /// already-registered URL is a harmless no-op we swallow.
    static func registerAll() {
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: face, withExtension: "ttf")
            else {
                #if DEBUG
                FileHandle.standardError.write(Data("[BrandFonts] missing \(face).ttf in bundle\n".utf8))
                #endif
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is fine; anything else we log in debug only.
                #if DEBUG
                if let err = error?.takeRetainedValue() {
                    FileHandle.standardError.write(Data("[BrandFonts] \(face): \(err)\n".utf8))
                }
                #endif
            }
        }
    }
}
