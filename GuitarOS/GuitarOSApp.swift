//
//  GuitarOSApp.swift
//  GuitarOS
//
//  Created by Aaron Anthony on 2022-12-25.
//

import SwiftUI

@main
struct GuitarOSApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                GridView(rows: 5.0, cols: 5.0, gridColor: .black)
                GridView(rows: 5.0, cols: 5.0, gridColor: .black)
                GridView(rows: 5.0, cols: 5.0, gridColor: .black)
                GridView(rows: 5.0, cols: 5.0, gridColor: .black)
                GridView(rows: 5.0, cols: 5.0, gridColor: .black)
            }
            .padding()
        }
    }
}
