// swift-tools-version: 5.9

// DualClock for iPhone + iPad v2.0 - Swift Playgrounds / Xcode app package.
// Open this .swiftpm folder in Swift Playgrounds (iPad or Mac) or Xcode 15+.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "DualClock",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "DualClock",
            targets: ["AppModule"],
            bundleIdentifier: "com.olszewski.DualClock",
            displayVersion: "2.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            appCategory: .utilities
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
