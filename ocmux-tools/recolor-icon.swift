import Foundation
import CoreImage
import AppKit

// usage: recolor <in.png> <out.png> <degrees> [saturation]
let args = CommandLine.arguments
guard args.count >= 4,
      let deg = Double(args[3]) else {
    FileHandle.standardError.write("usage: recolor <in> <out> <deg> [sat]\n".data(using: .utf8)!)
    exit(2)
}
let sat = args.count > 4 ? Double(args[4]) ?? 1.0 : 1.0
guard let src = CIImage(contentsOf: URL(fileURLWithPath: args[1])) else { exit(3) }

var img = src
if let hue = CIFilter(name: "CIHueAdjust") {
    hue.setValue(img, forKey: kCIInputImageKey)
    hue.setValue(Float(deg * .pi / 180.0), forKey: kCIInputAngleKey)
    img = hue.outputImage ?? img
}
if sat != 1.0, let ctl = CIFilter(name: "CIColorControls") {
    ctl.setValue(img, forKey: kCIInputImageKey)
    ctl.setValue(Float(sat), forKey: kCIInputSaturationKey)
    img = ctl.outputImage ?? img
}

let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
guard let cg = ctx.createCGImage(img, from: src.extent) else { exit(4) }
let rep = NSBitmapImageRep(cgImage: cg)
rep.size = NSSize(width: src.extent.width, height: src.extent.height)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(5) }
try data.write(to: URL(fileURLWithPath: args[2]))
