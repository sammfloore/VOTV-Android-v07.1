import '../services/iptv_api_service.dart';

class AppSession {
  const AppSession({
    required this.accountName,
    required this.isDemo,
    this.credentials,
  });

  final String accountName;
  final bool isDemo;
  final LoginCredentials? credentials;
}
