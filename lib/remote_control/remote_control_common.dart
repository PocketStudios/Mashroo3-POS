String buildRemoteControlIdentifier({
  String? selectedCustomerDisplayLabel,
  int? selectedCustomerApiId,
  String? maskedApiKey,
}) {
  final String? customerLabel = _normalizeIdentifier(selectedCustomerDisplayLabel);
  if (customerLabel != null && customerLabel.isNotEmpty) {
    return customerLabel;
  }

  if (selectedCustomerApiId != null && selectedCustomerApiId > 0) {
    return 'customer-$selectedCustomerApiId';
  }

  final String? key = _normalizeIdentifier(maskedApiKey);
  if (key != null && key.isNotEmpty) {
    return key;
  }

  return 'pos-terminal';
}

List<String> buildRemoteControlPrimaryArgs(String identifier) {
  return <String>[
    '--connect',
    '--name',
    identifier,
    '--description',
    identifier,
  ];
}

List<String> buildRemoteControlFallbackArgs() {
  return const <String>['--connect'];
}

String? _normalizeIdentifier(String? value) {
  if (value == null) return null;
  final String normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return null;
  if (normalized.length <= 80) return normalized;
  return normalized.substring(0, 80);
}
