# SwiftEarcut

A pure Swift port of [mapbox/earcut.hpp](https://github.com/mapbox/earcut.hpp) — a fast polygon triangulation library.

Takes a polygon (with optional holes) and produces triangle indices suitable for rendering with Metal, SceneKit, RealityKit, etc.

## Usage

### SIMD2 (Direct)

Works out of the box with `SIMD2<Double>` and `SIMD2<Float>`:

```swift
import SwiftEarcut
import simd

let square: [[SIMD2<Double>]] = [[
    SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1),
]]
let indices = earcut(polygon: square)
// [0, 1, 2, 2, 3, 0] — two triangles
```

### Polygon with Holes

The first ring is the outer boundary; subsequent rings are holes:

```swift
let withHole: [[SIMD2<Double>]] = [
    [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)],  // outer
    [SIMD2(2, 2), SIMD2(2, 8), SIMD2(8, 8), SIMD2(8, 2)],      // hole
]
let indices = earcut(polygon: withHole)
```

### PointProviding Protocol

Conform your own types to `PointProviding` to use them directly:

```swift
struct GeoCoord: PointProviding {
    var lat: Float
    var lon: Float
    var point: SIMD2<Float> { SIMD2(lon, lat) }
}

let polygon: [[GeoCoord]] = [[
    GeoCoord(lat: 0, lon: 0),
    GeoCoord(lat: 0, lon: 1),
    GeoCoord(lat: 1, lon: 1),
    GeoCoord(lat: 1, lon: 0),
]]
let indices = earcut(polygon: polygon)
```

The associated `Scalar` type can be any `BinaryFloatingPoint & SIMDScalar` (e.g. `Float`, `Double`).

### KeyPath API

For types you don't own, use key paths to extract coordinates:

```swift
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
```

Works with both `Float` and `Double` key paths.

## API Reference

```swift
// PointProviding protocol — conform your types
protocol PointProviding {
    associatedtype Scalar: BinaryFloatingPoint & SIMDScalar
    var point: SIMD2<Scalar> { get }
}

// Triangulate any PointProviding type (includes SIMD2<Float> and SIMD2<Double>)
func earcut<P: PointProviding>(polygon: [[P]]) -> [UInt32]

// Triangulate using key paths
func earcut<T, S: BinaryFloatingPoint>(polygon: [[T]], x: KeyPath<T, S>, y: KeyPath<T, S>) -> [UInt32]
```

Indices refer to the flattened vertex list (all rings concatenated). Every three consecutive indices form one triangle.

## Adding to Your Project

```swift
dependencies: [
    .package(url: "https://github.com/schwa/SwiftEarcut", from: "0.1.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: ["SwiftEarcut"]),
]
```

## Credits

Port of [mapbox/earcut.hpp](https://github.com/mapbox/earcut.hpp) by Mapbox. The algorithm is based on ear clipping with z-order curve hashing for performance on large polygons.
