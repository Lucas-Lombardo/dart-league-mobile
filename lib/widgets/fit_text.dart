import 'package:flutter/widgets.dart';

/// A label that never cuts a word in two. It wraps between words on up to
/// [maxLines] lines; when its widest word, or the whole text, still does not
/// fit the width, the font shrinks by half points down to [minFontSize].
/// Only past that floor does the end give way (ellipsis), as a plain [Text] —
/// or, with [wholeWords], after the last whole word that fits.
///
/// A no-break space (U+00A0) keeps its neighbours together: "412 / 1 000"
/// written with them is one word, which is how a value and its unit stay on
/// the same line.
///
/// Uses a LayoutBuilder: never put it under an IntrinsicHeight/Width.
class FitText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final double minFontSize;
  final TextAlign? textAlign;

  /// Past [minFontSize], end on the last whole word that fits followed by
  /// « … », instead of an ellipsis inside a word.
  final bool wholeWords;

  const FitText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    required this.minFontSize,
    this.textAlign,
    this.wholeWords = false,
  });

  /// Breakable spaces only: a no-break space stays inside its word.
  static final _breaks = RegExp('[ \t\n]+');

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _fontSize(context, base, constraints.maxWidth);
        final style = base.copyWith(fontSize: size);
        var shown = text;
        if (wholeWords && constraints.maxWidth.isFinite && !_fits(context, text, style, constraints.maxWidth)) {
          shown = _wholeWordsPrefix(context, style, constraints.maxWidth);
        }
        return Text(
          shown,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style,
        );
      },
    );
  }

  bool _fits(BuildContext context, String s, TextStyle style, double maxWidth) {
    final p = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final over = p.didExceedMaxLines;
    p.dispose();
    return !over;
  }

  /// The most whole words that fit with « … » after them (the first word
  /// alone when none does: the plain ellipsis then takes over).
  String _wholeWordsPrefix(BuildContext context, TextStyle style, double maxWidth) {
    final words = text.split(_breaks).where((w) => w.isNotEmpty).toList();
    var lo = 1;
    var hi = words.length - 1;
    var best = '${words.first}…';
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final candidate = '${words.take(mid).join(' ')}…';
      if (_fits(context, candidate, style, maxWidth)) {
        best = candidate;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  double _fontSize(BuildContext context, TextStyle base, double maxWidth) {
    final start = base.fontSize ?? 14;
    if (!maxWidth.isFinite || text.isEmpty || start <= minFontSize) return start;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    double width(String s, TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    bool wraps(TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      final over = p.didExceedMaxLines;
      p.dispose();
      return !over;
    }

    // The widest word stays the widest at every size: measure it once.
    final words = text.split(_breaks).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return start;
    var widest = words.first;
    var widestWidth = width(widest, base);
    for (final w in words.skip(1)) {
      final ww = width(w, base);
      if (ww > widestWidth) {
        widest = w;
        widestWidth = ww;
      }
    }

    for (var size = start; size > minFontSize; size -= 0.5) {
      final style = base.copyWith(fontSize: size);
      final wordFits = size == start ? widestWidth <= maxWidth : width(widest, style) <= maxWidth;
      if (wordFits && wraps(style)) return size;
    }
    return minFontSize;
  }
}
