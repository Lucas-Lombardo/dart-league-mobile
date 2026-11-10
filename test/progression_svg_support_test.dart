// What flutter_svg (vector_graphics_compiler) really renders, for the asset
// rules of docs/progression/CONTRACT.md §10. Fixtures follow
// docs/progression/svg/reference_svg.py.
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

const _monogram = '''
<svg width="132" height="132" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg"><defs>
<linearGradient id="a-r" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E2E8F0"/><stop offset="0.48" stop-color="#7B8798"/><stop offset="1" stop-color="#CBD5E1"/></linearGradient>
<linearGradient id="a-t" x1="0" y1="38" x2="0" y2="84" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#E2E8F0"/><stop offset="1" stop-color="#CBD5E1"/></linearGradient>
<radialGradient id="a-bg" cx="0.42" cy="0.36" r="0.7"><stop offset="0" stop-color="#26324A"/><stop offset="1" stop-color="#0B1222"/></radialGradient>
<clipPath id="a-c"><circle cx="60" cy="60" r="50.5"/></clipPath></defs>
<circle cx="60" cy="60" r="58" fill="url(#a-r)"/>
<circle cx="60" cy="60" r="50.5" fill="url(#a-bg)" stroke="rgba(11,18,34,0.7)" stroke-width="1.5"/>
<g clip-path="url(#a-c)"><circle cx="60" cy="60" r="36" fill="none" stroke="rgba(255,255,255,0.10)" stroke-width="0.6"/></g>
<text x="60" y="75.8" text-anchor="middle" font-family="Manrope" font-weight="800" font-size="44" fill="url(#a-t)">LL</text>
<ellipse cx="20" cy="60" rx="3.3" ry="8" transform="rotate(22 20 60)" fill="url(#a-r)"/>
</svg>''';

const _carbonPattern = '''
<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg"><defs>
<pattern id="b-p" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
<rect width="4" height="4" fill="#0E1013"/><rect x="4" y="4" width="4" height="4" fill="#4A5059"/></pattern></defs>
<rect width="120" height="120" fill="url(#b-p)"/></svg>''';

const _turbulence = '''
<svg viewBox="0 0 240 150" xmlns="http://www.w3.org/2000/svg"><defs>
<filter id="c-n" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3"/>
<feColorMatrix type="matrix" values="0 0 0 0 0.8 0 0 0 0 0.6 0 0 0 0 0.4 0.6 0 0 0 0"/></filter></defs>
<rect width="240" height="150" fill="#33281D"/><rect width="240" height="150" filter="url(#c-n)"/></svg>''';

/// Same options as flutter_svg's runtime loader (no PathOps optimizers).
List<int> _compile(String xml, {bool strict = false}) => encodeSvg(
      xml: xml,
      debugName: 'test',
      enableClippingOptimizer: false,
      enableMaskingOptimizer: false,
      enableOverdrawOptimizer: false,
      warningsAsErrors: strict,
    );

void main() {
  test('gradients, clipPath, ellipse, transforms and text compile strictly', () {
    final bytes = _compile(_monogram, strict: true);
    expect(bytes, isNotEmpty);
  });

  test('a pattern compiles (patternTransform is ignored, so pre-rotate the tile)', () {
    final bytes = _compile(_carbonPattern, strict: true);
    expect(bytes, isNotEmpty);
  });

  test('feTurbulence is NOT supported: texture backgrounds must be rasterized', () {
    expect(
      () => _compile(_turbulence, strict: true),
      throwsA(isA<UnimplementedError>()),
    );
    // Without strict mode the filter is silently dropped: only the flat base
    // color would show, which is why textures ship as WebP/PNG.
    expect(_compile(_turbulence), isNotEmpty);
  });
}
