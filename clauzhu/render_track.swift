// 畫「Clau猪跑道」的所有幀：用上一版（Clawd-TouchBar-Pet）那套 51x36 帶陰影的螃蟹，
// 只用側身走路的 16 幀（第 4–19 幀，手不張開），加上下搖晃。輸出到 frames/track/。
// 用法：swiftc -O render_track.swift native/Sources/CrabFrames.swift -o build/render_track && build/render_track
import AppKit
import CoreImage

let OUT = "/Users/a0000/Claude/touchbar/frames/track/"
let TW = 600, TH = 56                      // 跑道 600x56 像素 = Touch Bar 上 300x28 點
let CH: CGFloat = 44                       // 螃蟹畫 44 像素高（22 點，和上一版一樣）
let STEP = 6                               // 每幀走 6 像素（3 點）
let WALK = Array(4...19)                   // 側身走路幀（0–3 是正面張手，不用）
let BOB: [CGFloat] = [0, 2, 4, 2]          // 走路時上下搖（像素）
let IDLE_BOB: [CGFloat] = [0, 2, 4, 2]     // 空閒時慢慢上下搖

/// 側身幀裡遠側那隻眼睛貼著身體邊緣（黑眼睛就是最外一列），在黑色 Touch Bar 上會和背景連成一片，
/// 看起來像缺了一塊。把貼邊的眼睛往裡挪 3 像素，外側補上身體的橙色。
func fixEdgeEye(_ img: CGImage) -> CGImage {
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    func at(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
    func opaque(_ x: Int, _ y: Int) -> Bool { px[at(x, y) + 3] > 128 }
    func dark(_ x: Int, _ y: Int) -> Bool { let i = at(x, y); return px[i+3] > 128 && px[i] < 70 && px[i+1] < 70 }
    let shift = 3
    for y in 0..<h {
        guard let right = (0..<w).last(where: { opaque($0, y) }) else { continue }
        // 從右往左找貼邊（距邊緣 ≤1）的一段黑像素
        var e = right
        if !dark(e, y) && e > 0 && dark(e - 1, y) { e -= 1 }
        guard dark(e, y) else { continue }
        var s = e
        while s > 0 && dark(s - 1, y) { s -= 1 }
        guard s - shift > 0 else { continue }
        let fill = Array(px[at(s - 1, y)..<at(s - 1, y) + 4])          // 眼睛左邊的身體色
        let eye = Array(px[at(s, y)..<at(e, y) + 4])
        for x in s...right { px.replaceSubrange(at(x, y)..<at(x, y) + 4, with: fill) }
        px.replaceSubrange(at(s - shift, y)..<at(s - shift, y) + eye.count, with: eye)
    }
    return ctx.makeImage()!
}

let frames: [CGImage] = clawdCrabFramePNGs.compactMap {
    guard let d = Data(base64Encoded: $0), let r = NSBitmapImageRep(data: d) else { return nil }
    return r.cgImage.map(fixEdgeEye)
}
let CW = (CH * CGFloat(frames[0].width) / CGFloat(frames[0].height)).rounded()
let positions = Array(stride(from: 0, through: TW - Int(CW), by: STEP))

func gray(_ img: CGImage) -> CGImage {
    let f = CIFilter(name: "CIColorControls")!
    f.setValue(CIImage(cgImage: img), forKey: kCIInputImageKey)
    f.setValue(0.0, forKey: kCIInputSaturationKey)
    f.setValue(-0.15, forKey: kCIInputBrightnessKey)
    let o = f.outputImage!
    return CIContext().createCGImage(o, from: o.extent)!
}
let sleepImg = gray(frames[4])

func render(_ name: String, _ img: CGImage, x: Int, y: CGFloat, flip: Bool, z: Bool = false) {
    let ctx = CGContext(data: nil, width: TW, height: TH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.saveGState()
    if flip { ctx.translateBy(x: CGFloat(x) * 2 + CW, y: 0); ctx.scaleBy(x: -1, y: 1) }
    ctx.draw(img, in: CGRect(x: CGFloat(x), y: y, width: CW, height: CH))
    ctx.restoreGState()
    if z {   // 睡覺的 z
        let g = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
        ("z" as NSString).draw(at: NSPoint(x: CGFloat(x) + CW - 4, y: 30), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0.82, green: 0.84, blue: 0.92, alpha: 1)])
        NSGraphicsContext.restoreGraphicsState()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: OUT + name + ".png"))
}

try? FileManager.default.removeItem(atPath: OUT)
try! FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)
for (k, x) in positions.enumerated() {
    // 走路：幀和位置綁定，所以同一個位置向右、向左各一張
    let f = frames[WALK[k % WALK.count]], b = BOB[k % BOB.count]
    render("walkR_\(x)", f, x: x, y: b, flip: false)
    render("walkL_\(x)", f, x: x, y: b, flip: true)
    for (i, ib) in IDLE_BOB.enumerated() {
        render("idleR_\(x)_\(i)", frames[4], x: x, y: ib, flip: false)
        render("idleL_\(x)_\(i)", frames[4], x: x, y: ib, flip: true)
    }
    render("sleep_\(x)", sleepImg, x: x, y: -8, flip: false, z: true)
}
print("positions \(positions.count) (0...\(positions.last!)), crab \(CW)x\(CH)")
