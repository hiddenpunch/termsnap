// 아이콘 시안 3개를 그린다. 사용: draw <A|B|C> <출력.png>
import AppKit

let S: CGFloat = 1024
let inset: CGFloat = 100
let base = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
func rr(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
func shadow(_ blur: CGFloat, _ y: CGFloat, _ a: CGFloat) { let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: -y); s.shadowColor = NSColor.black.withAlphaComponent(a); s.set() }

/// 작은 터미널 창(제목 막대 점 3개 + 분할선 + 프롬프트)
func window(_ r: NSRect, fill: NSColor, split: Bool, accents: [NSColor]) {
    NSGraphicsContext.saveGraphicsState(); shadow(40, 18, 0.35)
    fill.setFill(); rr(r, 46).fill()
    NSGraphicsContext.restoreGraphicsState()
    // 제목 막대 점
    for (i, col) in [c(255, 95, 87), c(254, 188, 46), c(40, 200, 64)].enumerated() {
        col.setFill(); NSBezierPath(ovalIn: NSRect(x: r.minX + 38 + CGFloat(i) * 44, y: r.maxY - 62, width: 26, height: 26)).fill()
    }
    let body = NSRect(x: r.minX + 30, y: r.minY + 30, width: r.width - 60, height: r.height - 110)
    let panes: [NSRect] = split
        ? [NSRect(x: body.minX, y: body.minY, width: body.width / 2 - 8, height: body.height),
           NSRect(x: body.midX + 8, y: body.midY + 8, width: body.width / 2 - 8, height: body.height / 2 - 8),
           NSRect(x: body.midX + 8, y: body.minY, width: body.width / 2 - 8, height: body.height / 2 - 8)]
        : [body]
    for (i, p) in panes.enumerated() {
        c(255, 255, 255, 0.06).setFill(); rr(p, 22).fill()
        let col = accents[i % accents.count]
        let font = NSFont.monospacedSystemFont(ofSize: min(p.height * 0.32, 96), weight: .heavy)
        let t = NSMutableAttributedString(string: ">", attributes: [.font: font, .foregroundColor: col])
        t.append(NSAttributedString(string: "_", attributes: [.font: font, .foregroundColor: c(255, 255, 255, 0.85)]))
        t.draw(at: NSPoint(x: p.minX + 26, y: p.maxY - t.size().height - 18))
    }
}

/// 반시계 방향으로 도는 복원 화살표. 위쪽이 비고, 끝에 삼각형 머리가 진행 방향을 가리킨다.
func restoreArrow(center: NSPoint, radius: CGFloat, width: CGFloat, color: NSColor) {
    let start: CGFloat = 115, end: CGFloat = 395          // 115° 에서 반시계로 280° 돌아 35° 에서 끝난다
    color.setStroke(); color.setFill()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end - 8, clockwise: false)
    arc.lineWidth = width; arc.lineCapStyle = .round; arc.stroke()
    let e = end * .pi / 180
    let p = NSPoint(x: center.x + radius * cos(e), y: center.y + radius * sin(e))
    let dir = NSPoint(x: -sin(e), y: cos(e))               // 반시계 진행 방향(접선)
    let nrm = NSPoint(x: cos(e), y: sin(e))                // 바깥쪽
    let L = width * 2.4
    let head = NSBezierPath()
    head.move(to: NSPoint(x: p.x + dir.x * L * 0.75, y: p.y + dir.y * L * 0.75))
    head.line(to: NSPoint(x: p.x - dir.x * L * 0.35 + nrm.x * L * 0.62, y: p.y - dir.y * L * 0.35 + nrm.y * L * 0.62))
    head.line(to: NSPoint(x: p.x - dir.x * L * 0.35 - nrm.x * L * 0.62, y: p.y - dir.y * L * 0.35 - nrm.y * L * 0.62))
    head.close(); head.lineJoinStyle = .round; head.lineWidth = width * 0.3; head.fill(); head.stroke()
}

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let which = CommandLine.arguments[1]
let bg = rr(base, 185)
switch which {
case "A":   // 겹친 세션 창 + 복원 배지
    NSGradient(colors: [c(255, 154, 84), c(232, 76, 61)])!.draw(in: bg, angle: -60)
    window(NSRect(x: 230, y: 330, width: 520, height: 420), fill: c(38, 40, 52, 0.55), split: false, accents: [c(140, 140, 160)])
    window(NSRect(x: 290, y: 250, width: 560, height: 450), fill: c(28, 30, 40), split: true, accents: [c(255, 150, 90), c(90, 210, 200), c(120, 230, 140)])
    NSGraphicsContext.saveGraphicsState(); shadow(30, 10, 0.3)
    c(255, 255, 255).setFill(); NSBezierPath(ovalIn: NSRect(x: 650, y: 150, width: 230, height: 230)).fill()
    NSGraphicsContext.restoreGraphicsState()
    restoreArrow(center: NSPoint(x: 765, y: 265), radius: 62, width: 26, color: c(232, 76, 61))
case "B":   // 셔터(스냅샷) + 프롬프트
    NSGradient(colors: [c(99, 102, 241), c(139, 92, 246), c(217, 70, 239)])!.draw(in: bg, angle: -60)
    let ctr = NSPoint(x: S / 2, y: S / 2), R: CGFloat = 270
    NSGraphicsContext.saveGraphicsState(); shadow(36, 14, 0.3)
    c(255, 255, 255, 0.96).setFill(); NSBezierPath(ovalIn: NSRect(x: ctr.x - R, y: ctr.y - R, width: R * 2, height: R * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    for i in 0..<6 {   // 셔터 날
        let a0 = CGFloat(i) * 60 * .pi / 180
        let p = NSBezierPath()
        p.move(to: NSPoint(x: ctr.x + R * 0.98 * cos(a0), y: ctr.y + R * 0.98 * sin(a0)))
        p.line(to: NSPoint(x: ctr.x + R * 0.98 * cos(a0 + 1.05), y: ctr.y + R * 0.98 * sin(a0 + 1.05)))
        p.line(to: NSPoint(x: ctr.x + 120 * cos(a0 + 1.6), y: ctr.y + 120 * sin(a0 + 1.6)))
        p.close()
        c(120, 100, 240, 0.18 + CGFloat(i % 2) * 0.08).setFill(); p.fill()
    }
    c(30, 27, 60).setFill(); NSBezierPath(ovalIn: NSRect(x: ctr.x - 150, y: ctr.y - 150, width: 300, height: 300)).fill()
    let font = NSFont.monospacedSystemFont(ofSize: 150, weight: .heavy)
    let t = NSMutableAttributedString(string: ">", attributes: [.font: font, .foregroundColor: c(110, 231, 183)])
    t.append(NSAttributedString(string: "_", attributes: [.font: font, .foregroundColor: NSColor.white]))
    t.draw(at: NSPoint(x: ctr.x - t.size().width / 2, y: ctr.y - t.size().height / 2 + 6))
default:    // C: 분할 타일 + 둘러싼 복원 화살표
    NSGradient(colors: [c(15, 23, 42), c(30, 41, 59)])!.draw(in: bg, angle: -90)
    restoreArrow(center: NSPoint(x: S / 2, y: S / 2), radius: 300, width: 34, color: c(56, 189, 248))
    let g = NSRect(x: 322, y: 322, width: 380, height: 380), gap: CGFloat = 18
    let cols = [c(251, 146, 60), c(45, 212, 191), c(163, 230, 53), c(148, 163, 184)]
    for i in 0..<4 {
        let x = g.minX + CGFloat(i % 2) * (g.width / 2 + gap / 2), y = g.minY + CGFloat(1 - i / 2) * (g.height / 2 + gap / 2)
        let r = NSRect(x: x, y: y, width: g.width / 2 - gap / 2, height: g.height / 2 - gap / 2)
        c(255, 255, 255, 0.10).setFill(); rr(r, 30).fill()
        cols[i].setFill(); rr(NSRect(x: r.minX + 28, y: r.maxY - 62, width: r.width * 0.5, height: 22), 11).fill()
        c(255, 255, 255, 0.35).setFill(); rr(NSRect(x: r.minX + 28, y: r.maxY - 104, width: r.width * 0.32, height: 18), 9).fill()
    }
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
