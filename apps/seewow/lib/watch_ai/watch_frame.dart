import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Native capture may allocate a full-resolution frame. Retain only one small
/// encoded image for the current request and dispose decoder resources eagerly.
Future<Uint8List?> reduceWatchFrame(Uint8List? bytes) async {
  if (bytes == null) return null;
  if (bytes.length > 8 * 1024 * 1024)
    throw const FormatException('原始截图过大，本次请使用台词分析');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 3840 * 2160) {
      throw const FormatException('当前视频超过 4K，请使用台词分析以减少内存占用');
    }
    final scale = math.min(
      1.0,
      640 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > 512 * 1024) {
      throw const FormatException('压缩后截图仍过大，本次请使用台词分析');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
