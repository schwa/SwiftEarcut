import Testing
import simd
@testable import SwiftEarcut

@Suite
struct EarcutTests {
    @Test func emptyPolygon() {
        let result = earcut(polygon: [] as [[SIMD2<Double>]])
        #expect(result.isEmpty)
    }

    @Test func emptyRing() {
        let result = earcut(polygon: [[]] as [[SIMD2<Double>]])
        #expect(result.isEmpty)
    }

    @Test func triangle() {
        let polygon: [[SIMD2<Double>]] = [[
            SIMD2(0, 0),
            SIMD2(1, 0),
            SIMD2(0, 1),
        ]]
        let indices = earcut(polygon: polygon)
        #expect(indices.count == 3)
        // Should produce exactly one triangle
        let set = Set(indices.map { Int($0) })
        #expect(set == [0, 1, 2])
    }

    @Test func square() {
        let polygon: [[SIMD2<Double>]] = [[
            SIMD2(0, 0),
            SIMD2(1, 0),
            SIMD2(1, 1),
            SIMD2(0, 1),
        ]]
        let indices = earcut(polygon: polygon)
        // A quad should produce 2 triangles = 6 indices
        #expect(indices.count == 6)
        // All indices should be in range 0..<4
        for idx in indices {
            #expect(idx < 4)
        }
    }

    @Test func pentagon() {
        // Regular pentagon
        let polygon: [[SIMD2<Double>]] = [[
            SIMD2(0.0, 1.0),
            SIMD2(0.951, 0.309),
            SIMD2(0.588, -0.809),
            SIMD2(-0.588, -0.809),
            SIMD2(-0.951, 0.309),
        ]]
        let indices = earcut(polygon: polygon)
        // 5 vertices → 3 triangles → 9 indices
        #expect(indices.count == 9)
    }

    @Test func squareWithSquareHole() {
        let polygon: [[SIMD2<Double>]] = [
            // Outer ring (clockwise)
            [
                SIMD2(0, 0),
                SIMD2(10, 0),
                SIMD2(10, 10),
                SIMD2(0, 10),
            ],
            // Hole (counter-clockwise)
            [
                SIMD2(2, 2),
                SIMD2(2, 8),
                SIMD2(8, 8),
                SIMD2(8, 2),
            ],
        ]
        let indices = earcut(polygon: polygon)
        // 8 vertices, with a hole. Should produce 8 triangles = 24 indices
        #expect(indices.count == 24)
        for idx in indices {
            #expect(idx < 8)
        }
    }

    @Test func floatOverload() {
        let polygon: [[SIMD2<Float>]] = [[
            SIMD2(0, 0),
            SIMD2(1, 0),
            SIMD2(1, 1),
            SIMD2(0, 1),
        ]]
        let indices = earcut(polygon: polygon)
        #expect(indices.count == 6)
    }

    @Test func lShapedPolygon() {
        // L-shaped polygon (concave)
        let polygon: [[SIMD2<Double>]] = [[
            SIMD2(0, 0),
            SIMD2(2, 0),
            SIMD2(2, 1),
            SIMD2(1, 1),
            SIMD2(1, 2),
            SIMD2(0, 2),
        ]]
        let indices = earcut(polygon: polygon)
        // 6 vertices → 4 triangles → 12 indices
        #expect(indices.count == 12)
    }

    @Test func degenerateTriangle() {
        // Collinear points — degenerate
        let polygon: [[SIMD2<Double>]] = [[
            SIMD2(0, 0),
            SIMD2(1, 0),
            SIMD2(2, 0),
        ]]
        let indices = earcut(polygon: polygon)
        // Collinear points should produce no triangles after filtering
        #expect(indices.isEmpty)
    }

    @Test func triangulationCoversAllArea() {
        // Verify that the sum of triangle areas equals the polygon area
        let polygon: [[SIMD2<Double>]] = [[
            SIMD2(0, 0),
            SIMD2(4, 0),
            SIMD2(4, 3),
            SIMD2(0, 3),
        ]]
        let indices = earcut(polygon: polygon)

        // Flatten vertices
        let verts = polygon[0]

        // Sum triangle areas
        var triArea: Double = 0
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = verts[Int(indices[i])]
            let b = verts[Int(indices[i + 1])]
            let c = verts[Int(indices[i + 2])]
            triArea += abs(cross2D(b - a, c - a)) / 2
        }

        // Polygon area = 4 * 3 = 12
        #expect(abs(triArea - 12.0) < 1e-10)
    }

    @Test func largePolygon() {
        // Circle approximation with many vertices — exercises z-order hashing path
        let n = 200
        var ring: [SIMD2<Double>] = []
        for i in 0..<n {
            let angle = Double(i) / Double(n) * 2 * .pi
            ring.append(SIMD2(cos(angle), sin(angle)))
        }
        let indices = earcut(polygon: [ring])
        // n vertices → (n-2) triangles → 3*(n-2) indices
        #expect(indices.count == 3 * (n - 2))
    }

    // MARK: - KeyPath API

    @Test func keyPathAPI() {
        struct Vertex {
            var px: Double
            var py: Double
        }
        let polygon: [[Vertex]] = [[
            Vertex(px: 0, py: 0),
            Vertex(px: 1, py: 0),
            Vertex(px: 1, py: 1),
            Vertex(px: 0, py: 1),
        ]]
        let indices = earcut(polygon: polygon, x: \.px, y: \.py)
        #expect(indices.count == 6)
    }

    @Test func keyPathFloatAPI() {
        struct Vertex {
            var px: Float
            var py: Float
        }
        let polygon: [[Vertex]] = [[
            Vertex(px: 0, py: 0),
            Vertex(px: 1, py: 0),
            Vertex(px: 1, py: 1),
            Vertex(px: 0, py: 1),
        ]]
        let indices = earcut(polygon: polygon, x: \.px, y: \.py)
        #expect(indices.count == 6)
    }

    // MARK: - EarcutPoint protocol API

    @Test func protocolAPI() {
        struct MyPoint: PointProviding {
            var lat: Float
            var lon: Float
            var point: SIMD2<Float> { SIMD2(lon, lat) }
        }
        let polygon: [[MyPoint]] = [[
            MyPoint(lat: 0, lon: 0),
            MyPoint(lat: 0, lon: 1),
            MyPoint(lat: 1, lon: 1),
            MyPoint(lat: 1, lon: 0),
        ]]
        let indices = earcut(polygon: polygon)
        #expect(indices.count == 6)
    }
}

private func cross2D(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
    a.x * b.y - a.y * b.x
}
