import Testing
import simd
@testable import SwiftEarcut

/// Regression tests for issue #2: Node retain cycles leaked memory after
/// triangulation because the circular doubly-linked list pointers
/// (`next`/`prev` and `nextZ`/`prevZ`) were all strong references.
@Suite
struct LeakTests {
    @Test func nodesAreReleasedAfterSimpleTriangulation() {
        let polygon: [[SIMD2<Double>]] = [[
            SIMD2(0, 0),
            SIMD2(10, 0),
            SIMD2(10, 10),
            SIMD2(0, 10),
        ]]
        let (indices, weakNodes) = _earcutCollectingWeakNodes(polygon: polygon)
        #expect(!indices.isEmpty)
        #expect(!weakNodes.isEmpty)
        for ref in weakNodes {
            #expect(ref() == nil, "Node leaked after triangulation (retain cycle)")
        }
    }

    @Test func nodesAreReleasedWithHolesAndHashing() {
        // Large enough to exercise the z-order hashing path (threshold < 0),
        // which sets up the `prevZ`/`nextZ` linked list in addition to
        // `prev`/`next`.
        var outer: [SIMD2<Double>] = []
        let n = 120
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            outer.append(SIMD2(cos(a) * 100, sin(a) * 100))
        }
        var hole: [SIMD2<Double>] = []
        for i in 0..<20 {
            let a = Double(i) / 20.0 * 2 * .pi
            // holes wind opposite to outer
            hole.append(SIMD2(cos(-a) * 10, sin(-a) * 10))
        }
        let polygon = [outer, hole]
        let (indices, weakNodes) = _earcutCollectingWeakNodes(polygon: polygon)
        #expect(!indices.isEmpty)
        #expect(!weakNodes.isEmpty)
        for ref in weakNodes {
            #expect(ref() == nil, "Node leaked after triangulation with hashing")
        }
    }
}
