import SwiftUI

extension ProceduralShapeGenerator {

    struct BlobSource {
        let center: CGPoint
        let radius: CGFloat
    }

    /// Computes a merged metaball contour for multiple blob sources using marching squares.
    static func metaballPath(
        blobs: [BlobSource],
        in rect: CGRect,
        gridResolution: Int = 50,
        threshold: CGFloat = 1.0
    ) -> Path {
        guard !blobs.isEmpty else { return Path() }

        let cols = gridResolution
        let rows = Int(CGFloat(gridResolution) * rect.height / rect.width)
        let cellW = rect.width / CGFloat(cols)
        let cellH = rect.height / CGFloat(rows)

        var field = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: cols + 1), count: rows + 1)
        for row in 0...rows {
            for col in 0...cols {
                let px = rect.minX + CGFloat(col) * cellW
                let py = rect.minY + CGFloat(row) * cellH
                var value: CGFloat = 0
                for blob in blobs {
                    let dx = px - blob.center.x
                    let dy = py - blob.center.y
                    let distSq = dx * dx + dy * dy
                    let rSq = blob.radius * blob.radius
                    value += rSq / max(distSq, 1)
                }
                field[row][col] = value
            }
        }

        return marchingSquaresPath(field: field, cols: cols, rows: rows,
                                    cellW: cellW, cellH: cellH,
                                    originX: rect.minX, originY: rect.minY,
                                    threshold: threshold)
    }

    private static func marchingSquaresPath(
        field: [[CGFloat]], cols: Int, rows: Int,
        cellW: CGFloat, cellH: CGFloat,
        originX: CGFloat, originY: CGFloat,
        threshold: CGFloat
    ) -> Path {
        var segments = [(CGPoint, CGPoint)]()

        for row in 0..<rows {
            for col in 0..<cols {
                let tl = field[row][col]
                let tr = field[row][col + 1]
                let br = field[row + 1][col + 1]
                let bl = field[row + 1][col]

                let x = originX + CGFloat(col) * cellW
                let y = originY + CGFloat(row) * cellH

                let config = (tl >= threshold ? 8 : 0) |
                             (tr >= threshold ? 4 : 0) |
                             (br >= threshold ? 2 : 0) |
                             (bl >= threshold ? 1 : 0)

                guard config != 0 && config != 15 else { continue }

                func lerpX(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
                    let t = (threshold - a) / (b - a)
                    return x + t * cellW
                }
                func lerpY(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
                    let t = (threshold - a) / (b - a)
                    return y + t * cellH
                }

                let top    = CGPoint(x: lerpX(tl, tr), y: y)
                let right  = CGPoint(x: x + cellW, y: lerpY(tr, br))
                let bottom = CGPoint(x: lerpX(bl, br), y: y + cellH)
                let left   = CGPoint(x: x, y: lerpY(tl, bl))

                switch config {
                case 1:  segments.append((left, bottom))
                case 2:  segments.append((bottom, right))
                case 3:  segments.append((left, right))
                case 4:  segments.append((top, right))
                case 5:  segments.append((top, left)); segments.append((bottom, right))
                case 6:  segments.append((top, bottom))
                case 7:  segments.append((top, left))
                case 8:  segments.append((top, left))
                case 9:  segments.append((top, bottom))
                case 10: segments.append((top, right)); segments.append((left, bottom))
                case 11: segments.append((top, right))
                case 12: segments.append((left, right))
                case 13: segments.append((bottom, right))
                case 14: segments.append((left, bottom))
                default: break
                }
            }
        }

        return connectSegmentsIntoPath(segments)
    }

    private static func connectSegmentsIntoPath(_ segments: [(CGPoint, CGPoint)]) -> Path {
        guard !segments.isEmpty else { return Path() }

        var remaining = segments
        var path = Path()
        let epsilon: CGFloat = 2.0

        while !remaining.isEmpty {
            let first = remaining.removeFirst()
            var chain = [first.0, first.1]

            var changed = true
            while changed {
                changed = false
                for i in (0..<remaining.count).reversed() {
                    let seg = remaining[i]
                    if distance(chain.last!, seg.0) < epsilon {
                        chain.append(seg.1)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.last!, seg.1) < epsilon {
                        chain.append(seg.0)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.first!, seg.1) < epsilon {
                        chain.insert(seg.0, at: 0)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.first!, seg.0) < epsilon {
                        chain.insert(seg.1, at: 0)
                        remaining.remove(at: i)
                        changed = true
                    }
                }
            }

            if chain.count >= 3 {
                path.addPath(smoothClosedPath(through: chain))
            }
        }

        return path
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
