/// Defines the available tools in the crop & rotate editor.
enum CropRotateTool {
  /// A tool to rotate the image by 90° steps.
  rotate,

  /// A tool to flip the image horizontally or vertically.
  flip,

  /// A tool to change the aspect ratio of the image.
  aspectRatio,

  /// A tool to reset all transformations to their original state.
  reset,

  /// A tool to straighten/fine-tune rotate the image using a slider (-45° to +45°).
  straighten,
}
