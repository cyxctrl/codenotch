import AppKit
import SwiftUI

/// Upstream writes against the macOS 26 SDK — Liquid Glass (`glassEffect`),
/// unified pointer styles (`pointerStyle`) — and those modifiers are absent
/// entirely from the macOS 14 SDK this machine builds with, so `#available`
/// cannot gate them: the compiler must not even see the symbol. On such
/// toolchains these shims stand in with the pre-Tahoe form of the same
/// controls — a material in the same shape, a cursor hover — which is the
/// right look on those systems anyway.
///
/// `swift(>=6.2)` is the compile-time proxy for "the macOS 26 SDK is in this
/// toolchain" (Xcode 26 ships Swift 6.2; Xcode 15.4 ships 5.10). Newer
/// toolchains compile the real modifier, still gated at runtime by
/// `#available`; older ones never see the symbol. The maintainer's Xcode 26
/// builds pass through unchanged.
extension View {
    /// Liquid Glass card or disc, or a material in the same shape on older macOS.
    ///
    /// `interactive` is upstream's `.regular.interactive()`: the glass answers the
    /// pointer. There is no material equivalent — on the older systems this is the
    /// branch that never runs, since `NotchSurfaceStyle.glassAvailable` is false
    /// there — so the fallback stays the plain material.
    func compatGlassEffect<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        #if swift(>=6.2)
        if #available(macOS 26, *) {
            let glass: Glass = interactive ? .regular.interactive() : .regular
            AnyView(background { Color.clear.glassEffect(glass, in: shape) })
        } else {
            AnyView(background(.regularMaterial, in: shape))
        }
        #else
        AnyView(background(.regularMaterial, in: shape))
        #endif
    }

    /// Open hand where the pointer may drag; a pointing hand on older macOS.
    func compatPointerStyle(active: Bool) -> some View {
        #if swift(>=6.2)
        if #available(macOS 26, *) {
            AnyView(pointerStyle(active ? .grabIdle : nil))
        } else {
            AnyView(cursorCompat(active ? NSCursor.pointingHand : NSCursor.arrow))
        }
        #else
        AnyView(cursorCompat(active ? NSCursor.pointingHand : NSCursor.arrow))
        #endif
    }

    private func cursorCompat(_ cursor: NSCursor) -> some View {
        onHover { hovering in
            (hovering ? cursor : NSCursor.arrow).set()
        }
    }
}
