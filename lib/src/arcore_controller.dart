import 'dart:typed_data';

import 'package:arcore_flutter_plugin/src/arcore_augmented_image.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'arcore_hit_test_result.dart';
import 'arcore_node.dart';
import 'arcore_plane.dart';

typedef StringResultHandler = void Function(String text);
typedef UnsupportedHandler = void Function(String text);
typedef ArCoreHitResultHandler = void Function(List<ArCoreHitTestResult> hits);
typedef ArCorePlaneHandler = void Function(ArCorePlane plane);
typedef ArCoreAugmentedImageTrackingHandler = void Function(
    ArCoreAugmentedImage);

const UTILS_CHANNEL_NAME = 'arcore_flutter_plugin/utils';

class ArCoreController {
  static checkArCoreAvailability() async {
    final bool arcoreAvailable = await MethodChannel(UTILS_CHANNEL_NAME)
        .invokeMethod('checkArCoreApkAvailability');
    return arcoreAvailable;
  }

  static checkIsArCoreInstalled() async {
    final bool arcoreInstalled = await MethodChannel(UTILS_CHANNEL_NAME)
        .invokeMethod('checkIfARCoreServicesInstalled');
    return arcoreInstalled;
  }

  ArCoreController(
      {int id,
      this.enableTapRecognizer,
      this.enablePlaneRenderer,
      this.enableUpdateListener,
      this.debug = false
//    @required this.onUnsupported,
      }) {
    _channel = MethodChannel('arcore_flutter_plugin_$id');
    _channel.setMethodCallHandler(_handleMethodCalls);
    init();
  }

  final bool enableUpdateListener;
  final bool enableTapRecognizer;
  final bool enablePlaneRenderer;
  final bool debug;
  MethodChannel _channel;
  StringResultHandler onError;
  StringResultHandler onNodeTap;

//  UnsupportedHandler onUnsupported;
  ArCoreHitResultHandler onPlaneTap;
  ArCorePlaneHandler onPlaneDetected;
  String trackingState = '';
  ArCoreAugmentedImageTrackingHandler onTrackingImage;

  init() async {
    try {
      await _channel.invokeMethod<void>('init', {
        'enableTapRecognizer': enableTapRecognizer,
        'enablePlaneRenderer': enablePlaneRenderer,
        'enableUpdateListener': enableUpdateListener,
      });
    } on PlatformException catch (ex) {
      print(ex.message);
    }
  }

  Future<dynamic> _handleMethodCalls(MethodCall call) async {
    if (debug) {
      print('_platformCallHandler call ${call.method} ${call.arguments}');
    }

    switch (call.method) {
      case 'onError':
        if (onError != null) {
          onError(call.arguments);
        }
        break;
      case 'onNodeTap':
        if (onNodeTap != null) {
          onNodeTap(call.arguments);
        }
        break;
      case 'onPlaneTap':
        if (onPlaneTap != null) {
          final List<dynamic> input = call.arguments;
          final objects = input
              .cast<Map<dynamic, dynamic>>()
              .map<ArCoreHitTestResult>(
                  (Map<dynamic, dynamic> h) => ArCoreHitTestResult.fromMap(h))
              .toList();
          onPlaneTap(objects);
        }
        break;
      case 'onPlaneDetected':
        if (enableUpdateListener && onPlaneDetected != null) {
          final plane = ArCorePlane.fromMap(call.arguments);
          onPlaneDetected(plane);
        }
        break;
      case 'getTrackingState':
        // TRACKING, PAUSED or STOPPED
        trackingState = call.arguments;
        if (debug) {
          print('Latest tracking state received is: $trackingState');
        }
        break;
      case 'onTrackingImage':
        if (debug) {
          print('flutter onTrackingImage');
        }
        final arCoreAugmentedImage =
            ArCoreAugmentedImage.fromMap(call.arguments);
        onTrackingImage(arCoreAugmentedImage);
        break;
      default:
        if (debug) {
          print('Unknown method ${call.method}');
        }
    }
    return Future.value();
  }

  Future<void> addArCoreNode(ArCoreNode node, {String parentNodeName}) {
    assert(node != null);
    final params = _addParentNodeNameToParams(node.toMap(), parentNodeName);
    if (debug) {
      print(params.toString());
    }
    _addListeners(node);
    return _channel.invokeMethod('addArCoreNode', params);
  }

  Future<String> getTrackingState() async {
    return _channel.invokeMethod('getTrackingState');
  }

  Future<void> addArCoreNodeToAugmentedImage(ArCoreNode node, int index,
      {String parentNodeName}) {
    assert(node != null);

    final params = _addParentNodeNameToParams(node.toMap(), parentNodeName);
    return _channel.invokeMethod(
        'attachObjectToAugmentedImage', {'index': index, 'node': params});
  }

  Future<void> addVideoToAugmentedImage(int index,
      {String parentNodeName, String videoAsset, String chromaAsset}) {
    return _channel.invokeMethod('attachVideoToAugmentedImage',
        {'index': index, 'video': videoAsset, 'chroma': chromaAsset});
  }

  Future<void> addArCoreNodeWithAnchor(ArCoreNode node,
      {String parentNodeName}) {
    assert(node != null);
    final params = _addParentNodeNameToParams(node.toMap(), parentNodeName);
    if (debug) {
      print(params.toString());
    }
    _addListeners(node);
    if (debug) {
      print('---------_CALLING addArCoreNodeWithAnchor : $params');
    }
    return _channel.invokeMethod('addArCoreNodeWithAnchor', params);
  }

  Future<void> removeNode({@required String nodeName}) {
    assert(nodeName != null);
    return _channel.invokeMethod('removeARCoreNode', {'nodeName': nodeName});
  }

  Map<String, dynamic> _addParentNodeNameToParams(
      Map geometryMap, String parentNodeName) {
    if (parentNodeName?.isNotEmpty ?? false)
      geometryMap['parentNodeName'] = parentNodeName;
    return geometryMap;
  }

  void _addListeners(ArCoreNode node) {
    node.translationControllerNode
        .addListener(() => _handlePositionConfigChanged(node));
    node.scaleControllerNode.addListener(() => _handleScaleConfigChanged(node));
    node.rotationControllerNode
        .addListener(() => _handleRotationConfigChanged(node));
    node?.shape?.materials?.addListener(() => _updateMaterials(node));

    // if (node is ArCoreRotatingNode) {
    //   node.degreesPerSecond.addListener(() => _handleRotationChanged(node));
    // }
  }

/*  void _handleScaleChanged(ArCoreNode node) {
    print('_handleScaleChanged: ${node.name}');
    _channel.invokeMethod<void>(
        'scaleChanged',
        _getHandlerParams(
            node,
            _getHandlerParams(node, <String, dynamic>{
              'scale': convertVector3ToMap(node.scale.value)
            })));
  }

  void _handlePositionChanged(ArCoreNode node) {
    print('_handlePositionChanged: ${node.name}');
    _channel.invokeMethod<void>(
        'positionChanged',
        _getHandlerParams(
            node,
            _getHandlerParams(node, <String, dynamic>{
              'position': convertVector3ToMap(node.position.value)
            })));
  }

  void _handleRotationChanged(ArCoreNode node) {
    print('_handleRotationChanged: ${node.name}');
    _channel.invokeMethod<void>(
        'rotationChanged',
        _getHandlerParams(node, <String, dynamic>{
          'rotation': convertVector4ToMap(node.rotation.value)
        }));
  }*/

  void _handleRotationConfigChanged(ArCoreNode node) {
    print('_handleRotationGestureChanged: ${node.name}');
    _channel.invokeMethod<void>('rotationConfigChanged',
        _getHandlerParams(node, node.rotationControllerNode?.value?.toMap()));
  }

  void _handleScaleConfigChanged(ArCoreNode node) {
    print('_handleScaleConfigChanged: ${node.name}');
    _channel.invokeMethod<void>('scaleConfigChanged',
        _getHandlerParams(node, node.scaleControllerNode?.value?.toMap()));
  }

  void _handlePositionConfigChanged(ArCoreNode node) {
    print('_handlePositionConfigChanged: ${node.name}');
    _channel.invokeMethod<void>(
        'positionConfigChanged',
        _getHandlerParams(
            node, node.translationControllerNode?.value?.toMap()));
  }

  void _updateMaterials(ArCoreNode node) {
    print('_updateMaterials: ${node.name}');
    _channel.invokeMethod<void>(
        'updateMaterials', _getHandlerParams(node, node.shape.toMap()));
  }

  Map<String, dynamic> _getHandlerParams(
      ArCoreNode node, Map<String, dynamic> params) {
    final Map<String, dynamic> values = <String, dynamic>{'name': node.name}
      ..addAll(params);
    values.removeWhere((k, v) => v == null);
    return values;
  }

  Future<void> loadSingleAugmentedImage({@required Uint8List bytes}) {
    assert(bytes != null);
    return _channel.invokeMethod('load_single_image_on_db', {
      'bytes': bytes,
    });
  }

  Future<void> loadMultipleAugmentedImage(
      {@required Map<String, Uint8List> bytesMap}) {
    assert(bytesMap != null);
    return _channel.invokeMethod('load_multiple_images_on_db', {
      'bytesMap': bytesMap,
    });
  }

  Future<void> loadAugmentedImagesDatabase({@required Uint8List bytes}) {
    assert(bytes != null);
    return _channel.invokeMethod('load_augmented_images_database', {
      'bytes': bytes,
    });
  }

  void dispose() {
    _channel?.invokeMethod<void>('dispose');
  }

  void resume() {
    _channel?.invokeMethod<void>('resume');
  }

  Future<void> removeNodeWithIndex(int index) async {
    try {
      return await _channel.invokeMethod('removeARCoreNodeWithIndex', {
        'index': index,
      });
    } catch (ex) {
      print(ex);
    }
  }
}
