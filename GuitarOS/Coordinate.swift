//
//  Coordinate.swift
//  GuitarOS
//
//  Created by Aaron Anthony on 2022-12-25.
//

import Foundation

struct Coordinate: Identifiable, Hashable {
    var id: String {
        "\(x), \(y)"
    }

    let x: CGFloat
    let y: CGFloat
}
