//
//  ObservationToken.swift
//  SmartContacts
//
//  Created by Wataru Nagasawa on 2019/05/25.
//  Copyright © 2019 Wataru Nagasawa. All rights reserved.
//

import Foundation

public final class ObservationToken {
    private let cancellationClosure: () -> Void

    init(cancellationClosure: @escaping () -> Void) {
        self.cancellationClosure = cancellationClosure
    }

    public func cancel() {
        cancellationClosure()
    }
}

struct ObservationTokenCollection {
    typealias Closure = () -> Void
    typealias DictionaryType = [UUID: Closure]

    private var observations = DictionaryType()

    init(observations: DictionaryType = .init()) {
        self.observations = observations
    }
}

extension ObservationTokenCollection: Collection {
    typealias Index = DictionaryType.Index
    typealias Element = DictionaryType.Element

    var startIndex: Index { return observations.startIndex }
    var endIndex: Index { return observations.endIndex }

    subscript(index: Index) -> Element {
        get { return observations[index] }
    }

    func index(after i: Index) -> Index {
        return observations.index(after: i)
    }
}

extension ObservationTokenCollection {
    subscript(token: UUID) -> Closure? {
        get { return observations[token] }
        set { observations[token] = newValue }
    }

    mutating func insert(_ closure: @escaping Closure) -> UUID {
        let id = UUID()
        self[id] = closure
        return id
    }

    mutating func remove(_ id: UUID) {
        observations.removeValue(forKey: id)
    }

    var closures: [Closure] {
        return Array(observations.values)
    }
}
