//
//  Queue.swift
//  Deferred
//
//  Created by Zachary Waldowski on 2/22/18.
//  Copyright © 2018 Big Nerd Ranch. All rights reserved.
//

extension Deferred {
    /// Heap storage acting as a linked list node of continuations.
    ///
    /// The use of `ManagedBuffer` ensures aligned and heap-allocated addresses
    /// for the storage. The storage is tail-allocated with a reference to the
    /// next node.
    final class Node: ManagedBuffer<(Value) -> Void, AnyObject?> {
        fileprivate static func create(handler: @escaping(Value) -> Void) -> Node {
            let storage = unsafeDowncast(super.create(minimumCapacity: 1, makingHeaderWith: { _ in handler }), to: Node.self)

            storage.withUnsafeMutablePointers { (_, pointerToNext) in
                pointerToNext.initialize(to: nil)
            }

            return storage
        }

        deinit {
            _ = withUnsafeMutablePointers { (_, pointerToNext) in
                pointerToNext.deinitialize(count: 1)
            }
        }
    }

    /// The list of continuations to be submitted upon fill.
    ///
    /// A multi-producer, single-consumer queue a la the one in `DispatchGroup`:
    /// <https://github.com/apple/swift-corelibs-libdispatch/blob/master/src/semaphore.c>.
    typealias Queue = (head: Node?, tail: Node?)
}

private extension Deferred.Node {
    /// The next node in the linked list.
    ///
    /// - warning: To alleviate data races, the next node is loaded
    ///   unconditionally. `self` must have been checked not to be the tail.
    var next: Deferred.Node {
        get {
            return withUnsafeMutablePointers { (_, target) in
                repeat {
                    guard let result = bnr_atomic_load(target, .acquire) else { bnr_atomic_hardware_pause(); continue }
                    return unsafeDowncast(result, to: Deferred.Node.self)
                } while true
            }
        }
        set {
            _ = withUnsafeMutablePointers { (_, target) in
                bnr_atomic_store(target, newValue, .relaxed)
            }
        }
    }
}

extension Deferred {
    func drain(from target: UnsafeMutablePointer<Queue>, continuingWith value: Value) {
        var head = bnr_atomic_store(&target.pointee.head, nil, .relaxed)
        let tail = head != nil ? bnr_atomic_store(&target.pointee.tail, nil, .release) : nil

        while let current = head {
            head = current !== tail ? current.next : nil
            current.header(value)
        }
    }

    func push(to target: UnsafeMutablePointer<Queue>, _ handler: @escaping(Value) -> Void) -> Bool {
        let node = Node.create(handler: handler)

        if let tail = bnr_atomic_store(&target.pointee.tail, node, .release) {
            tail.next = node
            return false
        }

        _ = bnr_atomic_store(&target.pointee.head, node, .seq_cst)
        return true
    }
}
