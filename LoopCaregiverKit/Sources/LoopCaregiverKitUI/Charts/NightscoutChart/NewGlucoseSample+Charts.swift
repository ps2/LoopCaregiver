//
//  NewGlucoseSample+Charts.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 11/25/22.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm

// Loop Charts
extension NewGlucoseSample: GlucoseValue {
    public var startDate: Date {
        return date
    }
}

// Nightscout Graph
extension NewGlucoseSample {
    func graphItem(displayUnit: LoopUnit) -> GraphItem {
        return GraphItem(
            type: .egv,
            displayTime: date,
            quantity: quantity,
            displayUnit: displayUnit,
            graphItemState: .success
        )
    }

    func predictedBGGraphItem(displayUnit: LoopUnit) -> GraphItem {
        return GraphItem(
            type: .predictedBG,
            displayTime: date,
            quantity: quantity,
            displayUnit: displayUnit,
            graphItemState: .success
        )
    }
}
