// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "ProCRUD",
	platforms: [
		.macOS(.v26),
	],
	products: [
		.executable(name: "pro-crud", targets: ["ProCRUDCLI"]),
		.library(name: "ProCRUDCore", targets: ["ProCRUDCore"]),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-protobuf.git", from: "1.30.0"),
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
		.package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "1.6.1"),
		.package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.18.7"),
		.package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", from: "0.65.0"),
		.package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.62.1"),
	],
	targets: [
		.target(
			name: "ProPresenterProto",
			dependencies: [
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
			],
		),
		.target(
			name: "ProCRUDCore",
			dependencies: [
				"ProPresenterProto",
			],
			resources: [
				.copy("Resources/Protobuf"),
			],
			linkerSettings: [
				.linkedFramework("AppKit"),
				.linkedFramework("AVFoundation"),
			],
			plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
		),
		.executableTarget(
			name: "ProCRUDCLI",
			dependencies: [
				"ProCRUDCore",
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
			],
			resources: [
				.copy("../../skills"),
				.copy("../../Docs/Format"),
				.copy("Resources/Protobuf"),
			],
			plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
		),
		.executableTarget(
			name: "FixtureGenerator",
			dependencies: [
				"ProCRUDCore",
				"ProPresenterProto",
			],
			plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
		),
		.testTarget(
			name: "ProCRUDCoreTests",
			dependencies: [
				"ProCRUDCore",
				.product(name: "CustomDump", package: "swift-custom-dump"),
				.product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
			],
			exclude: ["__Snapshots__"],
			plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
		),
		.testTarget(
			name: "ProCRUDCLITests",
			dependencies: [
				"ProCRUDCLI",
				.product(name: "CustomDump", package: "swift-custom-dump"),
			],
			plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
		),
	],
)

for target in package.targets {
	guard target.type != .plugin else { continue }
	var settings = target.swiftSettings ?? []
	settings.append(contentsOf: [
		.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
		.enableUpcomingFeature("InferIsolatedConformances"),
	])
	target.swiftSettings = settings
}
