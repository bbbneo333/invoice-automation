// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InvoiceTimer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "InvoiceTimer", targets: ["InvoiceTimer"])
    ],
    targets: [
        .executableTarget(name: "InvoiceTimer")
    ]
)
