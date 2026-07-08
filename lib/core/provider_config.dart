class ProviderEndpoint {
  const ProviderEndpoint({
    required this.id,
    required this.scheme,
    required this.host,
    required this.port,
    required this.priority,
    this.enabled = true,
  });

  final String id;
  final String scheme;
  final String host;
  final int port;
  final int priority;
  final bool enabled;

  Uri get baseUri => Uri(
        scheme: scheme,
        host: host,
        port: port,
      );

  String get endpointKey => '${scheme.toLowerCase()}://${host.toLowerCase()}:$port';

  Map<String, dynamic> toMap() => {
        'id': id,
        'baseUrl': baseUri.toString(),
        'priority': priority,
        'enabled': enabled,
      };

  static ProviderEndpoint? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim().toLowerCase();
    final baseUrl = '${raw['baseUrl'] ?? ''}'.trim();
    final priority = int.tryParse('${raw['priority'] ?? ''}') ?? 999;
    final enabledRaw = raw['enabled'];
    final enabled = enabledRaw is bool
        ? enabledRaw
        : '${enabledRaw ?? 'true'}'.toLowerCase() != 'false';
    final uri = Uri.tryParse(baseUrl);

    if (!RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(id)) return null;
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.trim().isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final port = uri.port;
    if (port <= 0 || port > 65535 || priority < 0 || priority > 9999) {
      return null;
    }

    return ProviderEndpoint(
      id: id,
      scheme: uri.scheme.toLowerCase(),
      host: uri.host,
      port: port,
      priority: priority,
      enabled: enabled,
    );
  }
}

class ProviderConfig {
  const ProviderConfig._();

  static const String displayName = 'AVO TV';

  // Repositorio público separado que solo contiene avotv-config.json.
  // La aplicación intenta GitHub Pages y después raw.githubusercontent.com.
  static final List<Uri> remoteConfigUris = [
    Uri.parse(
      'https://sammfloore.github.io/avotv-config/avotv-config.json',
    ),
    Uri.parse(
      'https://raw.githubusercontent.com/sammfloore/avotv-config/main/avotv-config.json',
    ),
  ];

  static const List<ProviderEndpoint> fallbackServers = [
    ProviderEndpoint(
      id: 'plus',
      scheme: 'http',
      host: 'ultratvsv.site',
      port: 80,
      priority: 1,
    ),
    ProviderEndpoint(
      id: 'normal',
      scheme: 'http',
      host: 'avotv.online',
      port: 8080,
      priority: 2,
    ),
  ];

  static ProviderEndpoint get defaultServer => fallbackServers.last;

  // Compatibilidad con sesiones creadas antes de v0.6.9.
  static String get scheme => defaultServer.scheme;
  static String get host => defaultServer.host;
  static int get port => defaultServer.port;
  static Uri get baseUri => defaultServer.baseUri;
}
