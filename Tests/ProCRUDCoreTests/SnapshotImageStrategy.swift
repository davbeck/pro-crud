import AppKit
import CoreImage
import SnapshotTesting

extension Snapshotting where Value == NSImage, Format == NSImage {
	/// SnapshotTesting's Metal reduction path crashes in Core Image on macOS 27.
	/// This preserves its comparison semantics while reducing Delta E values on the CPU.
	static func proCRUDImage(
		precision: Float = 1,
		perceptualPrecision: Float = 1,
	) -> Snapshotting {
		Snapshotting(
			pathExtension: "png",
			diffing: .diff(
				toData: pngData,
				fromData: { NSImage(data: $0) ?? NSImage(size: .zero) },
				diffV2: { reference, snapshot in
					guard let message = compare(
						reference,
						snapshot,
						precision: precision,
						perceptualPrecision: perceptualPrecision,
					) else { return nil }
					return (
						message,
						[
							.data(pngData(reference), name: "reference.png"),
							.data(pngData(snapshot), name: "failure.png"),
						],
					)
				},
			),
		)
	}
}

private func pngData(_ image: NSImage) -> Data {
	guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
		return Data()
	}
	let representation = NSBitmapImageRep(cgImage: cgImage)
	representation.size = image.size
	return representation.representation(using: .png, properties: [:]) ?? Data()
}

private func compare(
	_ reference: NSImage,
	_ snapshot: NSImage,
	precision: Float,
	perceptualPrecision: Float,
) -> String? {
	guard let referenceImage = reference.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
		return "Reference image could not be loaded."
	}
	guard let snapshotImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
		return "Newly-taken snapshot could not be loaded."
	}
	guard snapshotImage.width != 0, snapshotImage.height != 0 else {
		return "Newly-taken snapshot is empty."
	}
	guard referenceImage.width == snapshotImage.width, referenceImage.height == snapshotImage.height else {
		return "Newly-taken snapshot@\(snapshot.size) does not match reference@\(reference.size)."
	}

	guard
		let referenceBytes = rgbaBytes(for: referenceImage),
		let snapshotBytes = rgbaBytes(for: snapshotImage)
	else {
		return "Snapshot image data could not be loaded."
	}
	guard referenceBytes != snapshotBytes else { return nil }
	guard precision < 1 || perceptualPrecision < 1 else {
		return "Newly-taken snapshot does not match reference."
	}

	if perceptualPrecision < 1 {
		let referenceCIImage = CIImage(cgImage: referenceImage)
		let snapshotCIImage = CIImage(cgImage: snapshotImage)
		let deltaImage = referenceCIImage.applyingFilter(
			"CILabDeltaE",
			parameters: ["inputImage2": snapshotCIImage],
		)
		let context = CIContext(options: [
			.workingColorSpace: NSNull(),
			.outputColorSpace: NSNull(),
			.useSoftwareRenderer: true,
		])
		let width = referenceImage.width
		let height = referenceImage.height
		var deltaValues = [Float](repeating: 0, count: width * height)
		deltaValues.withUnsafeMutableBytes { bytes in
			guard let baseAddress = bytes.baseAddress else { return }
			context.render(
				deltaImage,
				toBitmap: baseAddress,
				rowBytes: width * MemoryLayout<Float>.stride,
				bounds: deltaImage.extent,
				format: .Rf,
				colorSpace: nil,
			)
		}

		let deltaThreshold = (1 - perceptualPrecision) * 100
		var failingPixelCount = 0
		var maximumDeltaE: Float = 0
		for deltaE in deltaValues where deltaE > deltaThreshold {
			failingPixelCount += 1
			maximumDeltaE = max(maximumDeltaE, deltaE)
		}
		let actualPixelPrecision = 1 - Float(failingPixelCount) / Float(width * height)
		guard actualPixelPrecision < precision else { return nil }
		let minimumPerceptualPrecision = 1 - min(maximumDeltaE / 100, 1)
		return """
		The percentage of pixels that match \(actualPixelPrecision) is less than required \(precision)
		The lowest perceptual color precision \(minimumPerceptualPrecision) is less than required \(perceptualPrecision)
		"""
	}

	let differentByteCount = zip(referenceBytes, snapshotBytes).count { $0 != $1 }
	let actualPrecision = 1 - Float(differentByteCount) / Float(referenceBytes.count)
	return actualPrecision < precision
		? "Actual image precision \(actualPrecision) is less than required \(precision)"
		: nil
}

private func rgbaBytes(for image: CGImage) -> [UInt8]? {
	let bytesPerRow = image.width * 4
	var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
	guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
	guard let context = CGContext(
		data: &bytes,
		width: image.width,
		height: image.height,
		bitsPerComponent: 8,
		bytesPerRow: bytesPerRow,
		space: colorSpace,
		bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
	) else { return nil }
	context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
	return bytes
}
