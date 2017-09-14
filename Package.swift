// swift-tools-version:4.0
//
//  Package.swift
//  Deferred
//
//  Created by Zachary Waldowski on 12/7/15.
//  Copyright © 2014-2016 Big Nerd Ranch. Licensed under MIT.
//

import PackageDescription

let package = Package(
    name: "Deferred",
    products: [
        .library(name: "Deferred", targets: [
            "Deferred", "Task"
        ])
    ],
    targets: [
        .target(name: "Atomics"),
        .target(name: "Deferred", dependencies: [ "Atomics" ]),
        .target(name: "Task", dependencies: [ "Deferred" ]),
        .testTarget(name: "DeferredTests", dependencies: [ "Deferred" ]),
        .testTarget(name: "TaskTests", dependencies: [ "Task" ])
    ],
    swiftLanguageVersions: [ 4 ]
)
