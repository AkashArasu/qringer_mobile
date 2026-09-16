class AppKeys {
  static const String streamApiKey = 'tu734pa6zc9p';
  static const String signalingBaseUrl = String.fromEnvironment(
    'QRINGER_SIGNALING_BASE_URL',
    defaultValue: 'https://token-server.takash-arasu.workers.dev',
  );
  // These are Stream dashboard provider names, never credentials. Configure
  // the APNs VoIP provider before shipping the iOS target.
  static const String iosPushProviderName = 'qringer_apns_voip';
  static const String androidPushProviderName = 'firebase_push_provider';
}
