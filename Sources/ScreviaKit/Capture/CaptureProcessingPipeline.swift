import AppKit

nonisolated struct CaptureProcessingPipelineResult {
    let image: NSImage
    let savedImage: ImageStore.SavedImage
}

/// Keeps expensive image processing and encoding off CaptureCoordinator's
/// main actor. This actor also serializes writes so concurrent shortcuts
/// cannot race while choosing a unique destination filename.
actor CaptureProcessingPipeline {
    private let imageProcessor = ImageProcessor()
    private let imageStore = ImageStore()

    func processAndSave(
        image: NSImage,
        styleOptions: CaptureStyleOptions,
        directory: URL,
        format: ImageFormat,
        jpegQuality: Double,
        includeClipboardData: Bool,
        baseName: String? = nil,
        downscaleToPointSize: Bool = false
    ) throws -> CaptureProcessingPipelineResult {
        // Downscaled first, so padding and shadow are drawn at the size
        // that is saved rather than shrunk along with the capture.
        let sized = downscaleToPointSize ? imageProcessor.downscaledToPointSize(image) : image
        let processedImage = imageProcessor.process(sized, options: styleOptions)
        let savedImage = try imageStore.saveAndEncode(
            processedImage,
            directory: directory,
            format: format,
            jpegQuality: jpegQuality,
            includeData: includeClipboardData,
            baseName: baseName
        )
        return CaptureProcessingPipelineResult(
            image: processedImage,
            savedImage: savedImage
        )
    }
}
