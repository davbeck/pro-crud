#!/usr/bin/env swift

import AppKit
import Foundation

/// Generates a frame-identification video for testing video frame selection.
///
/// The large counter is the elapsed whole second (00...59). One more dot fills
/// from left to right for every frame, making the dot count the one-based frame
/// index within that second (1...30).
let width = 854
let height = 480
let frameRate = 30
let duration = 60
let dotCount = 30

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root.appending(path: "Examples/Video Frame Test")
let output = outputDirectory.appending(path: "frame-test-30fps-480p.mp4")
let poster = outputDirectory.appending(path: "frame-test-30fps-480p-poster.jpg")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let encoder = Process()
encoder.executableURL = URL(fileURLWithPath: "/usr/bin/env")
encoder.arguments = [
	"ffmpeg",
	"-y",
	"-f", "rawvideo",
	"-pixel_format", "rgba",
	"-video_size", "\(width)x\(height)",
	"-framerate", "\(frameRate)",
	"-i", "-",
	"-i", poster.path,
	"-map", "0:v:0",
	"-map", "1:v:0",
	"-c:v:0", "libx264",
	"-pix_fmt:v:0", "yuv420p",
	"-profile:v:0", "high",
	"-crf:v:0", "18",
	"-g:v:0", "\(frameRate)",
	"-bf:v:0", "0",
	"-x264-params:v:0", "keyint=\(frameRate):min-keyint=\(frameRate):scenecut=0:colorprim=bt709:transfer=bt709:colormatrix=bt709",
	"-color_range:v:0", "tv",
	"-colorspace:v:0", "bt709",
	"-color_primaries:v:0", "bt709",
	"-color_trc:v:0", "bt709",
	"-c:v:1", "mjpeg",
	"-disposition:v:1", "attached_pic",
	"-movflags", "+faststart+write_colr",
	"-metadata", "title=30 fps frame test",
	"-metadata", "comment=Second counter plus one-based frame progress dots",
	output.path,
]
let encoderInput = Pipe()
encoder.standardInput = encoderInput
encoder.standardOutput = FileHandle.standardOutput
encoder.standardError = FileHandle.standardError

let background = CGColor(red: 16 / 255, green: 20 / 255, blue: 28 / 255, alpha: 1)
let inactiveDot = CGColor(red: 94 / 255, green: 104 / 255, blue: 120 / 255, alpha: 1)
let activeDot = CGColor(red: 64 / 255, green: 217 / 255, blue: 1, alpha: 1)
let counterColor = NSColor.white
let counterFont = NSFont.monospacedDigitSystemFont(ofSize: 224, weight: .bold)
let counterAttributes: [NSAttributedString.Key: Any] = [
	.font: counterFont,
	.foregroundColor: counterColor,
]
let dotRadius: CGFloat = 8
let dotSpacing: CGFloat = 27
let dotFirstCenter = (CGFloat(width) - CGFloat(dotCount - 1) * dotSpacing) / 2
let dotCenterY: CGFloat = 34

func drawFrame(second: Int?, completedDots: Int, into pixels: inout Data) throws {
	try autoreleasepool {
		try pixels.withUnsafeMutableBytes { buffer in
			guard let baseAddress = buffer.baseAddress,
			      let context = CGContext(
			      	data: baseAddress,
			      	width: width,
			      	height: height,
			      	bitsPerComponent: 8,
			      	bytesPerRow: width * 4,
			      	space: CGColorSpaceCreateDeviceRGB(),
			      	bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,
			      )
			else {
				throw CocoaError(.coderInvalidValue)
			}

			context.setFillColor(background)
			context.fill(CGRect(x: 0, y: 0, width: width, height: height))

			if let second {
				let counter = NSAttributedString(string: String(format: "%02d", second), attributes: counterAttributes)
				let counterSize = counter.size()
				let counterFrame = CGRect(
					x: (CGFloat(width) - counterSize.width) / 2,
					y: 88 + (CGFloat(height - 88) - counterSize.height) / 2,
					width: counterSize.width,
					height: counterSize.height,
				)
				NSGraphicsContext.saveGraphicsState()
				NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
				counter.draw(in: counterFrame)
				NSGraphicsContext.restoreGraphicsState()
			}

			for dot in 0 ..< dotCount {
				let centerX = dotFirstCenter + CGFloat(dot) * dotSpacing
				let circle = CGRect(
					x: centerX - dotRadius,
					y: dotCenterY - dotRadius,
					width: dotRadius * 2,
					height: dotRadius * 2,
				)
				context.setStrokeColor(inactiveDot)
				context.setLineWidth(2)
				context.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
				if dot < completedDots {
					context.setFillColor(activeDot)
					context.fillEllipse(in: circle)
				}
			}
		}
	}
}

var posterPixels = Data(count: width * height * 4)
try drawFrame(second: nil, completedDots: 0, into: &posterPixels)
guard let posterProvider = CGDataProvider(data: posterPixels as CFData) else {
	throw CocoaError(.coderInvalidValue)
}
guard let posterImage = CGImage(
	width: width,
	height: height,
	bitsPerComponent: 8,
	bitsPerPixel: 32,
	bytesPerRow: width * 4,
	space: CGColorSpaceCreateDeviceRGB(),
	bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
	provider: posterProvider,
	decode: nil,
	shouldInterpolate: false,
	intent: .defaultIntent,
), let posterData = NSBitmapImageRep(cgImage: posterImage).representation(
	using: .jpeg,
	properties: [.compressionFactor: 0.9],
) else {
	throw CocoaError(.coderInvalidValue)
}

try posterData.write(to: poster)

try encoder.run()

var pixels = Data(count: width * height * 4)
for frame in 0 ..< (frameRate * duration) {
	try drawFrame(
		second: frame / frameRate,
		completedDots: frame % frameRate + 1,
		into: &pixels,
	)
	try pixels.withUnsafeBytes { buffer in
		try encoderInput.fileHandleForWriting.write(contentsOf: Data(buffer))
	}
}

try encoderInput.fileHandleForWriting.close()
encoder.waitUntilExit()
guard encoder.terminationStatus == 0 else {
	throw CocoaError(.coderInvalidValue)
}
