//
//  LoopCareDataSource.swift
//  LoopCaregiverKit
//
//  A Looper followed through LoopCare (LoopCare docs/loopcaregiver-2.md):
//  the circle's data, signed commands, alerts and caregivers come from the
//  LoopCare web service. Not connected yet: every call says so.
//

import Foundation
import LoopKit
import NightscoutKit

public class LoopCareDataSource: RemoteDataServiceProvider {
    public let credentials: LoopCareCredentials
    private let settings: CaregiverSettings

    public init(credentials: LoopCareCredentials, settings: CaregiverSettings) {
        self.credentials = credentials
        self.settings = settings
    }

    public func checkAuth() async throws { throw LoopCareDataSourceError.notConnected }
    public func fetchGlucoseSamples() async throws -> [NewGlucoseSample] { throw LoopCareDataSourceError.notConnected }
    public func fetchRecentGlucoseSamples() async throws -> [NewGlucoseSample] { throw LoopCareDataSourceError.notConnected }
    public func fetchBolusEntries() async throws -> [BolusNightscoutTreatment] { throw LoopCareDataSourceError.notConnected }
    public func fetchBasalEntries() async throws -> [TempBasalNightscoutTreatment] { throw LoopCareDataSourceError.notConnected }
    public func fetchCarbEntries() async throws -> [CarbCorrectionNightscoutTreatment] { throw LoopCareDataSourceError.notConnected }
    public func fetchOverridePresets() async throws -> [OverrideTreatment] { throw LoopCareDataSourceError.notConnected }
    public func fetchLatestDeviceStatus() async throws -> DeviceStatus? { throw LoopCareDataSourceError.notConnected }
    public func deliverCarbs(amountInGrams: Double, absorptionTime: TimeInterval, consumedDate: Date) async throws { throw LoopCareDataSourceError.notConnected }
    public func deliverBolus(amountInUnits: Double) async throws { throw LoopCareDataSourceError.notConnected }
    public func startOverride(overrideName: String, durationTime: TimeInterval) async throws { throw LoopCareDataSourceError.notConnected }
    public func cancelOverride() async throws { throw LoopCareDataSourceError.notConnected }
    public func activateAutobolus(activate: Bool) async throws { throw LoopCareDataSourceError.notSupported }
    public func activateClosedLoop(activate: Bool) async throws { throw LoopCareDataSourceError.notSupported }
    public func fetchCurrentProfile() async throws -> ProfileSet { throw LoopCareDataSourceError.notConnected }
    public func fetchRecentCommands() async throws -> [RemoteCommand] { throw LoopCareDataSourceError.notConnected }
    public func deleteAllCommands() async throws { throw LoopCareDataSourceError.notSupported }
}

public enum LoopCareDataSourceError: LocalizedError {
    case notConnected
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "LoopCare isn't available in this version yet."
        case .notSupported: return "LoopCare doesn't support this."
        }
    }
}

public extension Looper {
    /// Where this Looper's data comes from: its Nightscout site, or its LoopCare circle.
    func makeRemoteDataSource(settings: CaregiverSettings) -> RemoteDataServiceProvider {
        switch backend {
        case .nightscout(let credentials): return NightscoutDataSource(credentials: credentials, settings: settings)
        case .loopCare(let credentials): return LoopCareDataSource(credentials: credentials, settings: settings)
        }
    }
}
