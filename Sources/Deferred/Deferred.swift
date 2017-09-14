//
//  Deferred.swift
//  Deferred
//
//  Created by John Gallagher on 7/19/14.
//  Copyright © 2014-2016 Big Nerd Ranch. Licensed under MIT.
//

import Dispatch

#if SWIFT_PACKAGE
import Atomics
#elseif XCODE
import Deferred.Atomics
#endif

/// A deferred is a value that may become determined (or "filled") at some point
/// in the future. Once a deferred value is determined, it cannot change.
public final class Deferred<Value>: FutureProtocol, PromiseProtocol {
    // Using `ManagedBuffer` has advantages:
    //  - The buffer has a stable pointer when locked to a single element.
    //  - The buffer is appropriately aligned for atomic access.
    //  - Better `holdsUniqueReference` support allows for future optimization.
    private typealias Storage =
        DeferredStorage<Value>

    // Heap storage that is initialized with a value once-and-only-once.
    private let storage = Storage.create()
    // A semaphore that keeps efficiently keeps track of a callbacks list.
    private let group = DispatchGroup()

    public init() {
        storage.withUnsafeMutablePointerToElements { (pointerToElement) in
            pointerToElement.initialize(to: nil)
        }

        group.enter()
    }

    /// Creates an instance resolved with `value`.
    public init(filledWith value: Value) {
        storage.withUnsafeMutablePointerToElements { (pointerToElement) in
            pointerToElement.initialize(to: Storage.boxed(value))
        }
    }

    deinit {
        if !isFilled {
            group.leave()
        }
    }

    // MARK: FutureProtocol

    private func notify(flags: DispatchWorkItemFlags, upon queue: DispatchQueue, execute body: @escaping(Value) -> Void) {
        group.notify(flags: flags, queue: queue) { [storage] in
            guard let ptr = storage.withAtomicPointerToElement({ bnr_atomic_ptr_load($0, .relaxed) }) else { return }
            body(Storage.unsafelyUnboxed(from: ptr))
        }
    }

    public func upon(_ queue: DispatchQueue, execute body: @escaping (Value) -> Void) {
        notify(flags: [ .assignCurrentContext, .inheritQoS ], upon: queue, execute: body)
    }

    public func upon(_ executor: Executor, execute body: @escaping(Value) -> Void) {
        if let queue = executor as? DispatchQueue {
            return upon(queue, execute: body)
        } else if let queue = executor.underlyingQueue {
            return upon(queue, execute: body)
        }

        notify(flags: .assignCurrentContext, upon: .any()) { (value) in
            executor.submit {
                body(value)
            }
        }
    }

    public func wait(until time: DispatchTime) -> Value? {
        guard case .success = group.wait(timeout: time),
            let ptr = storage.withAtomicPointerToElement({ bnr_atomic_ptr_load($0, .relaxed) }) else { return nil }

        return Storage.unsafelyUnboxed(from: ptr)
    }

    // MARK: PromiseProtocol

    public var isFilled: Bool {
        return storage.withAtomicPointerToElement {
            bnr_atomic_ptr_load($0, .relaxed) != nil
        }
    }

    @discardableResult
    public func fill(with value: Value) -> Bool {
        let box = Storage.unsafelyBoxed(value)

        let wonRace = storage.withAtomicPointerToElement {
            bnr_atomic_ptr_compare_and_swap($0, nil, box.toOpaque(), .acq_rel)
        }

        if wonRace {
            group.leave()
        } else {
            box.release()
        }

        return wonRace
    }
}

private typealias RawStorage<Value> = AnyObject

private final class DeferredStorage<Value>: ManagedBuffer<Void, RawStorage<Value>?> {

    static func create() -> DeferredStorage<Value> {
        return unsafeDowncast(super.create(minimumCapacity: 1, makingHeaderWith: { _ in }), to: DeferredStorage<Value>.self)
    }

    func withAtomicPointerToElement<Return>(_ body: (UnsafeMutablePointer<UnsafeAtomicRawPointer>) throws -> Return) rethrows -> Return {
        return try withUnsafeMutablePointerToElements { target in
            try target.withMemoryRebound(to: UnsafeAtomicRawPointer.self, capacity: 1, body)
        }
    }

    static func boxed(_ value: Value) -> RawStorage<Value>? {
        return value as AnyObject
    }

    static func unsafelyBoxed<Value>(_ value: Value) -> Unmanaged<AnyObject> {
        return Unmanaged.passRetained(value as AnyObject)
    }

    static func unsafelyUnboxed<T>(from ptr: UnsafeMutableRawPointer) -> T {
        let raw = Unmanaged<AnyObject>.fromOpaque(ptr)
        // swiftlint:disable:next force_cast
        return raw.takeUnretainedValue() as! T
    }

}
