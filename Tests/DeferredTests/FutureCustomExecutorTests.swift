//
//  FutureCustomExecutorTests.swift
//  DeferredTests
//
//  Created by Zachary Waldowski on 4/10/16.
//  Copyright © 2016-2018 Big Nerd Ranch. Licensed under MIT.
//

import XCTest

import Deferred

class FutureCustomExecutorTests: CustomExecutorTestCase {
    static let allTests: [(String, (FutureCustomExecutorTests) -> () throws -> Void)] = [
        ("testUpon", testUpon),
        ("testMap", testMap),
        ("testAndThen", testAndThen)
    ]

    func testUpon() {
        let deferred = Deferred<Void>()

        let expect = expectation(description: "upon block called when deferred is filled")
        deferred.upon(customExecutor) { _ in
            expect.fulfill()
        }

        deferred.fill(with: ())

        wait(for: [
            expect,
            expectationThatCustomExecutor(isCalledAtLeast: 1)
        ], timeout: shortTimeout)
    }

    func testMap() {
        let marker = Deferred<Void>()
        let testValue = 42
        let mapped = marker.map(upon: customExecutor) { _ in testValue }

        let expect = expectation(description: "upon block called when deferred is filled")
        mapped.upon(customExecutor) {
            XCTAssertEqual($0, testValue)
            expect.fulfill()
        }

        marker.fill(with: ())

        wait(for: [
            expect,
            expectationThatCustomExecutor(isCalledAtLeast: 2)
        ], timeout: shortTimeout)
    }

    // Should this be promoted to an initializer on Future?
    private func delay<Value>(_ value: @autoclosure @escaping() -> Value) -> Future<Value> {
        let deferred = Deferred<Value>()
        afterShortDelay {
            deferred.fill(with: value())
        }
        return Future(deferred)
    }

    func testAndThen() {
        let marker = Deferred<Void>()
        let testValue = 42
        let flattened = marker.andThen(upon: customExecutor) { _ in self.delay(testValue) }

        let expect = expectation(description: "upon block called when deferred is filled")
        flattened.upon(customExecutor) {
            XCTAssertEqual($0, testValue)
            expect.fulfill()
        }

        marker.fill(with: ())

        wait(for: [
            expect,
            expectationThatCustomExecutor(isCalledAtLeast: 3)
        ], timeout: shortTimeout)
    }
}
