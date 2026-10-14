import OpenGL

// Match media_kit_video 2.0.1's macOS pixel format requirements.
let attributes: [CGLPixelFormatAttribute] = [
    kCGLPFAOpenGLProfile,
    CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
    kCGLPFAAccelerated,
    kCGLPFADoubleBuffer,
    kCGLPFAColorSize, CGLPixelFormatAttribute(rawValue: 64),
    kCGLPFAColorFloat,
    kCGLPFABackingStore,
    kCGLPFAAllowOfflineRenderers,
    kCGLPFASupportsAutomaticGraphicsSwitching,
    CGLPixelFormatAttribute(rawValue: 0),
]
var format: CGLPixelFormatObj?
var count: GLint = 0
let formatError = CGLChoosePixelFormat(attributes, &format, &count)
var context: CGLContextObj?
var available = false
if formatError == kCGLNoError, let format = format {
    let contextError = CGLCreateContext(format, nil, &context)
    available = contextError == kCGLNoError && context != nil
    if let context = context { CGLDestroyContext(context) }
    CGLDestroyPixelFormat(format)
}
print("available=\(available)")
print("format_count=\(count)")
