//
//  ContentView.swift
//  GuitarOS
//
//  Created by Aaron Anthony on 2022-12-25.
//

import SwiftUI

struct GridView: View {

    let rows: CGFloat
    let cols: CGFloat
    let gridColor: Color

    var body: some View {
    
        GeometryReader { geometry in
        
            ZStack {
                
                let width = geometry.size.width
                let height = geometry.size.height
                let xSpacing = width / cols
                let ySpacing = height / rows
                
                Path { path in
                    
                    for index in 0...Int(cols) {
                        let vOffset: CGFloat = CGFloat(index) * xSpacing
                        path.move(to: CGPoint(x: vOffset, y: 0))
                        path.addLine(to: CGPoint(x: vOffset, y: height))
                    }
                    for index in 0...Int(rows) {
                        let hOffset: CGFloat = CGFloat(index) * ySpacing
                        path.move(to: CGPoint(x: 0, y: hOffset))
                        path.addLine(to: CGPoint(x: width, y: hOffset))
                    }
                }
                .stroke(gridColor)
                
                HStack {
                    Circle()
                        .foregroundColor(.blue)
                        .frame(width: 9, height: 9)
                    
                    Circle()
                        .foregroundColor(.blue)
                        .frame(width: 9, height: 9)
                    
                }
                
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        GridView(rows: 5.0, cols: 5.0, gridColor: .black)
    }
}
