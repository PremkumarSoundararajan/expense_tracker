import 'transaction.dart';

enum SpendingTargetType { category, merchant }

/// A dated definition. Later definitions for the same scope supersede this one
/// from their effective date; earlier definitions remain available for history.
class SpendingTarget {
  const SpendingTarget({
    required this.id,
    required this.type,
    required this.scopeId,
    required this.name,
    required this.historicalMonthlyAverage,
    required this.reductionPercentage,
    required this.monthlyAmount,
    required this.effectiveDate,
    required this.active,
    required this.updatedAt,
  });
  final String id;
  final SpendingTargetType type;
  final String scopeId;
  final String name;
  final double historicalMonthlyAverage;
  final double reductionPercentage;
  final double monthlyAmount;
  final DateTime effectiveDate;
  final bool active;
  final DateTime updatedAt;
  String get scopeKey => '${type.name}:$scopeId';

  factory SpendingTarget.activate({
    required SpendingTargetType type,
    required String scopeId,
    required String name,
    required double average,
    required double percentage,
    required DateTime effectiveDate,
    DateTime? now,
  }) {
    if (!average.isFinite ||
        average < 0 ||
        !percentage.isFinite ||
        percentage < 0 ||
        percentage > 100 ||
        scopeId.trim().isEmpty) {
      throw ArgumentError('Invalid spending target.');
    }
    final date = DateTime(
      effectiveDate.year,
      effectiveDate.month,
      effectiveDate.day,
    );
    return SpendingTarget(
      id: '${type.name}:$scopeId@${date.toIso8601String().split('T').first}',
      type: type,
      scopeId: scopeId,
      name: name,
      historicalMonthlyAverage: average,
      reductionPercentage: percentage,
      monthlyAmount: average * (1 - percentage / 100),
      effectiveDate: date,
      active: true,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
  }

  SpendingTarget revise({
    required DateTime effectiveDate,
    double? amount,
    bool? active,
    DateTime? now,
  }) {
    final date = DateTime(
      effectiveDate.year,
      effectiveDate.month,
      effectiveDate.day,
    );
    final value = amount ?? monthlyAmount;
    if (!value.isFinite || value < 0) {
      throw ArgumentError('Invalid monthly amount.');
    }
    return SpendingTarget(
      id: '${type.name}:$scopeId@${date.toIso8601String().split('T').first}',
      type: type,
      scopeId: scopeId,
      name: name,
      historicalMonthlyAverage: historicalMonthlyAverage,
      reductionPercentage: historicalMonthlyAverage == 0
          ? 0
          : (1 - value / historicalMonthlyAverage) * 100,
      monthlyAmount: value,
      effectiveDate: date,
      active: active ?? this.active,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'scopeId': scopeId,
    'name': name,
    'average': historicalMonthlyAverage,
    'percentage': reductionPercentage,
    'amount': monthlyAmount,
    'effectiveDate': effectiveDate.toIso8601String().split('T').first,
    'active': active,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory SpendingTarget.fromJson(Map<String, dynamic> json) {
    final target = SpendingTarget(
      id: json['id'] as String,
      type: SpendingTargetType.values.byName(json['type'] as String),
      scopeId: json['scopeId'] as String,
      name: json['name'] as String,
      historicalMonthlyAverage: (json['average'] as num).toDouble(),
      reductionPercentage: (json['percentage'] as num).toDouble(),
      monthlyAmount: (json['amount'] as num).toDouble(),
      effectiveDate: DateTime.parse(json['effectiveDate'] as String),
      active: json['active'] == true,
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
    if (target.id.isEmpty ||
        target.scopeId.isEmpty ||
        !target.monthlyAmount.isFinite ||
        target.monthlyAmount < 0) {
      throw const FormatException('Invalid spending target record.');
    }
    return target;
  }
}

bool sameLedgerTransaction(Transaction a, Transaction b) =>
    a.id != null && b.id != null ? a.id == b.id : identical(a, b);
