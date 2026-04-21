# ISSUES.md

---

## 1: Add 3D polygon triangulation support

+++
status: new
priority: medium
kind: feature
created: 2026-04-15T01:26:40Z
+++

Add a public API overload that accepts 3D polygons (`[[SIMD3<Float>]]`) and handles the projection to 2D internally.\n\nCurrently consumers (e.g. SwiftMesh) must manually:\n1. Compute face normal (Newell's method)\n2. Build a tangent frame from the normal\n3. Project 3D points onto the 2D plane\n4. Call earcut with the 2D points\n5. Map indices back\n\nThis should be a convenience API inside SwiftEarcut so multiple consumers can reuse it. The core earcut algorithm stays 2D — this just adds the projection wrapper.\n\nProposed API sketch:\n```swift\npublic func earcut(polygon: [[SIMD3<Float>]]) -> [UInt32]\n```\n\nAlso consider a `Point3DProviding` protocol for generic usage.

---

## 2: Node retain cycles leak memory after triangulation

+++
status: new
priority: high
kind: bug
created: 2026-04-21T07:19:14Z
+++

While profiling a consumer app with `leaks` (MallocStackLogging=1), 999 `Node` instances were reported as ROOT CYCLE leaks, traced back to `earcut(polygon:)` via `Mesh.triangulateFace` in SwiftMesh.

The `Node` class in `Sources/SwiftEarcut/Earcut.swift` (around line 721) uses strong references for all four linked-list pointers:

```swift
private final class Node {
    var prev: Node?
    var next: Node?
    var prevZ: Node?
    var nextZ: Node?
    ...
}
```

This forms retain cycles (`a.next = b; b.prev = a`) that ARC cannot break. `NodePool` keeps the nodes alive during the algorithm, but when the pool is deallocated the cycles prevent the `Node` instances from being freed.

### Repro
Run any SwiftMesh/SwiftEarcut consumer under `leaks` with `MallocStackLogging=1`. Example stack from a real run:

```
STACK OF 999 INSTANCES OF 'ROOT CYCLE: <Node>':
...
 9  MetalSprockets-Examples   MetalMesh.init(mesh:device:label:bufferLayout:)
 8  MetalSprockets-Examples   specialized MetalMesh.init(...)  MetalMesh.swift:118
 7  MetalSprockets-Examples   Mesh.triangulateFace(vertexIDs:)  Triangulation.swift:49
 6  MetalSprockets-Examples   earcut<A>(polygon:)
...
  ROOT CYCLE: <Node 0x...> [96]
     __strong next --> ROOT CYCLE: <Node 0x...> [96]
        __strong next --> CYCLE BACK TO <Node 0x...> [96]
```

### Suggested fixes (pick one)

1. **Weakify back-pointers.** Make `prev` and `prevZ` `weak var`. Smallest diff; preserves API.
2. **Break cycles explicitly** at the end of `earcut(polygon:)` by walking `NodePool.storage` and setting `next`/`prev`/`nextZ`/`prevZ` to `nil` before returning.
3. **Refactor `NodePool` to use value types + indices** instead of class references. Biggest change, but removes ARC overhead entirely and matches the pool's stated goal ("reduce ARC overhead").

Option 2 is the safest one-line-ish fix. Option 3 is the principled long-term fix.

---
