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
    
    let coordinates = [Coordinate(x: 10, y: 10), Coordinate(x: 100, y: 100)]

    var body: some View {
    
        GeometryReader { geometry in
        
            ZStack {
                
                let width = geometry.size.width
                let height = geometry.size.height
                let xSpacing = width / cols
                let ySpacing = height / rows
                let diameter = geometry.size.width / 10
                
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
                
                ZStack {
                    ForEach(row1(size: geometry.size)) { coordinate in
                        Circle()
                            .size(width: diameter, height: diameter)
                            .foregroundColor(Color.red)
                            .offset(x: coordinate.x - diameter / 2, y: coordinate.y - diameter / 2)
                    }
                }
                
            }
        }
        .padding()
        .background{ Color.secondary }
    }
    
    func row1(size: CGSize) -> [Coordinate] {
        var row1 = [Coordinate]()
        let y = size.height / CGFloat(5) / CGFloat(2)
        for i in 0...5 {
            let x = size.width / 5 * CGFloat(i)
            row1.append(Coordinate(x: x, y: y))
        }
        return row1
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        GridView(rows: 5.0, cols: 5.0, gridColor: .black)
    }
}
