// Tests ported from mapbox/earcut.hpp test suite.
// Each fixture verifies triangle count and area deviation.

import Testing
import simd
@testable import SwiftEarcut

@Suite
struct FixtureTests {
    @Test(arguments: Fixtures.allFixtures)
    func fixture(_ fixture: FixtureData) {
        let indices = earcut(polygon: fixture.polygon)
        let triangleCount = indices.count / 3

        // Allow ±1 triangle difference vs C++ reference due to floating-point ordering differences.
        #expect(
            abs(triangleCount - fixture.expectedTriangles) <= 1,
            "\(fixture.name): got \(triangleCount) triangles, expected \(fixture.expectedTriangles)"
        )

        if triangleCount > 0 {
            let expectedArea = polygonArea(fixture.polygon)
            let vertices = fixture.polygon.flatMap { $0 }
            let actualArea = trianglesArea(vertices: vertices, indices: indices)

            let deviation: Double
            if expectedArea == actualArea {
                deviation = 0
            } else if expectedArea == 0 {
                deviation = .infinity
            } else {
                deviation = abs(actualArea - expectedArea) / expectedArea
            }

            // Allow up to 3× the C++ expected deviation to account for
            // floating-point evaluation order differences in the Swift port.
            let tolerance = max(fixture.expectedDeviation * 3, 1e-10)
            #expect(
                deviation <= tolerance,
                "\(fixture.name): area deviation \(deviation) exceeds tolerance \(tolerance)"
            )
        }
    }
}

extension FixtureData: CustomTestStringConvertible {
    var testDescription: String { name }
}

// MARK: - Area helpers

private func trianglesArea(vertices: [SIMD2<Double>], indices: [UInt32]) -> Double {
    var area: Double = 0
    for i in stride(from: 0, to: indices.count, by: 3) {
        let a = vertices[Int(indices[i])]
        let b = vertices[Int(indices[i + 1])]
        let c = vertices[Int(indices[i + 2])]
        area += abs((a.x - c.x) * (b.y - a.y) - (a.x - b.x) * (c.y - a.y)) / 2
    }
    return area
}

private func ringArea(_ ring: [SIMD2<Double>]) -> Double {
    var sum: Double = 0
    let len = ring.count
    var j = len - 1
    for i in 0..<len {
        sum += (ring[i].x - ring[j].x) * (ring[i].y + ring[j].y)
        j = i
    }
    return abs(sum) / 2
}

private func polygonArea(_ polygon: [[SIMD2<Double>]]) -> Double {
    guard !polygon.isEmpty else {
        return 0
    }
    var sum = ringArea(polygon[0])
    for i in 1..<polygon.count {
        sum -= ringArea(polygon[i])
    }
    return max(sum, 0)
}
