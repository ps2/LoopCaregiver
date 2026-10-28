//
//  LoopSightDataSource.swift
//  LoopCaregiverKit
//
//  A Looper followed through LoopSight (LoopSight docs/loopcaregiver-2.md):
//  the circle's data, signed commands, alerts and caregivers come from the
//  LoopSight web service. Not connected yet: every call says so.
//

import Foundation
import LoopKit
import NightscoutKit

public class LoopSightDataSource: RemoteDataServiceProvider {
    public let credentials: LoopSightCredentials
    private let settings: CaregiverSettings

    public init(credentials: LoopSightCredentials, settings: CaregiverSettings) {
        self.credentials = credentials
        self.settings = settings
    }

    /// Whether Loop has confirmed this caregiver: until then, the circle refuses their requests.
    public func checkAuth() async throws {
        let client = LoopSightClient(key: try CaregiverKeyStore.loadOrCreate())
        do {
            _ = try await client.request(base: credentials.siteURL, method: "GET", path: "/v1/circles/\(credentials.circle)/circle")
        } catch LoopSightClientError.badResponse(let status, _) where status == 401 || status == 403 {
            throw LoopSightDataSourceError.awaitingConfirmation
        }
    }
    public func fetchGlucoseSamples() async throws -> [NewGlucoseSample] { throw LoopSightDataSourceError.notConnected }
    public func fetchRecentGlucoseSamples() async throws -> [NewGlucoseSample] { throw LoopSightDataSourceError.notConnected }
    public func fetchBolusEntries() async throws -> [BolusNightscoutTreatment] { throw LoopSightDataSourceError.notConnected }
    public func fetchBasalEntries() async throws -> [TempBasalNightscoutTreatment] { throw LoopSightDataSourceError.notConnected }
    public func fetchCarbEntries() async throws -> [CarbCorrectionNightscoutTreatment] { throw LoopSightDataSourceError.notConnected }
    public func fetchOverridePresets() async throws -> [OverrideTreatment] { throw LoopSightDataSourceError.notConnected }
    public func fetchLatestDeviceStatus() async throws -> DeviceStatus? { throw LoopSightDataSourceError.notConnected }
    public func deliverCarbs(amountInGrams: Double, absorptionTime: TimeInterval, consumedDate: Date) async throws { throw LoopSightDataSourceError.notConnected }
    public func deliverBolus(amountInUnits: Double) async throws { throw LoopSightDataSourceError.notConnected }
    public func startOverride(overrideName: String, durationTime: TimeInterval) async throws { throw LoopSightDataSourceError.notConnected }
    public func cancelOverride() async throws { throw LoopSightDataSourceError.notConnected }
    public func activateAutobolus(activate: Bool) async throws { throw LoopSightDataSourceError.notSupported }
    public func activateClosedLoop(activate: Bool) async throws { throw LoopSightDataSourceError.notSupported }
    public func fetchCurrentProfile() async throws -> ProfileSet { throw LoopSightDataSourceError.notConnected }
    public func fetchRecentCommands() async throws -> [RemoteCommand] { throw LoopSightDataSourceError.notConnected }
    public func deleteAllCommands() async throws { throw LoopSightDataSourceError.notSupported }
}

public enum LoopSightDataSourceError: LocalizedError {
    case notConnected
    case notSupported
    case awaitingConfirmation

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "LoopSight isn't available in this version yet."
        case .notSupported: return "LoopSight doesn't support this."
        case .awaitingConfirmation: return "Waiting for Loop to confirm you. Ask them to open LoopSight in Loop's settings."
        }
    }
}

public extension Looper {
    /// Where this Looper's data comes from: its Nightscout site, or its LoopSight circle.
    func makeRemoteDataSource(settings: CaregiverSettings) -> RemoteDataServiceProvider {
        switch backend {
        case .nightscout(let credentials): return NightscoutDataSource(credentials: credentials, settings: settings)
        case .loopSight(let credentials): return LoopSightDataSource(credentials: credentials, settings: settings)
        }
    }
}
