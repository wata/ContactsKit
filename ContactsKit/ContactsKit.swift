//
//  ContactsKit.swift
//  SmartContacts
//
//  Created by Wataru Nagasawa on 2/21/19.
//  Copyright © 2019 Wataru Nagasawa. All rights reserved.
//

import Foundation
import Contacts
import ContactsUI

private let errorDomain = "dev.wata.ContactsKit.error"

private func nsError(failureReason: String) -> NSError {
    return NSError(domain: errorDomain, code: -999, userInfo: [NSLocalizedDescriptionKey: failureReason])
}

public final class ContactsKit {
    public static let `default`: ContactsKit = {
        let request = CNContactFetchRequest(
            keysToFetch: [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactViewController.descriptorForRequiredKeys(),
                CNContactVCardSerialization.descriptorForRequiredKeys()
            ]
        )
        request.sortOrder = .userDefault
        request.predicate = nil
        request.mutableObjects = false
        request.unifyResults = true
        return ContactsKit(defaultFetchRequest: request)
    }()

    private let notAuthorizedError: NSError = nsError(failureReason: "The application is not authorized to access contact data")
    private let contactStore = CNContactStore()
    private let defaultFetchRequest: CNContactFetchRequest
    private var observations = ObservationTokenCollection()

    public init(defaultFetchRequest: CNContactFetchRequest) {
        self.defaultFetchRequest = defaultFetchRequest

        NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: nil) { [weak self] (_) in
            self?.observations.closures.forEach { $0() }
        }
    }

    public var authorizationStatus: CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }

    public var isAuthorized: Bool {
        return authorizationStatus == .authorized
    }

    public func requestAccess(handler: @escaping (Result<Bool, Swift.Error>) -> Void) {
        let status = authorizationStatus
        switch status {
        case .notDetermined:
            contactStore.requestAccess(for: .contacts) { (isAuthorized, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        handler(.failure(error))
                        return
                    }
                    handler(.success(isAuthorized))
                    self.observations.closures.forEach { $0() }
                }
            }
        default:
            handler(.success(status == .authorized))
        }
    }

    private func observe(closure: @escaping () -> Void) -> ObservationToken {
        // First call.
        closure()

        // Register closure to observations.
        let id = observations.insert(closure)
        return ObservationToken { [weak self] in
            self?.observations.remove(id)
        }
    }

    private func addObserver<T: AnyObject>(_ observer: T, closure: @escaping (T) -> Void) -> ObservationToken {
        let id = UUID()

        // First call.
        closure(observer)

        // Register closure to observations.
        observations[id] = { [weak self, weak observer] in
            guard let observer = observer else {
                self?.observations.remove(id)
                return
            }
            closure(observer)
        }

        return ObservationToken { [weak self] in
            self?.observations.remove(id)
        }
    }
}

// MARK: - Fetching Contact

extension ContactsKit {
    public func fetchContact(identifier: String, keys: [CNKeyDescriptor]? = nil) -> Result<CNContact, Error> {
        guard isAuthorized else {
            return .failure(notAuthorizedError)
        }
        do {
            let contact = try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keys ?? defaultFetchRequest.keysToFetch)
            return .success(contact)
        } catch let error {
            return .failure(error)
        }
    }

    public func fetchContacts(request: CNContactFetchRequest? = nil) -> Result<[CNContact], Error> {
        guard isAuthorized else {
            return .failure(notAuthorizedError)
        }
        do {
            var contacts = [CNContact]()
            try contactStore.enumerateContacts(with: request ?? defaultFetchRequest) { (contact, _) in
                contacts.append(contact)
            }
            return .success(contacts)
        } catch let error {
            return .failure(error)
        }
    }

    public func fetchContacts(predicate: NSPredicate, keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        guard isAuthorized else {
            return .failure(notAuthorizedError)
        }
        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keys ?? defaultFetchRequest.keysToFetch)
            return .success(contacts)
        } catch let error {
            return .failure(error)
        }
    }

    public func fetchContacts(name: String, keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        let predicate = CNContact.predicateForContacts(matchingName: name)
        return fetchContacts(predicate: predicate, keys: keys)
    }

    public func fetchContacts(email: String, keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        return fetchContacts(predicate: predicate, keys: keys)
    }

    public func fetchContacts(phoneNumber: String, keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        return fetchContacts(phoneNumber: CNPhoneNumber(stringValue: phoneNumber))
    }

    public func fetchContacts(phoneNumber: CNPhoneNumber, keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        let predicate = CNContact.predicateForContacts(matching: phoneNumber)
        return fetchContacts(predicate: predicate, keys: keys)
    }

    public func fetchContacts(identifiers: [String], keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
        return fetchContacts(predicate: predicate, keys: keys)
    }

    public func fetchContacts(groupIdentifier: String, keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        let predicate = CNContact.predicateForContactsInGroup(withIdentifier: groupIdentifier)
        return fetchContacts(predicate: predicate, keys: keys)
    }

    public func fetchContacts(containerIdentifier: String, keys: [CNKeyDescriptor]? = nil) -> Result<[CNContact], Error> {
        let predicate = CNContact.predicateForContactsInContainer(withIdentifier: containerIdentifier)
        return fetchContacts(predicate: predicate, keys: keys)
    }
}

extension ContactsKit {
    public func observeContact(identifier: String, keys: [CNKeyDescriptor]? = nil, using block: @escaping (Result<CNContact, Error>) -> Void) -> ObservationToken {
        return observe { [weak self] in
            guard let self = self else { return }
            let result = self.fetchContact(identifier: identifier, keys: keys)
            block(result)
        }
    }

    public func addContactObserver<T: AnyObject>(
        _ observer: T,
        identifier: String,
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<CNContact, Error>) -> Void
    ) -> ObservationToken {
        return addObserver(observer) { [weak self] (_) in
            guard let self = self else { return }
            let result = self.fetchContact(identifier: identifier, keys: keys)
            block(result)
        }
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        request: CNContactFetchRequest? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        return addObserver(observer) { [weak self] (_) in
            guard let self = self else { return }
            let result = self.fetchContacts(request: request)
            block(result)
        }
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        predicate: NSPredicate,
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        return addObserver(observer) { [weak self] (_) in
            guard let self = self else { return }
            let result = self.fetchContacts(predicate: predicate, keys: keys)
            block(result)
        }
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        name: String,
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNContact.predicateForContacts(matchingName: name)
        return addContactsObserver(observer, predicate: predicate, using: block)
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        email: String,
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        return addContactsObserver(observer, predicate: predicate, using: block)
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        phoneNumber: CNPhoneNumber,
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNContact.predicateForContacts(matching: phoneNumber)
        return addContactsObserver(observer, predicate: predicate, using: block)
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        identifiers: [String],
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
        return addContactsObserver(observer, predicate: predicate, using: block)
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        groupIdentifier: String,
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNContact.predicateForContactsInGroup(withIdentifier: groupIdentifier)
        return addContactsObserver(observer, predicate: predicate, using: block)
    }

    public func addContactsObserver<T: AnyObject>(
        _ observer: T,
        containerIdentifier: String,
        keys: [CNKeyDescriptor]? = nil,
        using block: @escaping (Result<[CNContact], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNContact.predicateForContactsInContainer(withIdentifier: containerIdentifier)
        return addContactsObserver(observer, predicate: predicate, using: block)
    }
}

// MARK: - Fetching Group

extension ContactsKit {
    public func fetchGroups(predicate: NSPredicate? = nil) -> Result<[CNGroup], Error> {
        guard isAuthorized else {
            return .failure(notAuthorizedError)
        }
        do {
            let groups = try contactStore.groups(matching: predicate)
            return .success(groups)
        } catch let error {
            return .failure(error)
        }
    }

    public func fetchGroups(identifiers: [String]) -> Result<[CNGroup], Error> {
        let predicate = CNGroup.predicateForGroups(withIdentifiers: identifiers)
        return fetchGroups(predicate: predicate)
    }

    public func fetchGroups(containerIdentifier: String) -> Result<[CNGroup], Error> {
        let predicate = CNGroup.predicateForGroupsInContainer(withIdentifier: containerIdentifier)
        return fetchGroups(predicate: predicate)
    }
}

extension ContactsKit {
    public func addGroupsObserver<T: AnyObject>(
        _ observer: T,
        predicate: NSPredicate? = nil,
        using block: @escaping (Result<[CNGroup], Error>) -> Void
    ) -> ObservationToken {
        return addObserver(observer) { [weak self] (_) in
            guard let self = self else { return }
            let result = self.fetchGroups(predicate: predicate)
            block(result)
        }
    }

    public func addGroupsObserver<T: AnyObject>(
        _ observer: T,
        identifiers: [String],
        using block: @escaping (Result<[CNGroup], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNGroup.predicateForGroups(withIdentifiers: identifiers)
        return addGroupsObserver(observer, predicate: predicate, using: block)
    }

    public func addGroupsObserver<T: AnyObject>(
        _ observer: T,
        containerIdentifier: String,
        using block: @escaping (Result<[CNGroup], Error>) -> Void
    ) -> ObservationToken {
        let predicate = CNGroup.predicateForGroupsInContainer(withIdentifier: containerIdentifier)
        return addGroupsObserver(observer, predicate: predicate, using: block)
    }
}

// MARK: - Fetching Container

extension ContactsKit {
    public func fetchContainers(predicate: NSPredicate? = nil) -> Result<[CNContainer], Error> {
        guard isAuthorized else {
            return .failure(notAuthorizedError)
        }
        do {
            let containers = try contactStore.containers(matching: predicate)
            return .success(containers)
        } catch let error {
            return .failure(error)
        }
    }

    public func fetchContainers(identifiers: [String]) -> Result<[CNContainer], Error> {
        let predicate = CNContainer.predicateForContainers(withIdentifiers: identifiers)
        return fetchContainers(predicate: predicate)
    }

    public func fetchContainers(contactIdentifier: String) -> Result<[CNContainer], Error> {
        let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: contactIdentifier)
        return fetchContainers(predicate: predicate)
    }

    public func fetchContainers(groupIdentifier: String) -> Result<[CNContainer], Error> {
        let predicate = CNContainer.predicateForContainerOfGroup(withIdentifier: groupIdentifier)
        return fetchContainers(predicate: predicate)
    }
}

// MARK: - Saving

extension ContactsKit {
    public enum SaveRequestType {
        case addContacts(contacts: [CNContact], containerIdentifier: String?)
        case addGroups(groups: [CNGroup], containerIdentifier: String?)
        case updateContacts(contacts: [CNMutableContact])
        case updateGroups(groups: [CNMutableGroup])
        case deleteContacts(contacts: [CNContact])
        case deleteGroups(groups: [CNGroup])
        case addMembers(contacts: [CNContact], group: CNGroup)
        case removeMembers(contacts: [CNContact], group: CNGroup)

        var request: CNSaveRequest {
            let req = CNSaveRequest()
            switch self {
            case .addContacts(let contacts, let containerIdentifier):
                contacts.forEach { req.add($0.mutableCopy() as! CNMutableContact, toContainerWithIdentifier: containerIdentifier) }
            case .addGroups(let groups, let containerIdentifier):
                groups.forEach { req.add($0.mutableCopy() as! CNMutableGroup, toContainerWithIdentifier: containerIdentifier) }
            case .updateContacts(let contacts):
                contacts.forEach { req.update($0) }
            case .updateGroups(let groups):
                groups.forEach { req.update($0) }
            case .deleteContacts(let contacts):
                contacts.forEach { req.delete($0.mutableCopy() as! CNMutableContact) }
            case .deleteGroups(let groups):
                groups.forEach { req.delete($0.mutableCopy() as! CNMutableGroup) }
            case .addMembers(let contacts, let group):
                contacts.forEach { req.addMember($0, to: group) }
            case .removeMembers(let contacts, let group):
                contacts.forEach { req.removeMember($0, from: group) }
            }
            return req
        }
    }

    @discardableResult
    public func execute(_ type: SaveRequestType) -> Result<Bool, Error> {
        guard isAuthorized else {
            return .failure(notAuthorizedError)
        }
        do {
            try contactStore.execute(type.request)
            return .success(true)
        } catch let error {
            return .failure(error)
        }
    }

    @discardableResult
    public func addGroup(name: String, toContainerWithIdentifier identifier: String? = nil) -> Result<Bool, Error> {
        let group = CNMutableGroup()
        group.name = name
        return execute(.addGroups(groups: [group], containerIdentifier: identifier))
    }
}

// MARK: - Country Code

extension ContactsKit {
    public static var countryCode: String {
        return CNContactsUserDefaults.shared().countryCode
    }
}

// MARK: - Sort Order

extension ContactsKit {
    public static var contactSortOrder: CNContactSortOrder {
        return CNContactsUserDefaults.shared().sortOrder
    }
}

// MARK: - Custom APIs

extension ContactsKit {
    public func fetchGroupedContacts(request: CNContactFetchRequest? = nil) -> Result<[CNGroup: [CNContact]], Error> {
        guard isAuthorized else {
            return .failure(notAuthorizedError)
        }
        do {
            let groups = try contactStore.groups(matching: nil)
            let groupedContacts = try groups.reduce(into: [CNGroup: [CNContact]]()) {
                let predicate = CNContact.predicateForContactsInGroup(withIdentifier: $1.identifier)
                let contacts = try contactStore.unifiedContacts(
                    matching: predicate,
                    keysToFetch: request?.keysToFetch ?? defaultFetchRequest.keysToFetch
                )
                $0[$1] = contacts
            }
            return .success(groupedContacts)
        } catch let error {
            return .failure(error)
        }
    }

    public func addGroupedContactsObserver<T: AnyObject>(
        _ observer: T,
        request: CNContactFetchRequest? = nil,
        using block: @escaping (Result<[CNGroup: [CNContact]], Error>) -> Void
    ) -> ObservationToken {
        return addObserver(observer) { [weak self] (_) in
            guard let self = self else { return }
            let result = self.fetchGroupedContacts(request: request)
            block(result)
        }
    }
}

extension ContactsKit {
    public static func importContacts(from url: URL) -> Result<[CNContact], Error> {
        do {
            let data = try Data(contentsOf: url)
            let contacts = try CNContactVCardSerialization.contacts(with: data)
            return .success(contacts)
        } catch let error {
            return .failure(error)
        }
    }

    public static func exportContacts(_ contacts: [CNContact]) -> Result<URL, Error> {
        do {
            let directoryURL = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString
            let fileURL = directoryURL.appendingPathComponent(fileName).appendingPathExtension("vcf")
            let data = try CNContactVCardSerialization.data(with: contacts)
            try data.write(to: fileURL, options: [.atomic])
            return .success(fileURL)
        } catch let error {
            return .failure(error)
        }
    }
}
