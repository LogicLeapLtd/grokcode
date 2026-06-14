import Foundation

/// Static configuration for the GrokCode license gate.
///
/// Everything the *owner* must supply before launch is collected here and marked
/// with `// TODO(owner):` so it's grep-able. The numeric policy (trial length,
/// activation limit, offline grace) is set to the values agreed in
/// `docs/monetization-strategy.md` and can be tuned without touching the manager.
///
/// None of these values are secrets — the Lemon Squeezy *license* API is
/// authenticated by the customer's own key, so no seller token ships in the app.
enum LicenseConfig {
    // MARK: - Store / checkout (owner-supplied)

    /// Your Lemon Squeezy store subdomain, i.e. the `xxxx` in
    /// `https://xxxx.lemonsqueezy.com`. Used to build store/account links.
    // TODO(owner): set your Lemon Squeezy store subdomain, e.g. "grokcode".
    static let storeSubdomain = "YOUR_STORE"

    /// The hosted Lemon Squeezy checkout URL for the GrokCode product/variant,
    /// pre-seeding the Founder's launch discount so the "Buy" button lands on the
    /// $24 price. The `checkout[discount_code]` query param is how Lemon Squeezy
    /// auto-applies a coupon on a hosted checkout.
    ///
    /// Format (replace the path with your real buy URL):
    ///   https://YOUR_STORE.lemonsqueezy.com/buy/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
    // TODO(owner): replace with your real Lemon Squeezy checkout/buy URL.
    static let checkoutURL = URL(
        string: "https://YOUR_STORE.lemonsqueezy.com/buy/REPLACE-WITH-VARIANT-UUID?checkout[discount_code]=FOUNDER40"
    )!

    /// The Lemon Squeezy product *variant* id this build licenses against. The
    /// validate response includes `meta.variant_id`; comparing it lets you reject
    /// a key bought for a *different* product. Leave as 0 to skip the variant
    /// check (any valid key for your store is accepted).
    // TODO(owner): set the numeric Lemon Squeezy variant id for GrokCode (or leave 0 to skip the check).
    static let productVariantId: Int = 0

    // MARK: - Policy (pre-agreed defaults — safe to tune)

    /// Length of the no-card free trial, in days.
    static let trialDays = 7

    /// How many devices a single license key may be activated on. Enforced
    /// server-side by Lemon Squeezy when the product's "activation limit" is set;
    /// surfaced here for the in-app messaging and so the value lives in one place.
    static let activationLimit = 2

    /// How many days a previously-validated license may keep working fully offline
    /// before we force a re-validation. Covers flights / network outages without
    /// punishing legitimate customers.
    static let offlineGraceDays = 7

    // MARK: - Pricing copy (for the paywall — owner may localise)

    /// Launch (Founder's) price shown on the Buy button.
    // TODO(owner): confirm launch price string.
    static let launchPriceLabel = "$24"

    /// Regular price the launch price is discounted from.
    // TODO(owner): confirm regular price string.
    static let regularPriceLabel = "$39"

    // MARK: - Lemon Squeezy License API endpoints (no seller secret required)

    /// POST { license_key, instance_name } → activate this device, returns an
    /// `instance.id` we persist. Authenticated by the customer's key alone.
    static let activateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!

    /// POST { license_key, instance_id } → re-check the key/instance on launch.
    static let validateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!

    /// POST { license_key, instance_id } → release this device's activation slot
    /// (used by a "Deactivate this device" affordance).
    static let deactivateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/deactivate")!
}
