//
//  NewGlucoseSample+Presentable.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 6/3/23.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm

public extension NewGlucoseSample {
    func presentableUserValue(displayUnits: LoopUnit) -> Double {
        return quantity.doubleValue(for: displayUnits)
    }

    func presentableStringValue(displayUnits: LoopUnit, includeShortUnits: Bool) -> String {
        let unitInUserUnits = quantity.doubleValue(for: displayUnits)
        var result = LocalizationUtils.presentableStringFromGlucoseAmount(unitInUserUnits, displayUnits: displayUnits)
        if includeShortUnits {
            result += " " + displayUnits.shortLocalizedUnitString(avoidLineBreaking: true)
        }
        return result
    }
}

public extension [NewGlucoseSample] {
    func getLastGlucoseChange(displayUnits: LoopUnit) -> Double? {
        guard count > 1 else {
            return nil
        }
        let lastGlucoseValue = self[count - 1].presentableUserValue(displayUnits: displayUnits)
        let priorGlucoseValue = self[count - 2].presentableUserValue(displayUnits: displayUnits)
        return lastGlucoseValue - priorGlucoseValue
    }
}
