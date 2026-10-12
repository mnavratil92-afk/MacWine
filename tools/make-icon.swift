// Vykresli ikonu MacWine (1024x1024 PNG) a logo bez pozadi - vlastni kresba, bez cizich obrazku.
// Pouziti: swift make-icon.swift <ikona.png> [logo.png]
//   logo = jen sklenka s jablkem, pruhledne pozadi, sklenka s tmavym okrajem (aby nesplyvala se svetlym panelem)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let logoOut: String? = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

func draw(_ ctx: CGContext, background: Bool) {
// Podklad: zaobleny ctverec ve stylu macOS s fialovo-vinovym prechodem
if background {
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(bg)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bg)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.42, green: 0.10, blue: 0.30, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.16, green: 0.05, blue: 0.22, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size - inset), end: CGPoint(x: 0, y: inset), options: [])
} else { ctx.saveGState() }

// Sklenka s jablkem (vlastni kresba; jablko zamerne neni nakousnute - jine nez logo Apple)
let cx = size / 2
let white = NSColor(calibratedWhite: 1, alpha: 0.95).cgColor
let rgb = CGColorSpaceCreateDeviceRGB()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: a).cgColor }

let bowlTop: CGFloat = 770, bowlBottom: CGFloat = 400, bowlHalf: CGFloat = 215
let bowl = CGMutablePath()
bowl.move(to: CGPoint(x: cx - bowlHalf, y: bowlTop))
bowl.addLine(to: CGPoint(x: cx + bowlHalf, y: bowlTop))
bowl.addCurve(to: CGPoint(x: cx, y: bowlBottom), control1: CGPoint(x: cx + 235, y: 560), control2: CGPoint(x: cx + 150, y: bowlBottom + 5))
bowl.addCurve(to: CGPoint(x: cx - bowlHalf, y: bowlTop), control1: CGPoint(x: cx - 150, y: bowlBottom + 5), control2: CGPoint(x: cx - 235, y: 560))
bowl.closeSubpath()

// Jablko: stred, polomer, obrys ze dvou zrcadlovych polovin
let ax = cx, ay: CGFloat = 575, ar: CGFloat = 135
func ap(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ax + x * ar, y: ay + y * ar) }
let apple = CGMutablePath()
apple.move(to: ap(0, 0.62))
apple.addCurve(to: ap(0.98, 0.30), control1: ap(0.30, 0.92), control2: ap(0.92, 0.88))
apple.addCurve(to: ap(0.42, -0.98), control1: ap(1.06, -0.25), control2: ap(0.82, -0.92))
apple.addCurve(to: ap(0, -0.99), control1: ap(0.26, -1.02), control2: ap(0.12, -1.0))
apple.addCurve(to: ap(-0.42, -0.98), control1: ap(-0.12, -1.0), control2: ap(-0.26, -1.02))
apple.addCurve(to: ap(-0.98, 0.30), control1: ap(-0.82, -0.92), control2: ap(-1.06, -0.25))
apple.addCurve(to: ap(0, 0.62), control1: ap(-0.92, 0.88), control2: ap(-0.30, 0.92))
apple.closeSubpath()

// Jemne zabarveni skla
ctx.saveGState()
ctx.addPath(bowl); ctx.clip()
ctx.setFillColor(background ? NSColor(calibratedWhite: 1, alpha: 0.07).cgColor : color(0.42, 0.10, 0.30, 0.10))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.restoreGState()

// Bez pozadi: tmavy okraj kolem cele sklenky (kalich, stopka, podstavec)
let stemRect = CGRect(x: cx - 14, y: 268, width: 28, height: 140)
let base = CGPath(roundedRect: CGRect(x: cx - 130, y: 246, width: 260, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil)
if !background {
  let edge = color(0.24, 0.07, 0.22)
  ctx.saveGState()
  ctx.setStrokeColor(edge); ctx.setLineJoin(.round); ctx.setLineWidth(24 + 22)
  ctx.addPath(bowl); ctx.strokePath()
  ctx.setLineWidth(22)
  ctx.addPath(CGPath(roundedRect: stemRect, cornerWidth: 0, cornerHeight: 0, transform: nil)); ctx.strokePath()
  ctx.addPath(base); ctx.strokePath()
  ctx.restoreGState()
}

// Stopka a listek jablka
ctx.saveGState()
ctx.setStrokeColor(color(0.36, 0.22, 0.12)); ctx.setLineWidth(18); ctx.setLineCap(.round)
ctx.move(to: ap(0, 0.55)); ctx.addCurve(to: ap(0.10, 1.05), control1: ap(0.02, 0.80), control2: ap(0.04, 0.95)); ctx.strokePath()
let leaf = CGMutablePath()
leaf.move(to: ap(0.10, 0.88))
leaf.addCurve(to: ap(0.70, 1.12), control1: ap(0.25, 1.18), control2: ap(0.55, 1.22))
leaf.addCurve(to: ap(0.10, 0.88), control1: ap(0.55, 0.88), control2: ap(0.30, 0.80))
ctx.addPath(leaf); ctx.setFillColor(color(0.20, 0.62, 0.28)); ctx.fillPath()
ctx.restoreGState()

// Jablko s prechodem (zelene) a odleskem
ctx.saveGState()
ctx.addPath(apple); ctx.clip()
let ag = CGGradient(colorsSpace: rgb, colors: [color(0.70, 0.90, 0.32), color(0.30, 0.66, 0.18)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(ag, startCenter: ap(-0.35, 0.35), startRadius: 0, endCenter: ap(0, 0), endRadius: ar * 1.2, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let hl = CGGradient(colorsSpace: rgb, colors: [NSColor(calibratedWhite: 1, alpha: 0.45).cgColor, NSColor(calibratedWhite: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(hl, startCenter: ap(-0.45, 0.30), startRadius: 0, endCenter: ap(-0.45, 0.30), endRadius: ar * 0.45, options: [])
ctx.restoreGState()

// Obrys kalichu, odlesk skla
ctx.setStrokeColor(white); ctx.setLineWidth(24); ctx.setLineJoin(.round)
ctx.addPath(bowl); ctx.strokePath()
ctx.saveGState()
ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.45).cgColor); ctx.setLineWidth(14); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: cx - 175, y: 735)); ctx.addCurve(to: CGPoint(x: cx - 120, y: 500), control1: CGPoint(x: cx - 190, y: 640), control2: CGPoint(x: cx - 165, y: 550))
ctx.strokePath()
ctx.restoreGState()

// Stopka a podstavec sklenky
ctx.setFillColor(white)
ctx.fill(stemRect)
ctx.addPath(base); ctx.fillPath()
ctx.restoreGState()
}

func render(_ path: String, crop: CGRect, background: Bool) {
  let image = NSImage(size: crop.size)
  image.lockFocus()
  let ctx = NSGraphicsContext.current!.cgContext
  ctx.translateBy(x: -crop.minX, y: -crop.minY)
  draw(ctx, background: background)
  image.unlockFocus()
  let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
  print(path)
}
render(out, crop: CGRect(x: 0, y: 0, width: size, height: size), background: true)
// Logo: vyrez kolem sklenky vcetne okraje
if let logoOut { render(logoOut, crop: CGRect(x: 262, y: 218, width: 500, height: 588), background: false) }
