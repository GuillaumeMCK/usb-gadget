import 'dart:io';

import '/src/gadget/fs.dart';

import 'base.dart';

/// USB Video Class (UVC) frame format.
///
/// Determines how frame data is structured in the configfs directory tree
/// and which streaming format class the kernel expects.
enum UvcFormat {
  /// YUYV (packed YUV) uncompressed format.
  yuyv,

  /// MJPEG compressed format.
  mjpeg,

  /// Framebased format with a custom GUID (e.g., NV12, H.264).
  framebased;

  String get _groupDir {
    return switch (this) {
      .yuyv => 'uncompressed',
      .mjpeg => 'mjpeg',
      .framebased => 'framebased',
    };
  }

  String get _name {
    return switch (this) {
      .yuyv => 'yuyv',
      .mjpeg => 'mjpeg',
      .framebased => 'framebased',
    };
  }
}

/// Frame color matching information for a UVC format.
///
/// Optional per-format color space metadata. If not provided, the UVC
/// specification default values are used.
class UvcColorMatching {
  const UvcColorMatching({
    this.colorPrimaries = 0,
    this.transferCharacteristics = 0,
    this.matrixCoefficients = 0,
  });

  /// Color primaries (ITU-R BT.601, BT.709, etc.)
  final int colorPrimaries;

  /// Transfer characteristics (gamma curve)
  final int transferCharacteristics;

  /// Matrix coefficients (Y'CbCr matrix)
  final int matrixCoefficients;
}

/// A UVC video frame configuration.
///
/// Describes a single width × height resolution with one or more frame rates.
class UvcFrame {
  const UvcFrame({
    required this.width,
    required this.height,
    required this.fps,
    required this.format,
    this.bpp = 0,
    this.guid,
    this.formatName,
    this.colorMatching,
  });

  /// Creates a YUYV frame at the given resolution and frame rates.
  factory UvcFrame.yuyv(int width, int height, List<int> fps) =>
      UvcFrame(width: width, height: height, fps: fps, format: .yuyv);

  /// Creates an MJPEG frame at the given resolution and frame rates.
  factory UvcFrame.mjpeg(int width, int height, List<int> fps) =>
      UvcFrame(width: width, height: height, fps: fps, format: .mjpeg);

  /// Creates an NV12 framebased frame at the given resolution and frame rates.
  factory UvcFrame.nv12(int width, int height, List<int> fps) => UvcFrame(
    width: width,
    height: height,
    fps: fps,
    format: .framebased,
    guid: [
      0x4E, 0x56, 0x31, 0x32, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, //
      0xaa, 0x00, 0x38, 0x9b, 0x71, //
    ],
    formatName: 'nv12',
    bpp: 12,
  );

  /// Creates an H.264 framebased frame at the given resolution and frame rates.
  factory UvcFrame.h264(int width, int height, List<int> fps) => UvcFrame(
    width: width,
    height: height,
    fps: fps,
    format: .framebased,
    guid: [
      0x48, 0x32, 0x36, 0x34, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, //
      0xaa, 0x00, 0x38, 0x9b, 0x71, //
    ],
    formatName: 'h264',
    bpp: 0,
  );

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Frame rates in frames per second.
  final List<int> fps;

  /// Frame format.
  final UvcFormat format;

  /// Bits per pixel (for framebased formats). 0 for compressed.
  final int bpp;

  /// 16-byte GUID identifying the pixel format (for framebased formats).
  final List<int>? guid;

  /// Short name used for the configfs directory (for framebased formats).
  final String? formatName;

  /// Optional color matching information.
  final UvcColorMatching? colorMatching;

  String get _effectiveName {
    if (format == .framebased && formatName != null) return formatName!;
    return format._name;
  }

  String get groupPath => 'streaming/${format._groupDir}/$_effectiveName';

  String get _frameDirName => '${height}p';

  String get framePath => '$groupPath/$_frameDirName';

  String get headerLinkPath => 'streaming/header/h/$_effectiveName';

  String get _colorMatchingPath => 'streaming/color_matching/$_effectiveName';

  String get _colorMatchingLinkPath => '$groupPath/color_matching';

  /// Convert fps values to 100 ns interval units.
  List<int> get intervals => [
    ...fps.where((f) => f > 0).map((f) => 10000000 ~/ f),
  ];
}

/// UVC (USB Video Class) function for webcam emulation.
///
/// Requires a userspace program (such as `uvc-gadget`) to respond to UVC
/// control requests and fill V4L2 buffers.
///
/// ## Example
///
/// ```dart
/// final uvc = UvcFunction(
///   name: 'uvc',
///   frames: [
///     UvcFrame.yuyv(640, 480, [15, 30]),
///     UvcFrame.mjpeg(1280, 720, [30]),
///   ],
/// );
/// ```
class UvcFunction extends KernelFunction {
  UvcFunction({
    required super.name,
    this.frames = const [],
    this.streamingMaxpacket = 3072,
    this.streamingMaxburst = 0,
    this.streamingInterval = 1,
    this.processingControls,
    this.cameraControls,
    this.functionName,
  }) : super(kernelType: .uvc);

  /// Video frames to expose. Must contain at least one frame when binding.
  final List<UvcFrame> frames;

  /// Maximum packet size for streaming endpoint (valid: 1024, 2048, 3072)
  final int streamingMaxpacket;

  /// Maximum burst size (USB 3.0 only)
  final int streamingMaxburst;

  /// Streaming interval (1-16, frame rate related)
  final int streamingInterval;

  /// Processing Unit's bmControls field
  final int? processingControls;

  /// Camera Terminal's bmControls field
  final int? cameraControls;

  /// Video device interface name
  final String? functionName;

  @override
  bool validate() {
    if (streamingMaxpacket <= 0 || streamingMaxpacket > 3072) {
      log?.error('Invalid streaming_maxpacket: $streamingMaxpacket');
      return false;
    }
    if (streamingInterval < 1 || streamingInterval > 16) {
      log?.error('Invalid streaming_interval: $streamingInterval');
      return false;
    }
    return true;
  }

  // When frames are provided we must build the configfs directory structure
  // manually instead of just writing attributes.
  ConfigFsTree? _tree;

  @override
  Future<void> prepare(String path) async {
    await super.prepare(path);
    if (frames.isNotEmpty) {
      _tree = ConfigFsTree();
      _writeFrameDescriptors(path, _tree!);
    }
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    _tree?.sweep();
    _tree = null;
    await super.release();
  }

  @override
  Map<String, String> getConfigAttributes() {
    final attrs = <String, String>{
      'streaming_maxpacket': streamingMaxpacket.toString(),
      'streaming_maxburst': streamingMaxburst.toString(),
      'streaming_interval': streamingInterval.toString(),
    };
    if (functionName != null) attrs['function_name'] = functionName!;
    return attrs;
  }

  void _writeFrameDescriptors(String base, ConfigFsTree tree) {
    final seenColorMatching = <String>{};
    final seenGroups = <String>{};

    tree.mkdirp('$base/streaming/header/h');
    tree.mkdirp('$base/control/header/h');

    for (final frame in frames) {
      tree.mkdirp('$base/${frame.framePath}');

      if (frame.format == .framebased && frame.guid != null) {
        File(
          '$base/${frame.groupPath}/guidFormat',
        ).writeAsBytesSync(frame.guid!);
      }

      File(
        '$base/${frame.framePath}/wWidth',
      ).writeAsStringSync(frame.width.toString());
      File(
        '$base/${frame.framePath}/wHeight',
      ).writeAsStringSync(frame.height.toString());

      if (frame.format == .framebased) {
        File(
          '$base/${frame.framePath}/dwBytesPerLine',
        ).writeAsStringSync((frame.width * frame.bpp ~/ 8).toString());
      } else {
        File(
          '$base/${frame.framePath}/dwMaxVideoFrameBufferSize',
        ).writeAsStringSync((frame.width * frame.height * 2).toString());
      }

      File(
        '$base/${frame.framePath}/dwFrameInterval',
      ).writeAsStringSync(frame.intervals.join('\n'));

      final cm = frame.colorMatching;
      if (cm != null && seenColorMatching.add(frame._colorMatchingPath)) {
        tree.mkdirp('$base/${frame._colorMatchingPath}');
        File(
          '$base/${frame._colorMatchingPath}/bColorPrimaries',
        ).writeAsStringSync(cm.colorPrimaries.toString());
        File(
          '$base/${frame._colorMatchingPath}/bTransferCharacteristics',
        ).writeAsStringSync(cm.transferCharacteristics.toString());
        File(
          '$base/${frame._colorMatchingPath}/bMatrixCoefficients',
        ).writeAsStringSync(cm.matrixCoefficients.toString());
        tree.symlink(
          '$base/${frame._colorMatchingLinkPath}',
          '$base/${frame._colorMatchingPath}',
        );
      }

      if (seenGroups.add(frame.groupPath)) {
        tree.symlink(
          '$base/${frame.headerLinkPath}',
          '$base/${frame.groupPath}',
        );
      }
    }

    for (final cls in ['fs', 'hs', 'ss']) {
      tree.mkdirp('$base/streaming/class/$cls');
      tree.symlink('$base/streaming/class/$cls/h', '$base/streaming/header/h');
    }
    for (final cls in ['fs', 'ss']) {
      tree.mkdirp('$base/control/class/$cls');
      tree.symlink('$base/control/class/$cls/h', '$base/control/header/h');
    }
    if (processingControls != null) {
      File(
        '$base/control/processing/default/bmControls',
      ).writeAsStringSync(processingControls.toString());
    }
    if (cameraControls != null) {
      File(
        '$base/control/terminal/camera/default/bmControls',
      ).writeAsStringSync(cameraControls.toString());
    }
  }

  /// Gets the V4L2 video device path (e.g., `/dev/video0`).
  ///
  /// Parses the `dev` attribute to get the minor number and constructs
  /// the device path. Returns `null` if not available.
  String? getVideoDevice() {
    if (!prepared) return null;

    try {
      final dev = readAttribute('dev');
      if (dev != null) {
        final parts = dev.trim().split(':');
        if (parts.length == 2) {
          final minor = int.tryParse(parts[1]);
          if (minor != null) {
            return '/dev/video$minor';
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
