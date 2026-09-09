// Run on macOS with the same CoreVideo buffers used on iOS:
// swiftc ios/Runner/ReplayFrameCopy.swift test/native/replay_frame_copy_test.swift -o /tmp/replay-frame-copy-test
// /tmp/replay-frame-copy-test
import Foundation
import CoreVideo

final class TestPixelBuffer {
  let memory: UnsafeMutableRawPointer
  let byteCount: Int
  let allocationSize: Int
  var buffer: CVPixelBuffer!

  init(width: Int, height: Int, stride: Int? = nil, extraRows: Int = 1) {
    let rowBytes = stride ?? width * 4
    byteCount = rowBytes * height
    allocationSize = rowBytes * (height + extraRows)
    memory = .allocate(byteCount: allocationSize, alignment: 64)
    memory.initializeMemory(as: UInt8.self, repeating: 0xA5, count: allocationSize)
    let result = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA, memory, rowBytes, nil, nil, nil, &buffer)
    precondition(result == kCVReturnSuccess)
  }

  var unchanged: Bool {
    UnsafeRawBufferPointer(start: memory, count: allocationSize).allSatisfy { $0 == 0xA5 }
  }

  var guardIntact: Bool {
    UnsafeRawBufferPointer(start: memory + byteCount,
      count: allocationSize - byteCount).allSatisfy { $0 == 0xA5 }
  }

  deinit {
    buffer = nil
    memory.deallocate()
  }
}

@main
enum ReplayFrameCopyTests {
  static func main() {
    // The old replay pool remains landscape while iOS delivers portrait.
    let landscape = TestPixelBuffer(width: 1280, height: 720, extraRows: 561)
    let portraitData = Data(repeating: 0x11, count: 720 * 1280 * 4)
    precondition(!ReplayFrameCopy.copyBGRA(portraitData,
      width: 720, height: 1280, bytesPerRow: 720 * 4, to: landscape.buffer))
    precondition(landscape.unchanged && landscape.guardIntact)
    print("PASS: landscape pool rejects portrait frame without memory writes")

    let portrait = TestPixelBuffer(width: 720, height: 1280)
    precondition(ReplayFrameCopy.copyBGRA(portraitData,
      width: 720, height: 1280, bytesPerRow: 720 * 4, to: portrait.buffer))
    precondition(UnsafeRawBufferPointer(start: portrait.memory,
      count: portrait.byteCount).allSatisfy { $0 == 0x11 })
    precondition(portrait.guardIntact)
    print("PASS: fresh portrait pool receives the complete frame")

    let freshPortrait = TestPixelBuffer(width: 720, height: 1280)
    precondition(!ReplayFrameCopy.copyBGRA(portraitData,
      width: 1280, height: 720, bytesPerRow: 1280 * 4, to: freshPortrait.buffer))
    precondition(freshPortrait.unchanged)
    print("PASS: portrait pool rejects landscape frame")

    let small = TestPixelBuffer(width: 2, height: 2, stride: 16)
    precondition(!ReplayFrameCopy.copyBGRA(Data(count: 15),
      width: 2, height: 2, bytesPerRow: 8, to: small.buffer))
    precondition(small.unchanged)
    print("PASS: truncated source is rejected before copying")

    precondition(!ReplayFrameCopy.copyBGRA(Data(count: 32),
      width: 2, height: 2, bytesPerRow: -1, to: small.buffer))
    precondition(!ReplayFrameCopy.copyBGRA(Data(count: 32),
      width: 2, height: 2, bytesPerRow: 4, to: small.buffer))
    precondition(small.unchanged)
    print("PASS: invalid source strides are rejected")

    // Different row padding, including an unpadded final source row.
    var padded = Data(repeating: 0xEE, count: 20)
    padded.replaceSubrange(0..<8, with: repeatElement(UInt8(0x11), count: 8))
    padded.replaceSubrange(12..<20, with: repeatElement(UInt8(0x22), count: 8))
    precondition(ReplayFrameCopy.copyBGRA(padded,
      width: 2, height: 2, bytesPerRow: 12, to: small.buffer))
    let output = UnsafeRawBufferPointer(start: small.memory, count: small.byteCount)
    precondition(output[0..<8].allSatisfy { $0 == 0x11 })
    precondition(output[16..<24].allSatisfy { $0 == 0x22 })
    precondition(output[8..<16].allSatisfy { $0 == 0xA5 })
    precondition(output[24..<32].allSatisfy { $0 == 0xA5 })
    precondition(small.guardIntact)
    print("PASS: padded rows copied correctly without writing destination padding")

    precondition(!ReplayFrameCopy.copyBGRA(Data(), width: 2, height: 2,
      bytesPerRow: Int.max, to: small.buffer))
    print("PASS: overflowing source size is rejected")
  }
}
