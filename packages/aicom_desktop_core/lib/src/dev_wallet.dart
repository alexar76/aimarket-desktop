/// Production builds must inject ``WALLET_KEY`` via ``--dart-define``.
/// The fixed hex below is for local/dev only and must never be the only key in release.
library;

const String kAicomDevWalletKey =
    String.fromEnvironment('WALLET_KEY', defaultValue: '');

const String kAicomFallbackDevWalletKey =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

/// Resolve wallet key: require ``WALLET_KEY`` when ``dart.vm.product`` is true.
String resolveAicomWalletKey({bool? isProduct}) {
  final product = isProduct ?? bool.fromEnvironment('dart.vm.product');
  final fromEnv = kAicomDevWalletKey.trim();
  if (fromEnv.isNotEmpty) return fromEnv;
  if (product) {
    throw StateError(
      'WALLET_KEY is required in production builds '
      '(pass --dart-define=WALLET_KEY=...)',
    );
  }
  return kAicomFallbackDevWalletKey;
}

const kAicomDefaultHubUrl = 'https://modelmarket.dev';

const kAicomLocalHubUrl = 'http://127.0.0.1:8080';
