enum BaselineGroup {
  essential('Essential'),
  potentiallyFlexible('Potentially Flexible');

  const BaselineGroup(this.label);

  final String label;

  static BaselineGroup parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'committed') return BaselineGroup.essential;
    if (normalized == 'discretionary') return BaselineGroup.potentiallyFlexible;
    for (final group in BaselineGroup.values) {
      if (group.label.toLowerCase() == normalized ||
          group.name.toLowerCase() == normalized) {
        return group;
      }
    }
    throw FormatException('Unknown financial baseline group: $value');
  }
}

class FinancialBaselineMapping {
  const FinancialBaselineMapping({
    required this.merchantFingerprint,
    required this.group,
  });

  final String merchantFingerprint;
  final BaselineGroup group;

  String get id => '${group.name}:${merchantFingerprint.trim().toLowerCase()}';

  @override
  bool operator ==(Object other) =>
      other is FinancialBaselineMapping &&
      other.merchantFingerprint == merchantFingerprint &&
      other.group == group;

  @override
  int get hashCode => Object.hash(merchantFingerprint, group);

  Map<String, Object?> toJson() => {
    'merchant': merchantFingerprint,
    'group': group.label,
  };

  factory FinancialBaselineMapping.fromJson(Map<String, dynamic> json) =>
      FinancialBaselineMapping(
        merchantFingerprint:
            (json['merchant'] ?? json['merchantFingerprint'] ?? '').toString(),
        group: BaselineGroup.parse(json['group']),
      );

  static List<FinancialBaselineMapping> migrateStoredRows(Iterable rows) {
    final mappings = <FinancialBaselineMapping>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final json = Map<String, dynamic>.from(row);
      if (json['group']?.toString().trim().toLowerCase() == 'unclassified') {
        continue;
      }
      final group = BaselineGroup.parse(json['group']);
      final merchants = json['keywords'] is List
          ? (json['keywords'] as List).map((value) => value.toString())
          : [
              (json['merchant'] ?? json['merchantFingerprint'] ?? '')
                  .toString(),
            ];
      for (final merchant in merchants) {
        final fingerprint = merchant.trim();
        if (fingerprint.isEmpty) continue;
        final mapping = FinancialBaselineMapping(
          merchantFingerprint: fingerprint,
          group: group,
        );
        if (seen.add(mapping.id)) mappings.add(mapping);
      }
    }
    return List.unmodifiable(mappings);
  }
}

/// An unfinished account-local classification session and the committed state
/// it was based on, used to detect remote edits when restoring the draft.
class FinancialBaselineDraft {
  const FinancialBaselineDraft({
    required this.baseMappings,
    required this.draftMappings,
  });

  final List<FinancialBaselineMapping> baseMappings;
  final List<FinancialBaselineMapping> draftMappings;
}

class FinancialBaselineSyncBatch {
  const FinancialBaselineSyncBatch({
    required this.upserts,
    required this.removals,
  });
  final List<FinancialBaselineMapping> upserts;
  final List<String> removals;
}
