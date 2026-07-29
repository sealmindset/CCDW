// swift-tools-version:5.9
// =============================================================================
// CCDW Terminal — native macOS terminal for the CCDW container.
// -----------------------------------------------------------------------------
// SwiftPM manifest. Builds a real terminal emulator (SwiftTerm) that drives a
// `docker exec -it` PTY into the claude-code container — so selection, copy,
// paste, and ⌘C/⌘V are GENUINELY native (Terminal.app behavior), with no
// xterm/ttyd/OSC-52 web layer in the loop.
//
// Build:  swift build -c release   (invoked by build-terminal-app.sh, which
//         then assembles + ad-hoc signs the .app bundle around the binary).
// =============================================================================
import PackageDescription

let package = Package(
    name: "CCDWTerminal",
    platforms: [ .macOS(.v11) ],
    dependencies: [
        // Pinned for reproducible builds. Bump deliberately after testing.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "CCDWTerminal",
            dependencies: [ "SwiftTerm" ],
            path: "Sources/CCDWTerminal"
        ),
    ]
)
