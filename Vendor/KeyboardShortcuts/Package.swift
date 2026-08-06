// swift-tools-version:5.7
import PackageDescription

let package = Package(
	name: "KeyboardShortcuts",
	defaultLocalization: "en",
	platforms: [
		.macOS(.v10_13)
	],
	products: [
		.library(
			name: "KeyboardShortcuts",
			targets: [
				"KeyboardShortcuts"
			]
		)
	],
	targets: [
		// LOCAL CHANGE: upstream's testTarget is dropped; Tests/ is not vendored.
		.target(
			name: "KeyboardShortcuts"
		)
	]
)
