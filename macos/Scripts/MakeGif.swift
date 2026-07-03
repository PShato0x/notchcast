// Assembles PNG frames into a looping animated GIF using ImageIO — no
// external dependencies. Used to build the README demo GIF.
//   makegif <out.gif> <frame1.png> <frame2.png> ...
//   GIF_DELAY=0.15 (seconds per frame, via environment)

import AppKit
import UniformTypeIdentifiers

@main
enum MakeGif {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            fputs("usage: makegif <out.gif> <frame.png>...\n", stderr)
            exit(2)
        }
        let out = URL(fileURLWithPath: args[1])
        let frames = args.dropFirst(2).map { URL(fileURLWithPath: $0) }
        let delay = Double(ProcessInfo.processInfo.environment["GIF_DELAY"] ?? "") ?? 0.15

        guard let dest = CGImageDestinationCreateWithURL(
            out as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { fputs("cannot create \(out.path)\n", stderr); exit(1) }

        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0] // loop forever
        ] as CFDictionary)

        let frameProps = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ] as CFDictionary

        for frame in frames {
            guard
                let src = CGImageSourceCreateWithURL(frame as CFURL, nil),
                let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
            else { fputs("bad frame: \(frame.path)\n", stderr); exit(1) }
            CGImageDestinationAddImage(dest, img, frameProps)
        }

        guard CGImageDestinationFinalize(dest) else { fputs("finalize failed\n", stderr); exit(1) }
        print("wrote \(out.path) (\(frames.count) frames @ \(delay)s)")
    }
}
