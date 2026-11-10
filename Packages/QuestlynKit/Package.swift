// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuestlynKit",
    defaultLocalization: "ru",
    platforms: [
        .iOS("26.0"),
        // macOS — только для быстрого `swift test` на Mac; приложение — iPhone-only.
        .macOS("27.0"),
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Application", dependencies: ["Domain"]),
        .target(
            name: "Persistence",
            dependencies: ["Domain", "Application", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Application", "Domain"]),
    ]
)
