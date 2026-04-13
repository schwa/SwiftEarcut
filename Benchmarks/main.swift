import Foundation
import SwiftEarcut
import simd

// MARK: - Harness

struct BenchmarkResult {
    let name: String
    let vertices: Int
    let iterations: Int
    let totalSeconds: Double

    var perIterationMicroseconds: Double { totalSeconds / Double(iterations) * 1_000_000 }
    var verticesPerSecond: Double { Double(vertices) * Double(iterations) / totalSeconds }
}

func benchmark(name: String, vertices: Int, iterations: Int, body: () -> Void) -> BenchmarkResult {
    // Warmup
    for _ in 0..<min(iterations, 3) {
        body()
    }

    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
        body()
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    return BenchmarkResult(name: name, vertices: vertices, iterations: iterations, totalSeconds: elapsed)
}

func printResult(_ r: BenchmarkResult) {
    let usPerIter = String(format: "%.1f", r.perIterationMicroseconds)
    let mVerts = String(format: "%.2f", r.verticesPerSecond / 1_000_000)
    print("  \(r.name): \(usPerIter) µs/iter (\(mVerts)M verts/s, \(r.iterations) iters)")
}

// MARK: - Polygon generators

func makeCircle(n: Int) -> [[SIMD2<Double>]] {
    let ring = (0..<n).map { i -> SIMD2<Double> in
        let a = Double(i) / Double(n) * 2.0 * .pi
        return SIMD2(cos(a), sin(a))
    }
    return [ring]
}

func makeCircleWithHole(outer: Int, inner: Int) -> [[SIMD2<Double>]] {
    let outerRing = (0..<outer).map { i -> SIMD2<Double> in
        let a = Double(i) / Double(outer) * 2.0 * .pi
        return SIMD2(cos(a) * 10, sin(a) * 10)
    }
    let innerRing = (0..<inner).map { i -> SIMD2<Double> in
        let a = Double(i) / Double(inner) * 2.0 * .pi
        return SIMD2(cos(a) * 5, sin(a) * 5)
    }
    return [outerRing, innerRing]
}

func makeGrid(nx: Int, ny: Int) -> [[SIMD2<Double>]] {
    // Zigzag polygon covering a grid — creates a complex non-convex shape
    var ring: [SIMD2<Double>] = []
    for row in 0..<ny {
        if row % 2 == 0 {
            for col in 0..<nx {
                ring.append(SIMD2(Double(col), Double(row)))
            }
        } else {
            for col in stride(from: nx - 1, through: 0, by: -1) {
                ring.append(SIMD2(Double(col), Double(row)))
            }
        }
    }
    return [ring]
}

// MARK: - Main

print("SwiftEarcut Benchmarks")
print("======================\n")

let configs: [(String, [[SIMD2<Double>]], Int)] = [
    ("triangle (3v)", [[SIMD2(0,0), SIMD2(1,0), SIMD2(0,1)]], 100_000),
    ("quad (4v)", [[SIMD2(0,0), SIMD2(1,0), SIMD2(1,1), SIMD2(0,1)]], 100_000),
    ("circle 32v", makeCircle(n: 32), 50_000),
    ("circle 100v", makeCircle(n: 100), 20_000),
    ("circle 500v", makeCircle(n: 500), 5_000),
    ("circle 1000v", makeCircle(n: 1000), 2_000),
    ("circle 5000v", makeCircle(n: 5000), 200),
    ("circle+hole 200+100v", makeCircleWithHole(outer: 200, inner: 100), 5_000),
    ("circle+hole 1000+500v", makeCircleWithHole(outer: 1000, inner: 500), 500),
    ("grid 50×20 (1000v)", makeGrid(nx: 50, ny: 20), 2_000),
    ("grid 100×50 (5000v)", makeGrid(nx: 100, ny: 50), 200),
]

for (name, polygon, iters) in configs {
    let verts = polygon.reduce(0) { $0 + $1.count }
    let result = benchmark(name: name, vertices: verts, iterations: iters) {
        _ = earcut(polygon: polygon)
    }
    printResult(result)
}

print("\nDone.")
