import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Only this app's user-entered Agent Plan credential lives here.
class AgentPlanKeyStore {
  static const _name = 'soundcore-manager.agent-plan.asr';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accountName: _name),
    mOptions: MacOsOptions(
      accountName: _name,
      usesDataProtectionKeychain: false,
    ),
  );

  Future<String?> read() async {
    try {
      return await _storage.read(key: _name);
    } catch (_) {
      throw StateError('无法读取 Agent Plan 专属 API Key，请检查系统安全存储');
    }
  }

  Future<void> save(String? key) async {
    try {
      if (key == null) {
        await _storage.delete(key: _name);
      } else {
        await _storage.write(key: _name, value: key);
      }
    } catch (_) {
      throw StateError('无法保存 Agent Plan 专属 API Key，请检查系统安全存储');
    }
  }
}
