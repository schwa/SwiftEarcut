# ISSUES.md

---

## 1: Add 3D polygon triangulation support
status: new
priority: medium
kind: feature
created: 2026-04-15T01:26:40Z

Add a public API overload that accepts 3D polygons (`[[SIMD3<Float>]]`) and handles the projection to 2D internally.\n\nCurrently consumers (e.g. SwiftMesh) must manually:\n1. Compute face normal (Newell's method)\n2. Build a tangent frame from the normal\n3. Project 3D points onto the 2D plane\n4. Call earcut with the 2D points\n5. Map indices back\n\nThis should be a convenience API inside SwiftEarcut so multiple consumers can reuse it. The core earcut algorithm stays 2D — this just adds the projection wrapper.\n\nProposed API sketch:\n```swift\npublic func earcut(polygon: [[SIMD3<Float>]]) -> [UInt32]\n```\n\nAlso consider a `Point3DProviding` protocol for generic usage.

---

