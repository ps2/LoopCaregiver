//
//  LooperBackendTestCase.swift
//  LoopCaregiverKitTests
//
//  A Looper is followed through Nightscout or LoopCare. Loopers saved before
//  LoopCare (Nightscout, Core Data model 2) must keep working unchanged.
//

import CoreData
@testable import LoopCaregiverKit
import XCTest

final class LooperBackendTestCase: XCTestCase {
    private let nightscout = NightscoutCredentials(url: URL(string: "https://ns.example.com")!, secretKey: "secret", otpURL: "otpauth://totp/x?secret=ABC")
    private let loopCare = LoopCareCredentials(siteURL: URL(string: "https://care.example.com")!, circle: "c_abc", keyID: "k_123")

    func testNightscoutLooperEncodesAsBefore() throws {
        let looper = Looper(identifier: UUID(), name: "Liz", nightscoutCredentials: nightscout, lastSelectedDate: Date(timeIntervalSince1970: 0))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(looper)) as? [String: Any]
        XCTAssertEqual(Set(json?.keys ?? [:].keys), ["identifier", "name", "lastSelectedDate", "nightscoutCredentials"])

        let decoded = try JSONDecoder().decode(Looper.self, from: JSONEncoder().encode(looper))
        XCTAssertEqual(decoded.backend, .nightscout(nightscout))
        XCTAssertEqual(decoded.nightscoutCredentials, nightscout)
        XCTAssertNil(decoded.loopCareCredentials)
    }

    func testLoopCareLooperRoundTrips() throws {
        let looper = Looper(identifier: UUID(), name: "Sam", backend: .loopCare(loopCare), lastSelectedDate: Date())
        let decoded = try JSONDecoder().decode(Looper.self, from: JSONEncoder().encode(looper))
        XCTAssertEqual(decoded.backend, .loopCare(loopCare))
        XCTAssertNil(decoded.nightscoutCredentials)
        XCTAssertTrue(looper.makeRemoteDataSource(settings: CaregiverSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!, appGroupsSupported: false)) is LoopCareDataSource)
    }

    func testBothKindsAreStored() throws {
        let service = CoreDataAccountService(containerFactory: InMemoryPersistentContainerFactory())
        try service.addLooper(Looper(identifier: UUID(), name: "Liz", nightscoutCredentials: nightscout, lastSelectedDate: Date()))
        try service.addLooper(Looper(identifier: UUID(), name: "Sam", backend: .loopCare(loopCare), lastSelectedDate: Date()))
        let loopers = Dictionary(uniqueKeysWithValues: try service.getLoopers().map { ($0.name, $0) })
        XCTAssertEqual(loopers["Liz"]?.backend, .nightscout(nightscout))
        XCTAssertEqual(loopers["Sam"]?.backend, .loopCare(loopCare))
    }

    /// A store written by the app before LoopCare opens with the new model, its Loopers still Nightscout ones.
    func testStoreFromModelVersion2Migrates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("LoopCaregiver.sqlite")

        let v2 = try XCTUnwrap(NSManagedObjectModel(contentsOf: Bundle.coreDataModelURL.appendingPathComponent("LoopCaregiver 2.mom")))
        XCTAssertNil(v2.entitiesByName["LooperCD"]?.attributesByName["loopCareCircle"])
        let old = NSPersistentContainer(name: "LoopCaregiver", managedObjectModel: v2)
        old.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        old.loadPersistentStores { _, error in XCTAssertNil(error) }
        let id = UUID()
        let row = NSEntityDescription.insertNewObject(forEntityName: "LooperCD", into: old.viewContext)
        row.setValue(id, forKey: "identifier")
        row.setValue("Liz", forKey: "name")
        row.setValue(Date(), forKey: "lastSelectedDate")
        row.setValue(nightscout.url.absoluteString, forKey: "nightscoutURL")
        row.setValue(nightscout.secretKey, forKey: "nightscoutAPISecret")
        row.setValue(nightscout.otpURL, forKey: "otpURL")
        try old.viewContext.save()
        for store in old.persistentStoreCoordinator.persistentStores {
            try old.persistentStoreCoordinator.remove(store)
        }

        let service = CoreDataAccountService(containerFactory: FilePersistentContainerFactory(storeURL: storeURL))
        let loopers = try service.getLoopers()
        XCTAssertEqual(loopers.map(\.identifier), [id])
        XCTAssertEqual(loopers.first?.backend, .nightscout(nightscout))
    }
}

/// The current model, on a store file of the test's choosing (migrating it as the app does).
private struct FilePersistentContainerFactory: PersistentContainerFactory {
    let storeURL: URL

    func createContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "LoopCaregiver", managedObjectModel: NSManagedObjectModel(contentsOf: Bundle.coreDataModelURL)!)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        container.loadPersistentStores { _, error in
            if let error { preconditionFailure("\(error)") }
        }
        return container
    }
}
