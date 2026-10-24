//
//  BolusNightscoutTreatment+Charts.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 1/7/23.
//

import Foundation
import LoopAlgorithm
import HealthKit
import NightscoutKit

extension BolusNightscoutTreatment {
    func graphItem(egvValues: [GraphItem], displayUnit: LoopUnit) -> GraphItem {
        let relativeEgvValue = interpolateEGVValue(egvs: egvValues, atDate: timestamp)
        return GraphItem(
            type: .bolus(self.amount),
            displayTime: timestamp,
            quantity: LoopQuantity(unit: displayUnit, doubleValue: relativeEgvValue),
            displayUnit: displayUnit,
            graphItemState: .success
        )
    }
}
