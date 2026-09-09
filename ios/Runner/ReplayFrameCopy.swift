import Foundation
import CoreVideo

/// Bounds-checked copy into the fixed-size buffer owned by a replay segment.
enum ReplayFrameCopy {
  static func copyBGRA(
    _ bytes: Data, width: Int, height: Int, bytesPerRow: Int, to buffer: CVPixelBuffer
  ) -> Bool {
    guard width > 0, height > 0, width <= Int.max / 4,
          CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
          CVPixelBufferGetWidth(buffer) == width,
          CVPixelBufferGetHeight(buffer) == height
    else { return false }
    let rowBytes = width * 4
    let dstStride = CVPixelBufferGetBytesPerRow(buffer)
    guard bytesPerRow >= rowBytes, dstStride >= rowBytes,
          bytesPerRow <= Int.max / height,
          bytes.count >= (height - 1) * bytesPerRow + rowBytes
    else { return false }

    guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let dst = CVPixelBufferGetBaseAddress(buffer) else { return false }
    return bytes.withUnsafeBytes { src in
      guard let base = src.baseAddress else { return false }
      if bytesPerRow == rowBytes && dstStride == rowBytes {
        memcpy(dst, base, height * rowBytes)
      } else {
        for row in 0..<height {
          memcpy(dst + row * dstStride, base + row * bytesPerRow, rowBytes)
        }
      }
      return true
    }
  }
}
