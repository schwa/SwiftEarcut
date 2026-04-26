// SwiftEarcut — pure Swift port of mapbox/earcut.hpp
// https://github.com/mapbox/earcut.hpp
//
// A fast polygon triangulation library. Takes a polygon with holes as input
// and produces a flat array of triangle vertex indices.

import simd
import HeapModule

// MARK: - Protocol

/// Conform your type to this protocol to use it directly with `earcut`.
public protocol PointProviding {
    associatedtype Scalar: BinaryFloatingPoint & SIMDScalar
    var point: SIMD2<Scalar> { get }
}

extension SIMD2: PointProviding where Scalar: BinaryFloatingPoint {
    public var point: SIMD2<Scalar> { self }
}

// MARK: - Public API

/// Triangulates a polygon of `PointProviding`-conforming values.
///
/// - Parameter polygon: An array of rings. The first ring is the outer boundary,
///   subsequent rings are holes. Each ring is an array of points.
/// - Returns: An array of indices into the flattened vertex list, where every three consecutive
///   indices form a triangle.
public func earcut<P: PointProviding>(polygon: [[P]]) -> [UInt32] {
    let converted = polygon.map { ring in ring.map { p -> SIMD2<Double> in
        let pt = p.point
        return SIMD2<Double>(Double(pt.x), Double(pt.y))
    }}
    var ec = Earcut()
    ec.run(polygon: converted)
    return ec.indices
}

/// Triangulates a polygon using key paths to extract x/y coordinates from arbitrary element types.
///
/// - Parameters:
///   - polygon: An array of rings. The first ring is the outer boundary,
///     subsequent rings are holes.
///   - x: Key path to the x coordinate.
///   - y: Key path to the y coordinate.
/// - Returns: An array of indices into the flattened vertex list, where every three consecutive
///   indices form a triangle.
public func earcut<T, S: BinaryFloatingPoint>(polygon: [[T]], x: KeyPath<T, S>, y: KeyPath<T, S>) -> [UInt32] {
    let converted = polygon.map { ring in ring.map { SIMD2<Double>(Double($0[keyPath: x]), Double($0[keyPath: y])) } }
    var ec = Earcut()
    ec.run(polygon: converted)
    return ec.indices
}

// MARK: - Testing hooks

/// Internal test helper: runs earcut on a polygon and returns a list of closures,
/// each of which weakly references a `Node` that was allocated during
/// triangulation. After this function returns, every closure should yield `nil`
/// if nodes are being released correctly (no retain cycles). See issue #2.
internal func earcutCollectingWeakNodes(polygon: [[SIMD2<Double>]]) -> (indices: [UInt32], weakNodes: [() -> Node?]) {
    var ec = Earcut()
    var weakRefs: [() -> Node?] = []
    ec.testingNodeSnapshot = { nodes in
        weakRefs = nodes.map { node in { [weak node] in node } }
    }
    ec.run(polygon: polygon)
    return (ec.indices, weakRefs)
}

// MARK: - Implementation

private struct Earcut {
    var indices: [UInt32] = []
    private var vertices: Int = 0
    private var nodes: NodePool = NodePool()

    /// Testing hook: if set, invoked with the live node storage just before the
    /// pool is cleared, so tests can capture weak references to verify nodes
    /// are released (see issue #2).
    var testingNodeSnapshot: (([Node]) -> Void)?

    private var hashing = false
    private var minX: Double = 0
    private var maxX: Double = 0
    private var minY: Double = 0
    private var maxY: Double = 0
    private var invSize: Double = 0

    mutating func run(polygon: [[SIMD2<Double>]]) {
        indices.removeAll()
        vertices = 0

        if polygon.isEmpty {
            return
        }

        let threshold: Int = polygon.reduce(80) { $0 - $1.count }
        let totalLen = polygon.reduce(0) { $0 + $1.count }

        nodes = NodePool(capacity: totalLen * 3 / 2)
        indices.reserveCapacity(totalLen + polygon[0].count)

        // Always clear the node pool on exit to break linked-list retain cycles
        // and release `Node` instances (see issue #2).
        defer {
            testingNodeSnapshot?(nodes.allNodesForTesting)
            nodes.clear()
        }

        guard var outerNode = linkedList(ring: polygon[0], clockwise: true) else {
            return
        }
        if outerNode.prev === outerNode.next {
            return
        }

        if polygon.count > 1 {
            outerNode = eliminateHoles(polygon: polygon, outerNode: outerNode)
        }

        hashing = threshold < 0
        if hashing {
            var p = outerNode.next!
            minX = outerNode.x
            maxX = outerNode.x
            minY = outerNode.y
            maxY = outerNode.y
            while p !== outerNode {
                let x = p.x
                let y = p.y
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
                p = p.next!
            }
            invSize = Swift.max(maxX - minX, maxY - minY)
            invSize = invSize != 0 ? (32767.0 / invSize) : 0
        }

        earcutLinked(ear: outerNode, pass: 0)
    }

    // MARK: - Linked list construction

    /// Creates a circular doubly-linked list from a ring of points in the specified winding order.
    private mutating func linkedList(ring: [SIMD2<Double>], clockwise: Bool) -> Node? {
        let len = ring.count
        if len == 0 {
            return nil
        }

        var sum: Double = 0
        for i in 0..<len {
            let j = (i == 0) ? len - 1 : i - 1
            let p1 = ring[i]
            let p2 = ring[j]
            sum += (p2.x - p1.x) * (p1.y + p2.y)
        }

        var last: Node?
        if clockwise == (sum > 0) {
            for i in 0..<len {
                last = insertNode(index: vertices + i, point: ring[i], last: last)
            }
        } else {
            for i in stride(from: len - 1, through: 0, by: -1) {
                last = insertNode(index: vertices + i, point: ring[i], last: last)
            }
        }

        if let l = last, equals(l, l.next!) {
            removeNode(l)
            last = l.next
        }

        vertices += len

        if let l = last {
            l.next!.prev = l  // ensure circularity
            return l
        }
        return nil
    }

    // MARK: - Filter points

    /// Eliminate colinear or duplicate points.
    @discardableResult
    private mutating func filterPoints(_ start: Node, end: Node? = nil) -> Node {
        var end = end ?? start
        var p = start
        var again: Bool
        repeat {
            again = false
            if !p.steiner && (equals(p, p.next!) || area(p.prev!, p, p.next!) == 0) {
                removeNode(p)
                let prev = p.prev!
                p = prev
                end = prev
                if p === p.next! {
                    break
                }
                again = true
            } else {
                p = p.next!
            }
        } while again || p !== end

        return end
    }

    // MARK: - Ear slicing

    /// Main ear slicing loop which triangulates a polygon (given as a linked list).
    private mutating func earcutLinked(ear startEar: Node, pass: Int) {
        var ear: Node? = startEar

        if !hashing && pass == 0 {
            // no-op; hashing done below
        }
        if pass == 0 && hashing {
            indexCurve(start: startEar)
        }

        var stop = ear!
        var prev: Node
        var next: Node

        while ear!.prev !== ear!.next {
            prev = ear!.prev!
            next = ear!.next!

            if hashing ? isEarHashed(ear!) : isEar(ear!) {
                indices.append(UInt32(prev.i))
                indices.append(UInt32(ear!.i))
                indices.append(UInt32(next.i))

                removeNode(ear!)

                ear = next.next
                stop = next.next!
                continue
            }

            ear = next

            if ear === stop {
                if pass == 0 {
                    earcutLinked(ear: filterPoints(ear!), pass: 1)
                } else if pass == 1 {
                    let filtered = filterPoints(ear!)
                    let cured = cureLocalIntersections(start: filtered)
                    earcutLinked(ear: cured, pass: 2)
                } else if pass == 2 {
                    splitEarcut(start: ear!)
                }
                break
            }
        }
    }

    /// Check whether a polygon node forms a valid ear with adjacent nodes.
    private func isEar(_ ear: Node) -> Bool {
        let a = ear.prev!
        let b = ear
        let c = ear.next!

        if area(a, b, c) >= 0 {
            return false
        }

        var p = ear.next!.next!
        while p !== ear.prev! {
            if pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, p.x, p.y)
                && area(p.prev!, p, p.next!) >= 0 {
                return false
            }
            p = p.next!
        }
        return true
    }

    /// Check whether a polygon node forms a valid ear (z-order optimized).
    private func isEarHashed(_ ear: Node) -> Bool {
        let a = ear.prev!
        let b = ear
        let c = ear.next!

        if area(a, b, c) >= 0 {
            return false
        }

        let minTX = Swift.min(a.x, Swift.min(b.x, c.x))
        let minTY = Swift.min(a.y, Swift.min(b.y, c.y))
        let maxTX = Swift.max(a.x, Swift.max(b.x, c.x))
        let maxTY = Swift.max(a.y, Swift.max(b.y, c.y))

        let minZ = zOrder(x: minTX, y: minTY)
        let maxZ = zOrder(x: maxTX, y: maxTY)

        var p = ear.nextZ
        while let pp = p, pp.z <= maxZ {
            if pp !== ear.prev && pp !== ear.next
                && pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, pp.x, pp.y)
                && area(pp.prev!, pp, pp.next!) >= 0 {
                return false
            }
            p = pp.nextZ
        }

        p = ear.prevZ
        while let pp = p, pp.z >= minZ {
            if pp !== ear.prev && pp !== ear.next
                && pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, pp.x, pp.y)
                && area(pp.prev!, pp, pp.next!) >= 0 {
                return false
            }
            p = pp.prevZ
        }

        return true
    }

    // MARK: - Cure local intersections

    /// Go through all polygon nodes and cure small local self-intersections.
    private mutating func cureLocalIntersections(start: Node) -> Node {
        var p = start
        var startNode = start
        repeat {
            let a = p.prev!
            let b = p.next!.next!

            if !equals(a, b) && intersects(a, p, p.next!, b) && locallyInside(a, b) && locallyInside(b, a) {
                indices.append(UInt32(a.i))
                indices.append(UInt32(p.i))
                indices.append(UInt32(b.i))

                removeNode(p)
                removeNode(p.next!)

                p = b
                startNode = b
            } else {
                p = p.next!
            }
        } while p !== startNode

        return filterPoints(p)
    }

    // MARK: - Split earcut

    /// Try splitting polygon into two and triangulate them independently.
    private mutating func splitEarcut(start: Node) {
        var a: Node = start
        let startNode = start
        repeat {
            var b = a.next!.next!
            while b !== a.prev! {
                if a.i != b.i && isValidDiagonal(a, b) {
                    var c = splitPolygon(a, b)

                    a = filterPoints(a, end: a.next)
                    c = filterPoints(c, end: c.next)

                    earcutLinked(ear: a, pass: 0)
                    earcutLinked(ear: c, pass: 0)
                    return
                }
                b = b.next!
            }
            a = a.next!
        } while a !== startNode
    }

    // MARK: - Hole elimination

    /// Link every hole into the outer loop, producing a single-ring polygon without holes.
    private mutating func eliminateHoles(polygon: [[SIMD2<Double>]], outerNode: Node) -> Node {
        var heap = Heap<Node>()

        for i in 1..<polygon.count {
            if let list = linkedList(ring: polygon[i], clockwise: false) {
                if list === list.next {
                    list.steiner = true
                }
                heap.insert(getLeftmost(start: list))
            }
        }

        var outer = outerNode
        while let hole = heap.popMin() {
            outer = eliminateHole(hole: hole, outerNode: outer)
        }

        return outer
    }

    /// Find a bridge between vertices that connects a hole with an outer ring and link it.
    private mutating func eliminateHole(hole: Node, outerNode: Node) -> Node {
        guard let bridge = findHoleBridge(hole: hole, outerNode: outerNode) else {
            return outerNode
        }

        let bridgeReverse = splitPolygon(bridge, hole)
        filterPoints(bridgeReverse, end: bridgeReverse.next)
        return filterPoints(bridge, end: bridge.next)
    }

    /// David Eberly's algorithm for finding a bridge between hole and outer polygon.
    private func findHoleBridge(hole: Node, outerNode: Node) -> Node? {
        var p = outerNode
        let hx = hole.x
        let hy = hole.y
        var qx = -Double.infinity
        var m: Node?

        repeat {
            if hy <= p.y && hy >= p.next!.y && p.next!.y != p.y {
                let x = p.x + (hy - p.y) * (p.next!.x - p.x) / (p.next!.y - p.y)
                if x <= hx && x > qx {
                    qx = x
                    m = p.x < p.next!.x ? p : p.next!
                    if x == hx {
                        return m
                    }
                }
            }
            p = p.next!
        } while p !== outerNode

        guard var m else {
            return nil
        }

        let stop = m
        var tanMin = Double.infinity

        p = m
        let mx = m.x
        let my = m.y

        repeat {
            let inTriangle = pointInTriangle(
                hy < my ? hx : qx, hy,
                mx, my,
                hy < my ? qx : hx, hy,
                p.x, p.y)
            if hx >= p.x && p.x >= mx && hx != p.x && inTriangle {
                let tanCur = abs(hy - p.y) / (hx - p.x)

                if locallyInside(p, hole)
                    && (tanCur < tanMin || (tanCur == tanMin && (p.x > m.x || sectorContainsSector(m, p)))) {
                    m = p
                    tanMin = tanCur
                }
            }
            p = p.next!
        } while p !== stop

        return m
    }

    /// Whether sector in node m contains sector in node p in the same coordinates.
    private func sectorContainsSector(_ m: Node, _ p: Node) -> Bool {
        area(m.prev!, m, p.prev!) < 0 && area(p.next!, m, m.next!) < 0
    }

    // MARK: - Z-order indexing

    /// Interlink polygon nodes in z-order.
    private mutating func indexCurve(start: Node) {
        var p: Node = start
        repeat {
            if p.z == 0 {
                p.z = zOrder(x: p.x, y: p.y)
            }
            p.prevZ = p.prev
            p.nextZ = p.next
            p = p.next!
        } while p !== start

        p.prevZ?.nextZ = nil
        p.prevZ = nil

        sortLinked(p)
    }

    /// Simon Tatham's linked list merge sort algorithm.
    @discardableResult
    private func sortLinked(_ list: Node) -> Node {
        var list: Node? = list
        var inSize = 1

        while true {
            var p = list
            list = nil
            var tail: Node?
            var numMerges = 0

            while p != nil {
                numMerges += 1
                var q = p
                var pSize = 0
                for _ in 0..<inSize {
                    pSize += 1
                    q = q?.nextZ
                    if q == nil {
                        break
                    }
                }

                var qSize = inSize

                while pSize > 0 || (qSize > 0 && q != nil) {
                    let e: Node
                    if pSize == 0 {
                        e = q!
                        q = q!.nextZ
                        qSize -= 1
                    } else if qSize == 0 || q == nil {
                        e = p!
                        p = p!.nextZ
                        pSize -= 1
                    } else if p!.z <= q!.z {
                        e = p!
                        p = p!.nextZ
                        pSize -= 1
                    } else {
                        e = q!
                        q = q!.nextZ
                        qSize -= 1
                    }

                    if let t = tail {
                        t.nextZ = e
                    } else {
                        list = e
                    }
                    e.prevZ = tail
                    tail = e
                }
                p = q
            }

            tail?.nextZ = nil

            if numMerges <= 1 {
                return list!
            }

            inSize *= 2
        }
    }

    /// Z-order of a point given coords and the data bounding box.
    private func zOrder(x xCoord: Double, y yCoord: Double) -> Int32 {
        var x = Int32((xCoord - minX) * invSize)
        var y = Int32((yCoord - minY) * invSize)

        x = (x | (x << 8)) & 0x00FF00FF
        x = (x | (x << 4)) & 0x0F0F0F0F
        x = (x | (x << 2)) & 0x33333333
        x = (x | (x << 1)) & 0x55555555

        y = (y | (y << 8)) & 0x00FF00FF
        y = (y | (y << 4)) & 0x0F0F0F0F
        y = (y | (y << 2)) & 0x33333333
        y = (y | (y << 1)) & 0x55555555

        return x | (y << 1)
    }

    // MARK: - Utility functions

    /// Find the leftmost node of a polygon ring.
    private func getLeftmost(start: Node) -> Node {
        var p = start
        var leftmost = start
        repeat {
            if p.x < leftmost.x || (p.x == leftmost.x && p.y < leftmost.y) {
                leftmost = p
            }
            p = p.next!
        } while p !== start
        return leftmost
    }

    /// Check if a point lies within a convex triangle.
    private func pointInTriangle(
        _ ax: Double, _ ay: Double,
        _ bx: Double, _ by: Double,
        _ cx: Double, _ cy: Double,
        _ px: Double, _ py: Double
    ) -> Bool {
        (cx - px) * (ay - py) >= (ax - px) * (cy - py)
            && (ax - px) * (by - py) >= (bx - px) * (ay - py)
            && (bx - px) * (cy - py) >= (cx - px) * (by - py)
    }

    /// Check if a diagonal between two polygon nodes is valid.
    private func isValidDiagonal(_ a: Node, _ b: Node) -> Bool {
        a.next!.i != b.i && a.prev!.i != b.i && !intersectsPolygon(a, b)
            && ((locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b)
                && (area(a.prev!, a, b.prev!) != 0.0 || area(a, b.prev!, b) != 0.0))
                || (equals(a, b) && area(a.prev!, a, a.next!) > 0 && area(b.prev!, b, b.next!) > 0))
    }

    /// Signed area of a triangle.
    private func area(_ p: Node, _ q: Node, _ r: Node) -> Double {
        (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
    }

    /// Check if two points are equal.
    private func equals(_ p1: Node, _ p2: Node) -> Bool {
        p1.x == p2.x && p1.y == p2.y
    }

    /// Check if two segments intersect.
    private func intersects(_ p1: Node, _ q1: Node, _ p2: Node, _ q2: Node) -> Bool {
        let o1 = sign(area(p1, q1, p2))
        let o2 = sign(area(p1, q1, q2))
        let o3 = sign(area(p2, q2, p1))
        let o4 = sign(area(p2, q2, q1))

        if o1 != o2 && o3 != o4 {
            return true
        }
        if o1 == 0 && onSegment(p1, p2, q1) { return true }
        if o2 == 0 && onSegment(p1, q2, q1) { return true }
        if o3 == 0 && onSegment(p2, p1, q2) { return true }
        if o4 == 0 && onSegment(p2, q1, q2) { return true }

        return false
    }

    /// For collinear points p, q, r, check if point q lies on segment pr.
    private func onSegment(_ p: Node, _ q: Node, _ r: Node) -> Bool {
        q.x <= Swift.max(p.x, r.x)
            && q.x >= Swift.min(p.x, r.x)
            && q.y <= Swift.max(p.y, r.y)
            && q.y >= Swift.min(p.y, r.y)
    }

    private func sign(_ val: Double) -> Int {
        (val > 0 ? 1 : 0) - (val < 0 ? 1 : 0)
    }

    /// Check if a polygon diagonal intersects any polygon segments.
    private func intersectsPolygon(_ a: Node, _ b: Node) -> Bool {
        var p = a
        repeat {
            if p.i != a.i && p.next!.i != a.i && p.i != b.i && p.next!.i != b.i
                && intersects(p, p.next!, a, b) {
                return true
            }
            p = p.next!
        } while p !== a
        return false
    }

    /// Check if a polygon diagonal is locally inside the polygon.
    private func locallyInside(_ a: Node, _ b: Node) -> Bool {
        if area(a.prev!, a, a.next!) < 0 {
            return area(a, b, a.next!) >= 0 && area(a, a.prev!, b) >= 0
        } else {
            return area(a, b, a.prev!) < 0 || area(a, a.next!, b) < 0
        }
    }

    /// Check if the middle point of a polygon diagonal is inside the polygon.
    private func middleInside(_ a: Node, _ b: Node) -> Bool {
        var p = a
        var inside = false
        let px = (a.x + b.x) / 2
        let py = (a.y + b.y) / 2
        repeat {
            if ((p.y > py) != (p.next!.y > py)) && p.next!.y != p.y
                && (px < (p.next!.x - p.x) * (py - p.y) / (p.next!.y - p.y) + p.x) {
                inside = !inside
            }
            p = p.next!
        } while p !== a
        return inside
    }

    // MARK: - Node manipulation

    /// Link two polygon vertices with a bridge.
    private mutating func splitPolygon(_ a: Node, _ b: Node) -> Node {
        let a2 = nodes.create(index: a.i, x: a.x, y: a.y)
        let b2 = nodes.create(index: b.i, x: b.x, y: b.y)
        let an = a.next!
        let bp = b.prev!

        a.next = b
        b.prev = a

        a2.next = an
        an.prev = a2

        b2.next = a2
        a2.prev = b2

        bp.next = b2
        b2.prev = bp

        return b2
    }

    /// Create a node and optionally link it with the previous one (circular doubly linked list).
    private mutating func insertNode(index: Int, point: SIMD2<Double>, last: Node?) -> Node {
        let p = nodes.create(index: index, x: point.x, y: point.y)

        if let last {
            p.next = last.next
            p.prev = last
            last.next!.prev = p
            last.next = p
        } else {
            p.prev = p
            p.next = p
        }

        return p
    }

    /// Remove a node from the linked list.
    private func removeNode(_ p: Node) {
        p.next!.prev = p.prev
        p.prev!.next = p.next

        if let prevZ = p.prevZ {
            prevZ.nextZ = p.nextZ
        }
        if let nextZ = p.nextZ {
            nextZ.prevZ = p.prevZ
        }
    }
}

// MARK: - Node

internal final class Node {
    let i: Int
    let x: Double
    let y: Double

    var prev: Node?
    var next: Node?

    var z: Int32 = 0

    var prevZ: Node?
    var nextZ: Node?

    var steiner: Bool = false

    init(index: Int, x: Double, y: Double) {
        self.i = index
        self.x = x
        self.y = y
    }
}

extension Node: Equatable {
    static func == (lhs: Node, rhs: Node) -> Bool {
        lhs === rhs
    }
}

extension Node: Comparable {
    /// Strict total order: primarily by `x`, then `y`, then vertex index `i`.
    ///
    /// A total order (rather than `lhs.x < rhs.x` alone) is required for
    /// determinism when `Node` values are inserted into `Heap`. Equal keys
    /// in a heap pop in unspecified order, which causes nondeterministic
    /// hole-elimination ordering for inputs with symmetric leftmost
    /// vertices (e.g. ellipses flattened to multiple rings sharing the
    /// same leftmost x). See issue #3.
    static func < (lhs: Node, rhs: Node) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.i < rhs.i
    }
}

// MARK: - NodePool

/// Simple object pool for Node allocation to reduce ARC overhead.
private struct NodePool {
    private var storage: [Node] = []

    init(capacity: Int = 0) {
        storage.reserveCapacity(capacity)
    }

    mutating func create(index: Int, x: Double, y: Double) -> Node {
        let node = Node(index: index, x: x, y: y)
        storage.append(node)
        return node
    }

    mutating func clear() {
        // Break retain cycles formed by the circular doubly-linked list pointers
        // (`next`/`prev` and `nextZ`/`prevZ`) before releasing the nodes. Without
        // this, ARC cannot reclaim the `Node` instances and they leak as root
        // cycles. See issue #2.
        for node in storage {
            node.prev = nil
            node.next = nil
            node.prevZ = nil
            node.nextZ = nil
        }
        storage.removeAll(keepingCapacity: true)
    }

    /// Testing-only accessor for the currently pooled nodes.
    var allNodesForTesting: [Node] { storage }
}
