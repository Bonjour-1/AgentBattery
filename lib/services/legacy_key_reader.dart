/// Compatibility stub retained for source compatibility in clean builds.
///
/// Clean distributions never import keys from a creator's machine.
class LegacyKeyReader {
  Future<Map<String, String>> read() async => const {};
}
