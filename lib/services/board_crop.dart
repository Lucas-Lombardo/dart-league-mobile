import 'dart:math' as math;

import 'board_framing.dart';
import 'dart_scoring_service.dart';

/// The board crop of the outgoing match video (2026-09-06 design, option B).
///
/// The thrower's phone knows exactly where its board is — the AI projects the
/// full board circle every frame (see [BoardFraming]) — so instead of
/// streaming the whole room and letting the opponent's screen guess which
/// square to keep, the sender crops a square around its board BEFORE the
/// encoder. The 1 100 kbit/s then go to the board alone (sharper, cooler),
/// and the opponent always receives the whole board, centred, whatever the
/// two phones' orientations.
///
/// Everything here is pure Dart and unit-tested: the crop geometry, its
/// mapping into the raw (unrotated) Android frame, the turn state machine
/// that keeps the crop STILL while darts fly, and the "look here" point that
/// travels with every dart so the opponent's screen can zoom on it.

/// Side of the square the sender streams once it crops. Fixed on purpose:
/// hardware H264 encoders on Android are fragile on resolution changes, so
/// the encoder must never see the crop grow or shrink between turns.
const int kBoardCropOutputSide = 640;

/// Square side over the projected board diameter — enough surround to keep
/// the numbers ring and a dart's flight in frame.
const double kBoardCropMargin = 1.18;

/// Movement (as a fraction of the square's side) below which a re-measured
/// board does not move the crop between two turns — a crop that "swims" by a
/// few pixels every turn is worse than one that is a hair off-centre.
const double kBoardCropHysteresis = 0.02;

/// Where the board sits in the UPRIGHT frame, in units that survive a change
/// of frame size: normalized centre plus the square's side as a fraction of
/// the frame height. [aspect] (width / height) and [rotation] (clockwise
/// degrees raw → upright) record the frame it was measured on, so a push
/// from a differently oriented camera can refuse it instead of cropping the
/// wrong region.
class BoardCropPlan {
  final double centerX;
  final double centerY;
  final double sideOverHeight;
  final double aspect;
  final int rotation;

  const BoardCropPlan({
    required this.centerX,
    required this.centerY,
    required this.sideOverHeight,
    required this.aspect,
    required this.rotation,
  });

  @override
  String toString() =>
      'BoardCropPlan(c=(${centerX.toStringAsFixed(3)}, ${centerY.toStringAsFixed(3)}) '
      'side/h=${sideOverHeight.toStringAsFixed(3)} aspect=${aspect.toStringAsFixed(3)} rot=$rotation)';
}

/// An integer rectangle in some frame's pixel space.
class PixelRect {
  final int x;
  final int y;
  final int width;
  final int height;

  const PixelRect(this.x, this.y, this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is PixelRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PixelRect($x, $y, ${width}x$height)';
}

/// A normalized point in the frame the opponent actually receives.
class VideoPoint {
  final double x;
  final double y;
  const VideoPoint(this.x, this.y);

  @override
  String toString() => 'VideoPoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

class BoardCropPlanner {
  BoardCropPlanner._();

  /// The square to keep around a board measured as [framing] on an upright
  /// frame of [imageWidth]×[imageHeight]. Null when the measurement is
  /// unusable (degenerate dimensions or a circle with no size).
  static BoardCropPlan? planFor(
    BoardFraming framing, {
    required int imageWidth,
    required int imageHeight,
    required int rotation,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return null;
    final aspect = imageWidth / imageHeight;
    // The circle's diameter in pixels is the larger of its two extents once
    // each is scaled by its own axis — a portrait frame makes the x extent
    // (fraction of a short width) and the y extent (fraction of a tall
    // height) incomparable until then.
    final diameterOverHeight =
        math.max(framing.extentX * aspect, framing.extentY);
    if (!diameterOverHeight.isFinite || diameterOverHeight <= 0.01) return null;
    if (!framing.centerX.isFinite || !framing.centerY.isFinite) return null;
    return BoardCropPlan(
      centerX: framing.centerX,
      centerY: framing.centerY,
      sideOverHeight: diameterOverHeight * kBoardCropMargin,
      aspect: aspect,
      rotation: rotation,
    );
  }

  /// [plan] as a pixel square inside an upright frame of
  /// [uprightWidth]×[uprightHeight]: clamped into the frame (a board near an
  /// edge gets less margin on that side rather than a black band), never
  /// larger than the frame's short side, and snapped to even coordinates so
  /// the chroma planes crop cleanly. Null when the frame is not the one the
  /// plan was measured on (other aspect) — the caller then streams the whole
  /// frame rather than a wrong region.
  static PixelRect? uprightRect(
    BoardCropPlan plan,
    int uprightWidth,
    int uprightHeight,
  ) {
    if (uprightWidth <= 0 || uprightHeight <= 0) return null;
    final aspect = uprightWidth / uprightHeight;
    if ((aspect - plan.aspect).abs() > 0.015 * plan.aspect) return null;
    final shortSide = math.min(uprightWidth, uprightHeight);
    var side = (plan.sideOverHeight * uprightHeight).round();
    side = side.clamp(2, shortSide);
    side -= side % 2;
    if (side < 2) return null;
    var x = (plan.centerX * uprightWidth - side / 2).round();
    var y = (plan.centerY * uprightHeight - side / 2).round();
    x = x.clamp(0, uprightWidth - side);
    y = y.clamp(0, uprightHeight - side);
    x -= x % 2;
    y -= y % 2;
    return PixelRect(x, y, side, side);
  }

  /// The same region expressed in the RAW frame, i.e. before the [rotation]
  /// (clockwise degrees) that makes it upright. Android ships camera frames
  /// unrotated with that rotation as metadata, so the crop must be applied
  /// there; iOS frames arrive upright (rotation 0) and pass through.
  ///
  /// Convention, shared with the AI's pre-analysis rotation and WebRTC's
  /// frame rotation: upright = rotateClockwise(raw, rotation). A raw pixel
  /// (x, y) lands at (H_raw − y, x) after 90°, (W_raw − x, H_raw − y) after
  /// 180°, and (y, W_raw − x) after 270°.
  static PixelRect toRaw(
    PixelRect r,
    int uprightWidth,
    int uprightHeight,
    int rotation,
  ) {
    switch (((rotation % 360) + 360) % 360) {
      case 90:
        // raw dims = (uprightHeight, uprightWidth); H_raw = uprightWidth
        return PixelRect(r.y, uprightWidth - (r.x + r.width), r.height, r.width);
      case 180:
        return PixelRect(
          uprightWidth - (r.x + r.width),
          uprightHeight - (r.y + r.height),
          r.width,
          r.height,
        );
      case 270:
        // raw dims = (uprightHeight, uprightWidth); W_raw = uprightHeight
        return PixelRect(uprightHeight - (r.y + r.height), r.x, r.height, r.width);
      default:
        return r;
    }
  }

  /// Whether two plans disagree by more than [fraction] of the square's side
  /// on centre or size (the between-turns hysteresis).
  static bool differsBeyond(
    BoardCropPlan a,
    BoardCropPlan b,
    double fraction,
  ) {
    if (a.rotation != b.rotation) return true;
    if ((a.aspect - b.aspect).abs() > 0.015 * a.aspect) return true;
    // Compare in "height" units so x and y are commensurable.
    final side = math.max(a.sideOverHeight, 1e-6);
    final dx = (a.centerX - b.centerX).abs() * a.aspect;
    final dy = (a.centerY - b.centerY).abs();
    final ds = (a.sideOverHeight - b.sideOverHeight).abs();
    return dx > fraction * side || dy > fraction * side || ds > fraction * side;
  }
}

/// Sender-side state of the board crop and of the per-dart zoom point —
/// static, like the turn gate it follows ([RtcFramesService.setSendActive]).
///
/// Turn rules (Lucas's spec, 2026-09-06): the crop is re-measured from the
/// moment my turn starts, FROZEN at my first dart of the turn (the player is
/// often still in front of the board at the flip, so the flip itself is a
/// bad moment to trust a measurement), and only moves between two turns when
/// the board really moved (hysteresis). Without any measurement the sender
/// keeps its last square, and with none at all streams the whole frame,
/// exactly as before this feature.
class OpponentVideoFraming {
  OpponentVideoFraming._();

  static BoardCropPlan? _plan;
  static bool _myTurn = false;
  static bool _frozen = false;

  // The frame the camera service pushed LAST (upright pixels, rotation) and
  // the crop it applied to it. A dart's zoom point is expressed against the
  // crop the CURRENT plan yields on that frame — what the very next pushes
  // carry — falling back to the last applied crop when the plan cannot be
  // applied to it (see [_currentRect]).
  static PixelRect? _appliedRect;
  static int _appliedWidth = 0;
  static int _appliedHeight = 0;
  static int _appliedRotation = 0;

  // Last valid homography of the turn (image ↔ board), so a typed score can
  // still be pointed at on the outgoing video — with the rotation of the
  // frame it was measured on: after the phone turns, its image coordinates
  // no longer describe the frame the opponent receives.
  static DartScoringService? _lastScorer;
  static int _lastScorerRotation = 0;

  // Bumped by every match screen that takes ownership (see [claim]), so a
  // screen's deferred dispose can never wipe the state of the screen that
  // replaced it (the ~300 ms deferred-dispose overlap on match entry).
  static int _generation = 0;

  static BoardCropPlan? get plan => _plan;
  static bool get frozen => _frozen;
  static DartScoringService? get lastScorer => _lastScorer;

  static void setMyTurn(bool myTurn) {
    _myTurn = myTurn;
    // My turn starts: measurements may move the square again until the first
    // dart. Their turn: keep whatever square we have, still.
    _frozen = !myTurn;
  }

  /// First dart of the turn is on the board: the picture must not move any
  /// more until my next turn.
  static void freeze() {
    _frozen = true;
  }

  /// One board measurement from the AI on an upright analysis frame.
  static void reportFraming(
    BoardFraming framing, {
    required int imageWidth,
    required int imageHeight,
    required int rotation,
  }) {
    if (_frozen || !_myTurn) return;
    final candidate = BoardCropPlanner.planFor(
      framing,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      rotation: rotation,
    );
    if (candidate == null) return;
    final current = _plan;
    if (current == null ||
        BoardCropPlanner.differsBeyond(
            current, candidate, kBoardCropHysteresis)) {
      _plan = candidate;
    }
  }

  /// [rotation] is the clockwise raw → upright rotation of the frame the
  /// homography was measured on (0 on iOS).
  static void noteScorer(DartScoringService? scorer, {int rotation = 0}) {
    _lastScorer = scorer;
    _lastScorerRotation = rotation;
  }

  /// Recorded by the camera service on every push: the upright crop it
  /// applied (null = whole frame) on a frame of [uprightWidth]×[uprightHeight].
  static void noteApplied(
    PixelRect? rect,
    int uprightWidth,
    int uprightHeight, {
    int rotation = 0,
  }) {
    _appliedRect = rect;
    _appliedWidth = uprightWidth;
    _appliedHeight = uprightHeight;
    _appliedRotation = rotation;
  }

  /// The crop the next pushes will carry on the last pushed frame: the
  /// current plan applied to it, or — when the plan does not fit that frame
  /// (other rotation / aspect) — whatever the last push actually applied.
  /// Reading the plan rather than the last push closes the gap between a
  /// plan that just moved and the push that has not carried it yet.
  static PixelRect? _currentRect() {
    final plan = _plan;
    if (_appliedWidth <= 0 || _appliedHeight <= 0) return null;
    if (plan != null && plan.rotation == _appliedRotation) {
      return BoardCropPlanner.uprightRect(plan, _appliedWidth, _appliedHeight);
    }
    return _appliedRect;
  }

  /// A point given in normalized UPRIGHT frame coordinates, re-expressed in
  /// the frame the opponent receives (the crop, or the whole frame when no
  /// crop is applied). Null when it falls outside that frame.
  static VideoPoint? videoPointForUpright(double ux, double uy) {
    if (!ux.isFinite || !uy.isFinite) return null;
    final rect = _currentRect();
    double x, y;
    if (rect == null || _appliedWidth <= 0 || _appliedHeight <= 0) {
      x = ux;
      y = uy;
    } else {
      x = (ux * _appliedWidth - rect.x) / rect.width;
      y = (uy * _appliedHeight - rect.y) / rect.height;
    }
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    return VideoPoint(x, y);
  }

  /// A point in the scorer's normalized board space (bull at (1, 1), board
  /// edge at radius 1 — Shoot.actualPoint's space), on the outgoing video.
  static VideoPoint? videoPointForBoardNorm(double nx, double ny) {
    final scorer = _lastScorer;
    if (scorer == null) return null;
    // Measured on a frame the opponent is no longer receiving (the phone
    // turned since): better no zoom than a zoom on the wrong spot.
    if (_lastScorerRotation != _appliedRotation) return null;
    try {
      final img = scorer.boardToImage(nx * kBoardR, ny * kBoardR);
      return videoPointForUpright(img[0], img[1]);
    } catch (_) {
      return null; // singular homography
    }
  }

  /// Where a typed score sits on the outgoing video: the centre of the bed
  /// the notation designates. Null for a miss, or without a homography.
  static VideoPoint? videoPointForNotation({
    required int baseScore,
    required bool isDouble,
    required bool isTriple,
  }) {
    final board = DartScoringService.boardPointForNotation(
      baseScore: baseScore,
      isDouble: isDouble,
      isTriple: isTriple,
    );
    if (board == null) return null;
    return videoPointForBoardNorm(board[0] / kBoardR, board[1] / kBoardR);
  }

  /// A match screen takes ownership. Returns the token to hand back to
  /// [reset] so that only the current owner can clear the state.
  static int claim() => ++_generation;

  /// Forget everything — the match screen is going away. With
  /// [ifGeneration], a no-op unless that screen is still the owner (a
  /// deferred dispose must not wipe its successor's board).
  static void reset({int? ifGeneration}) {
    if (ifGeneration != null && ifGeneration != _generation) return;
    _plan = null;
    _myTurn = false;
    _frozen = false;
    _appliedRect = null;
    _appliedWidth = 0;
    _appliedHeight = 0;
    _appliedRotation = 0;
    _lastScorer = null;
    _lastScorerRotation = 0;
  }
}
