# SwiftEarcut

A pure Swift port of [mapbox/earcut.hpp](https://github.com/mapbox/earcut.hpp) — a fast polygon triangulation library.

Takes a polygon (with optional holes) and produces triangle indices suitable for rendering with Metal, SceneKit, RealityKit, etc.

## Usage

```swift
import SwiftEarcut
import simd

// Simple polygon
let square: [[SIMD2<Double>]] = [[
    SIMD2(0, 0),
    SIMD2(1, 0),
    SIMD2(1, 1),
    SIMD2(0, 1),
]]
let indices = earcut(polygon: square)
// [0, 1, 2, 2, 3, 0] — two triangles

// Polygon with a hole
let withHole: [[SIMD2<Double>]] = [
    // Outer ring
    [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)],
    // Hole
    [SIMD2(2, 2), SIMD2(2, 8), SIMD2(8, 8), SIMD2(8, 2)],
]
let indices2 = earcut(polygon: withHole)
// 24 indices — 8 triangles filling the area between the outer ring and the hole
```

Indices refer to the flattened vertex list (all rings concatenated). Every three consecutive indices form one triangle.

A `SIMD2<Float>` overload is also available.

## Adding to your project

```swift
dependencies: [
    .package(url: "https://github.com/schwa/SwiftEarcut", from: "0.1.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: ["SwiftEarcut"]),
]
```

## API

```swift
func earcut(polygon: [[SIMD2<Double>]]) -> [UInt32]
func earcut(polygon: [[SIMD2<Float>]]) -> [UInt32]
```

**Parameters:**
- `polygon` — An array of rings. The first ring is the outer boundary, subsequent rings are holes.

**Returns:** A flat array of vertex indices. Every three indices form a triangle.

## Credits

Port of [mapbox/earcut.hpp](https://github.com/mapbox/earcut.hpp) by Mapbox. The algorithm is based on ear clipping with z-order curve hashing for performance on large polygons.
