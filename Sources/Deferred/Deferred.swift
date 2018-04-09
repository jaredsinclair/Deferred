//
//  Deferred.swift
//  Deferred
//
//  Created by John Gallagher on 7/19/14.
//  Copyright © 2014-2018 Big Nerd Ranch. Licensed under MIT.
//

import Dispatch

/// A value that may become determined (or "filled") at some point in the
/// future. Once determined, it cannot change.
///
/// You may subscribe to be notified once the value becomes determined.
///
/// Handlers and their captures are strongly referenced until:
/// - they are executed when the value is determined
/// - the last copy to this type escapes without the value becoming determined
///
/// If the value never becomes determined, a handler submitted to it will never
/// be executed.
public struct Deferred<Value> {
    /// Heap storage that is initialized once and only once from `nil` to a
    /// reference. See `Deferred.Variant` for more details.
    fileprivate final class ObjectStorage: ManagedBuffer<Queue, AnyObject?> {
        static func create() -> ObjectStorage {
            let storage = unsafeDowncast(super.create(minimumCapacity: 1, makingHeaderWith: { _ in
                (head: nil, tail: nil)
            }), to: ObjectStorage.self)

            storage.withUnsafeMutablePointers { (_, pointerToValue) in
                pointerToValue.initialize(to: nil)
            }

            return storage
        }

        deinit {
            withUnsafeMutablePointers { (_, pointerToValue) in
                _ = pointerToValue.deinitialize(count: 1)
            }
        }
    }

    /// Heap storage that is initialized once and only once using a flag.
    /// See `Deferred.Variant` for more details.
    fileprivate final class NativeStorage: ManagedBuffer<(Queue, isInitialized: Bool), Value> {
        static func create() -> NativeStorage {
            return unsafeDowncast(super.create(minimumCapacity: 1, makingHeaderWith: { _ in
                ((head: nil, tail: nil), isInitialized: false)
            }), to: NativeStorage.self)
        }

        deinit {
            withUnsafeMutablePointers { (pointerToHeader, pointerToValue) in
                if pointerToHeader.pointee.isInitialized {
                    pointerToValue.deinitialize(count: 1)
                }
            }
        }
    }

    /// Heap storage that starts initialized. See `Deferred.Variant` for more
    /// details.
    fileprivate final class FilledStorage: ManagedBuffer<Value, Void> {
        static func create(_ value: Value) -> FilledStorage {
            return unsafeDowncast(super.create(minimumCapacity: 0, makingHeaderWith: { _ in
                value
            }), to: FilledStorage.self)
        }
    }

    /// Deferred's storage. It, lock-free but thread-safe, should:
    /// - be initialized with a value once and only once
    /// - manages a callback queue
    /// - hold the expected invariants for deallocation
    ///
    /// An underlying implementation will be chosen at init. All variants use
    /// `ManagedBuffer` to guarantee indirect storage. Those that start unfilled
    /// are also guarantee aligned and heap-allocated addresses for atomic
    /// access, and are tail-allocated with space for the callbacks queue.
    ///
    /// - note: **Q:** Why not just stored properties? Aren't you overthinking
    ///   it? **A:** We want raw memory because Swift reserves the right to
    ///   lay out properties anywhere. The initial store during `init` also
    ///   counts as unsafe access to TSAN.
    fileprivate enum Variant {
        case object(ObjectStorage)
        case native(NativeStorage)
        case filled(FilledStorage)
    }

    fileprivate let variant: Variant

    public init() {
        if Value.self is AnyObject.Type {
            variant = .object(.create())
        } else {
            variant = .native(.create())
        }
    }

    /// Creates an instance resolved with `value`.
    public init(filledWith value: Value) {
        variant = .filled(.create(value))
    }
}

// MARK: -

extension Deferred: PromiseProtocol {
    @discardableResult
    public func fill(with value: Value) -> Bool {
        switch variant {
        case .object(let storage):
            return storage.withUnsafeMutablePointers { (pointerToQueue, pointerToValue) in
                guard bnr_atomic_initialize_once(pointerToValue, unsafeBitCast(value, to: AnyObject.self)) else { return false }
                drain(from: pointerToQueue, continuingWith: value)
                return true
            }
        case .native(let storage):
            return storage.withUnsafeMutablePointers { (pointerToHeader, pointerToValue) in
                guard bnr_atomic_initialize_once(&pointerToHeader.pointee.isInitialized, {
                    pointerToValue.initialize(to: value)
                }) else { return false }
                drain(from: &pointerToHeader.pointee.0, continuingWith: value)
                return true
            }
        case .filled:
            return false
        }
    }
}

// MARK: -

extension Deferred: FutureProtocol {
    /// Appends the `continuation` to the queue. If it's the only item and we are filled,
    /// drain the queue and invoke it immediately.
    private func push(_ continuation: @escaping(Value) -> Void) {
        switch variant {
        case .object(let storage):
            storage.withUnsafeMutablePointers { (pointerToQueue, pointerToValue) in
                guard push(to: pointerToQueue, continuation),
                    let existingValue = unsafeBitCast(bnr_atomic_load(pointerToValue, .seq_cst), to: Value?.self) else { return }
                drain(from: pointerToQueue, continuingWith: existingValue)
            }
        case .native(let storage):
            storage.withUnsafeMutablePointers { (pointerToHeader, pointerToValue) in
                guard push(to: &pointerToHeader.pointee.0, continuation),
                    bnr_atomic_load(&pointerToHeader.pointee.isInitialized, .seq_cst) else { return }
                drain(from: &pointerToHeader.pointee.0, continuingWith: pointerToValue.pointee)
            }
        case .filled(let storage):
            continuation(storage.header)
        }
    }

    public func upon(_ executor: Executor, execute body: @escaping(Value) -> Void) {
        push { (value) in
            executor.submit {
                body(value)
            }
        }
    }

    public func wait(until time: DispatchTime) -> Value? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Value?

        push { (value) in
            result = value
            semaphore.signal()
        }

        guard case .success = semaphore.wait(timeout: time) else { return nil }
        return result
    }

    public func peek() -> Value? {
        switch variant {
        case .object(let storage):
            return storage.withUnsafeMutablePointers { (_, pointerToValue) in
                unsafeBitCast(bnr_atomic_load(pointerToValue, .relaxed), to: Value?.self)
            }
        case .native(let storage):
            return storage.withUnsafeMutablePointers { (pointerToHeader, pointerToValue) in
                bnr_atomic_load(&pointerToHeader.pointee.isInitialized, .relaxed) ? pointerToValue.pointee : nil
            }
        case .filled(let storage):
            return storage.header
        }
    }
}
