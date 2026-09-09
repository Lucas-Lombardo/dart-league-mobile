import 'dart:async';

// The fake exercises CameraController's real stream/ownership transitions.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/camera_frame_service.dart';

class _CameraPlatform extends CameraPlatform {
  final created = <int>[];
  final disposed = <int>[];
  final streaming = <int>{};
  final lenses = <CameraDescription>[];
  final zoom = <int, double>{};
  final frames = <int, StreamController<CameraImageData>>{};
  Completer<void>? disposalGate;
  Completer<void>? initializationGate;
  Completer<void>? streamStopGate;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async {
    final id = created.length;
    created.add(id);
    lenses.add(description);
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializationGate?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    if (disposed.contains(cameraId)) throw StateError('Camera is closed');
    if (streaming.contains(cameraId)) {
      throw StateError('Previous stream is still active');
    }
    frames[cameraId] = StreamController<CameraImageData>(
      onListen: () => streaming.add(cameraId),
      onCancel: () async {
        await streamStopGate?.future;
        streaming.remove(cameraId);
      },
    );
    return frames[cameraId]!.stream;
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 4;

  @override
  Future<void> setZoomLevel(int cameraId, double value) async {
    zoom[cameraId] = value;
  }

  @override
  Future<void> dispose(int cameraId) async {
    await disposalGate?.future;
    disposed.add(cameraId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraPlatform original;
  late _CameraPlatform platform;
  late CameraFrameService service;
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    original = CameraPlatform.instance;
    platform = _CameraPlatform();
    CameraPlatform.instance = platform;
    service = CameraFrameService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => null);
  });

  tearDown(() async {
    await service.dispose();
    CameraPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
  });

  test(
    'background resume reopens the selected lens and restores zoom',
    () async {
      await service.initialize();
      await service.switchCamera();
      await service.setZoomLevel(2.5);
      final oldId = platform.created.last;

      service.pause(releaseCamera: true);
      await service.resume();

      final newId = platform.created.last;
      expect(newId, isNot(oldId));
      expect(platform.disposed, contains(oldId));
      expect(platform.lenses.last.lensDirection, CameraLensDirection.front);
      expect(platform.zoom[newId], 2.5);
      expect(platform.streaming, {newId});
    },
  );

  test('resume waits for native camera release', () async {
    await service.initialize();
    platform.disposalGate = Completer<void>();
    service.pause(releaseCamera: true);
    final resuming = service.resume();
    await Future<void>.delayed(Duration.zero);
    expect(platform.created, [0]);
    platform.disposalGate!.complete();
    await resuming;
    expect(platform.created, [0, 1]);
    expect(platform.streaming, {1});
  });

  test(
    'backgrounding during initial setup releases before reopening',
    () async {
      platform.initializationGate = Completer<void>();
      final initializing = service.initialize();
      await Future<void>.delayed(Duration.zero);
      service.pause(releaseCamera: true);
      final resuming = service.resume();
      platform.initializationGate!.complete();
      await Future.wait([initializing, resuming]);
      expect(platform.disposed, [0]);
      expect(platform.streaming, {1});
    },
  );

  test('backgrounding clears the image cached for AI', () async {
    await service.initialize();
    platform.frames[0]!.add(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        planes: [
          CameraImagePlane(
            bytes: Uint8List.fromList([128, 128, 128, 128]),
            bytesPerRow: 2,
            bytesPerPixel: 1,
          ),
          CameraImagePlane(
            bytes: Uint8List.fromList([128]),
            bytesPerRow: 1,
            bytesPerPixel: 1,
          ),
          CameraImagePlane(
            bytes: Uint8List.fromList([128]),
            bytesPerRow: 1,
            bytesPerPixel: 1,
          ),
        ],
        height: 2,
        width: 2,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.captureRgba(), isNotNull);
    service.pause(releaseCamera: true);
    expect(service.captureRgba(), isNull);
    await service.resume();
    expect(
      service.captureRgba(),
      isNull,
      reason: 'AI must wait for a fresh image from the reopened camera',
    );
  });

  test('AI state changes cannot restart capture while backgrounded', () async {
    await service.initialize();
    service.pause(releaseCamera: true);
    service.setAiActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(platform.streaming, isEmpty);
    await service.resume();
    expect(platform.streaming, {1});
  });

  test('resume preserves a deliberately stopped solo AI stream', () async {
    await service.initialize();
    service.setAiActive(false);
    service.pause(releaseCamera: true);
    await service.resume();
    expect(service.isInitialized, isTrue);
    expect(platform.streaming, isEmpty);
  });

  test(
    'an attached call resumes frames even when AI is between turns',
    () async {
      await service.initialize(p2pMode: true);
      service.setAiActive(false);
      service.pause(releaseCamera: true);
      await service.resume();
      expect(platform.streaming, {1});
    },
  );

  test('a brief inactive interruption keeps the camera controller', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await service.initialize();
    service.pause(releaseCamera: false);
    await service.resume();
    expect(platform.created, [0]);
    expect(platform.disposed, isEmpty);
    expect(platform.streaming, {0});
  });

  test('Android default pause reopens solo cameras', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await service.initialize();
    service.pause();
    await service.resume();
    expect(platform.disposed, [0]);
    expect(platform.streaming, {1});
  });

  test(
    'inactive during reopen retries zoom without leaking a controller',
    () async {
      await service.initialize();
      await service.setZoomLevel(2.5);
      service.pause(releaseCamera: true);
      platform.initializationGate = Completer<void>();
      final resuming = service.resume();
      await Future<void>.delayed(Duration.zero);
      expect(platform.created, [0, 1]);
      service.pause(releaseCamera: false);
      platform.initializationGate!.complete();
      await resuming;
      expect(platform.streaming, isEmpty);
      await service.resume();
      expect(platform.created, [0, 1]);
      expect(platform.disposed, [0]);
      expect(platform.zoom[1], 2.5);
      expect(platform.streaming, {1});
    },
  );

  test(
    'iOS-style resume waits for stream cancellation and keeps the device',
    () async {
      await service.initialize(p2pMode: true);
      service.setAiActive(false);
      platform.streamStopGate = Completer<void>();
      service.pause();
      await Future<void>.delayed(Duration.zero);
      final resuming = service.resume();
      await Future<void>.delayed(Duration.zero);
      // Native cancellation has not finished: a new subscription must wait.
      expect(platform.streaming, {0});
      platform.streamStopGate!.complete();
      await resuming;
      expect(service.controller!.value.isStreamingImages, isTrue);
      expect(platform.streaming, {0});
      expect(platform.created, [0]);
      expect(platform.disposed, isEmpty);
    },
  );

  test('leaving the match during resume cannot reopen its camera', () async {
    await service.initialize();
    platform.disposalGate = Completer<void>();
    service.pause(releaseCamera: true);
    final resuming = service.resume();
    final disposing = service.dispose();
    platform.disposalGate!.complete();
    await Future.wait([resuming, disposing]);
    expect(platform.created, [0]);
    expect(service.controller, isNull);
    expect(platform.streaming, isEmpty);
  });

  test(
    'a second background event during reopen still releases that camera',
    () async {
      await service.initialize();
      platform.initializationGate = Completer<void>();
      service.pause(releaseCamera: true);
      final firstResume = service.resume();
      await Future<void>.delayed(Duration.zero);
      expect(platform.created, [0, 1]);
      service.pause(releaseCamera: true);
      final secondResume = service.resume();
      platform.initializationGate!.complete();
      await Future.wait([firstResume, secondResume]);
      expect(platform.disposed, [0, 1]);
      expect(platform.streaming, {2});
    },
  );
}
