import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    let card = NSBezierPath(roundedRect: rect.insetBy(dx: 80, dy: 80), xRadius: 190, yRadius: 190)
    NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).setFill()
    card.fill()

    let page = NSBezierPath(roundedRect: NSRect(x: 250, y: 230, width: 524, height: 560), xRadius: 48, yRadius: 48)
    NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).setFill()
    page.fill()
    NSColor(srgbRed: 1, green: 0.42, blue: 0.24, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 250, y: 680, width: 524, height: 110)).fill()

    func ring(_ color: NSColor, x: CGFloat) {
        color.setStroke()
        let path = NSBezierPath(ovalIn: NSRect(x: x, y: 300, width: 150, height: 150))
        path.lineWidth = 16
        path.stroke()
        color.setFill()
        NSBezierPath(rect: NSRect(x: x + 67, y: 330, width: 16, height: 90)).fill()
        NSBezierPath(rect: NSRect(x: x + 30, y: 367, width: 90, height: 16)).fill()
    }
    ring(NSColor(srgbRed: 0.55, green: 0.86, blue: 0.67, alpha: 1), x: 320)
    ring(NSColor(srgbRed: 0.78, green: 0.64, blue: 0.95, alpha: 1), x: 540)
    return true
}

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法生成图标\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
