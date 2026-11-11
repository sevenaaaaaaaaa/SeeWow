import AppKit

// Vector geometry matching the app's monochrome play mark.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Contents.json"))) as! [String: Any]
for entry in manifest["images"] as! [[String: String]] {
  guard let file = entry["filename"], let size = entry["size"], let scale = entry["scale"],
        let points = Double(size.components(separatedBy: "x")[0]),
        let multiplier = Double(scale.replacingOccurrences(of: "x", with: "")) else { continue }
  let pixels = Int((points * multiplier).rounded())
  let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
  NSColor(srgbRed: 9/255, green: 10/255, blue: 11/255, alpha: 1).setFill()
  NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
  NSColor(srgbRed: 229/255, green: 234/255, blue: 242/255, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 194, y: 194, width: 636, height: 636), xRadius: 178, yRadius: 178).fill()
  NSColor(srgbRed: 9/255, green: 10/255, blue: 11/255, alpha: 1).setFill()
  let play = NSBezierPath()
  play.move(to: NSPoint(x: 438, y: 354))
  play.line(to: NSPoint(x: 438, y: 670))
  play.line(to: NSPoint(x: 696, y: 512))
  play.close()
  play.fill()
  NSGraphicsContext.restoreGraphicsState()
  let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
  try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(file))
}
