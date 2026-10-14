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
        includeClipboardData: Bool
    ) throws -> CaptureProcessingPipelineResult {
        let processedImage = imageProcessor.process(image, options: styleOptions)
        let savedImage = try imageStore.saveAndEncode(
            processedImage,
            directory: directory,
            format: format,
            jpegQuality: jpegQuality,
            includeData: includeClipboardData
        )
        return CaptureProcessingPipelineResult(
            image: processedImage,
            savedImage: savedImage
        )
    }
}
