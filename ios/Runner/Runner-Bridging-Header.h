#import "GeneratedPluginRegistrant.h"
#import <TensorFlowLiteC/TensorFlowLiteC.h>
#import <TensorFlowLiteCCoreML/TensorFlowLiteCCoreML.h>
#import <TensorFlowLiteCMetal/TensorFlowLiteCMetal.h>
// RTC v2 (P2P) — RtcFramesPlugin.swift reaches into flutter_webrtc's native
// singleton (localTracks / peerConnectionFactory) and its LocalVideoTrack
// wrapper. WebRTC types come transitively via FlutterWebRTCPlugin.h.
#import <flutter_webrtc/FlutterWebRTCPlugin.h>
#import <flutter_webrtc/LocalVideoTrack.h>
