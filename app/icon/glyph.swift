// 상단바용 단색 아이콘(템플릿). 앱 아이콘 A 의 겹친 창 두 장 + 복원 화살표를 윤곽선으로 옮긴 것.
import AppKit

func menuBarGlyph(scale: CGFloat = 1) -> NSImage {
    let W: CGFloat = 24, H: CGFloat = 16
    let img = NSImage(size: NSSize(width: W * scale, height: H * scale), flipped: false) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: scale, y: scale)
        NSColor.black.setStroke(); NSColor.black.setFill()
        let lw: CGFloat = 1.4
        // 뒤 창: 왼쪽 위 모서리만 보이게
        let back = NSBezierPath()
        back.move(to: NSPoint(x: 1.2, y: 6))
        back.line(to: NSPoint(x: 1.2, y: 12.6))
        back.appendArc(from: NSPoint(x: 1.2, y: 15.0), to: NSPoint(x: 3.6, y: 15.0), radius: 2.2)
        back.line(to: NSPoint(x: 12, y: 15.0))
        back.lineWidth = lw; back.lineCapStyle = .round; back.stroke()
        // 앞 창
        let front = NSRect(x: 4, y: 1.2, width: 13.5, height: 11.4)
        let fp = NSBezierPath(roundedRect: front, xRadius: 2.2, yRadius: 2.2)
        fp.lineWidth = lw; fp.stroke()
        let bar = NSBezierPath(); bar.move(to: NSPoint(x: front.minX, y: front.maxY - 3)); bar.line(to: NSPoint(x: front.maxX, y: front.maxY - 3))
        bar.lineWidth = lw * 0.8; bar.stroke()
        // 프롬프트 >
        let pr = NSBezierPath(); pr.move(to: NSPoint(x: 6.6, y: 7.4)); pr.line(to: NSPoint(x: 8.4, y: 5.9)); pr.line(to: NSPoint(x: 6.6, y: 4.4))
        pr.lineWidth = lw * 0.9; pr.lineCapStyle = .round; pr.lineJoinStyle = .round; pr.stroke()
        // 복원 배지: 앞 창 오른쪽 아래를 지우고 그 자리에 반시계 화살표
        let c = NSPoint(x: 18.4, y: 4.4), r: CGFloat = 3.1
        ctx.saveGState(); ctx.setBlendMode(.clear)
        NSBezierPath(ovalIn: NSRect(x: c.x - r - 1.6, y: c.y - r - 1.6, width: (r + 1.6) * 2, height: (r + 1.6) * 2)).fill()
        ctx.restoreGState()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: r, startAngle: 115, endAngle: 375, clockwise: false)
        arc.lineWidth = lw; arc.lineCapStyle = .round; arc.stroke()
        let e: CGFloat = 395 * .pi / 180
        let p = NSPoint(x: c.x + r * cos(e), y: c.y + r * sin(e))
        let d = NSPoint(x: -sin(e), y: cos(e)), n = NSPoint(x: cos(e), y: sin(e)), L: CGFloat = 3.0
        let head = NSBezierPath()
        head.move(to: NSPoint(x: p.x + d.x * L * 0.75, y: p.y + d.y * L * 0.75))
        head.line(to: NSPoint(x: p.x - d.x * L * 0.3 + n.x * L * 0.6, y: p.y - d.y * L * 0.3 + n.y * L * 0.6))
        head.line(to: NSPoint(x: p.x - d.x * L * 0.3 - n.x * L * 0.6, y: p.y - d.y * L * 0.3 - n.y * L * 0.6))
        head.close(); head.fill()
        return true
    }
    img.isTemplate = true
    return img
}
