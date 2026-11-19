enum SttProvider {
  apple('Apple 设备端'),
  soniox('Soniox'),
  moss('MOSS Pro'),
  agentPlan('火山方舟 Agent Plan · 豆包语音识别 2.0');

  const SttProvider(this.label);
  final String label;

  bool get fileOnly => this == moss || this == agentPlan;

  static SttProvider? parse(Object? value) {
    for (final provider in values) {
      if (provider.name == value) return provider;
    }
    return null;
  }
}

SttProvider initialSpeechProvider({
  required SttProvider? saved,
  required bool appleSupported,
  required bool sonioxConfigured,
}) =>
    saved ??
    (appleSupported && !sonioxConfigured
        ? SttProvider.apple
        : SttProvider.soniox);
