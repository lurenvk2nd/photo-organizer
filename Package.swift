// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PhotoOrganizer",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "PhotoOrganizer",
            targets: ["PhotoOrganizer"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PhotoOrganizer",
            dependencies: [],
            path: ".",
            exclude: ["README.md", "LICENSE", "Package.swift"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PhotoOrganizerTests",
            dependencies: ["PhotoOrganizer"]),
    ]
)