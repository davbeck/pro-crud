import Foundation

public struct EffectiveRendering: Codable, Sendable {
	public var schemaVersion: Int
	public var coordinateSystem: String
	public var layerOrder: String
	public var presentations: [Presentation]

	public init(presentations: [Presentation]) {
		schemaVersion = 1
		coordinateSystem = "bottom-left"
		layerOrder = "back-to-front"
		self.presentations = presentations
	}

	public struct Presentation: Codable, Sendable {
		public var name: String
		public var uuid: String
		public var arrangement: Arrangement?
		public var slides: [Slide]
	}

	public struct Arrangement: Codable, Sendable {
		public var name: String
		public var uuid: String
		public var path: String
	}

	public struct CueGroup: Codable, Sendable {
		public var name: String
		public var uuid: String
		public var path: String
		public var arrangementOccurrenceIndex: Int?
	}

	public struct Slide: Codable, Sendable {
		public var index: Int
		public var name: String
		public var uuid: String
		public var cueGroup: CueGroup?
		public var canvasSize: Size
		public var background: String?
		public var layers: [Layer]
	}

	public struct Layer: Codable, Sendable {
		public var index: Int
		public var sourceIndex: Int
		public var kind: String
		public var componentPath: String
		public var uuid: String
		public var name: String?
		public var actionType: String?
		public var bounds: Rect
		public var opacity: Double?
		public var rotation: Double?
		/// Schema-v1 compatibility name for raw nonzero `Slide.Element.info`.
		/// Layer ordering comes from reverse stored element order, not this value.
		public var zOrder: Int?
		public var alternateTextOutline: Bool?
		public var fill: Fill?
		public var lineFillMask: LineFillMask?
		public var stroke: Stroke?
		public var shadow: Shadow?
		public var media: Media?
		public var text: Text?
	}

	public struct Text: Codable, Sendable {
		public var plainText: String
		public var effectiveRTF: String
		public var scaleBehavior: String?
		public var fontScale: Double?
		public var verticalAlignment: String?
		public var transform: String?
		public var capitalization: String?
		public var margins: Insets?
		public var contentBounds: Rect
		public var drawBounds: Rect?
		public var layoutBounds: Rect
		public var lineCount: Int?
		public var runs: [TextRun]
	}

	public struct TextRun: Codable, Sendable {
		public var location: Int
		public var length: Int
		public var text: String
		public var font: Font?
		public var foregroundColor: Color?
		public var backgroundColor: Color?
		public var underlineStyle: Int?
		public var strikethroughStyle: Int?
		public var strokeWidth: Double?
		public var strokeColor: Color?
		public var kern: Double?
		public var baselineOffset: Double?
		public var paragraph: Paragraph?
		public var shadow: Shadow?
	}

	public struct Font: Codable, Sendable {
		public var postscriptName: String
		public var familyName: String?
		public var pointSize: Double
		public var bold: Bool?
		public var italic: Bool?
	}

	public struct Paragraph: Codable, Sendable {
		public var alignment: String?
		public var lineSpacing: Double?
		public var paragraphSpacing: Double?
		public var paragraphSpacingBefore: Double?
		public var firstLineHeadIndent: Double?
		public var headIndent: Double?
		public var tailIndent: Double?
		public var minimumLineHeight: Double?
		public var maximumLineHeight: Double?
		public var lineHeightMultiple: Double?
	}

	public struct Fill: Codable, Sendable {
		public var kind: String
		public var color: Color?
		public var media: Media?
	}

	public struct Stroke: Codable, Sendable {
		public var width: Double
		public var color: Color
		public var pattern: [Double]?
	}

	public struct LineFillMask: Codable, Sendable {
		public var style: String?
		public var heightOffset: Double?
		public var verticalOffset: Double?
		public var widthOffset: Double?
		public var horizontalOffset: Double?
	}

	public struct Shadow: Codable, Sendable {
		public var color: Color?
		public var offset: Size?
		public var blurRadius: Double?
	}

	public struct Media: Codable, Sendable {
		public var source: String?
		public var resolvedSource: String?
		public var type: String?
	}

	public struct Color: Codable, Sendable {
		public var red: Double?
		public var green: Double?
		public var blue: Double?
		public var alpha: Double?
	}

	public struct Rect: Codable, Sendable {
		public var x: Double?
		public var y: Double?
		public var width: Double
		public var height: Double
	}

	public struct Size: Codable, Sendable {
		public var width: Double
		public var height: Double
	}

	public struct Insets: Codable, Sendable {
		public var top: Double?
		public var left: Double?
		public var bottom: Double?
		public var right: Double?
	}
}
