import 'package:flutter/material.dart';

class NetworkArt extends StatelessWidget {
  const NetworkArt({
    super.key,
    required this.url,
    required this.fit,
    this.borderRadius,
    this.cacheWidth = 720,
    this.fallbackLabel = '',
    this.live = false,
  });

  static const _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 AVO-TV/0.6.2',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  final String url;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? cacheWidth;
  final String fallbackLabel;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    final valid = normalized.isNotEmpty &&
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    final content = valid
        ? Image.network(
            normalized,
            headers: _headers,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: cacheWidth != null && cacheWidth! > 0
                ? cacheWidth!.clamp(96, 1080).toInt()
                : null,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return _fallback(context, loading: true);
            },
            errorBuilder: (_, _, _) => _fallback(context),
          )
        : _fallback(context);

    if (borderRadius == null) return content;
    return ClipRRect(borderRadius: borderRadius!, child: content);
  }

  Widget _fallback(BuildContext context, {bool loading = false}) {
    final initials = fallbackLabel
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
            const Color(0xFF151A20),
          ],
        ),
      ),
      child: Center(
        child: loading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    live ? Icons.live_tv_rounded : Icons.movie_creation_outlined,
                    size: live ? 38 : 44,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                  if (initials.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      initials,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
