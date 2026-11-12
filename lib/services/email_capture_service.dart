import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'worker_csv_sync_service.dart';

const emailCurrencies = [
  'USD',
  'CAD',
  'AUD',
  'EUR',
  'GBP',
  'INR',
  'SGD',
  'MYR',
];

class EmailExpenseCandidate {
  const EmailExpenseCandidate({
    required this.id,
    required this.accountId,
    required this.merchant,
    required this.amount,
    required this.currency,
    required this.date,
    this.subject = '',
    this.sender = '',
    this.excerpt = '',
    this.dateSource = '',
    this.merchantNeedsReview = false,
    this.importUncertain = false,
    this.category = 'Uncategorized',
    this.categoryId,
    this.expenseType = 'Unknown',
    this.essentiality = 'Unclassified',
    this.classificationEdited = false,
    this.possibleDuplicate = false,
    this.importAnyway = false,
    this.currencyNeedsReview = false,
    this.reviewBlocked = false,
    this.needsReview = false,
    this.reviewReason = '',
    this.manualReviewConfirmed = false,
    this.amountWarning = '',
    this.dateNeedsReview = false,
    this.amountIsSuggestion = false,
    this.amountCandidates = const [],
  });
  final String id,
      accountId,
      merchant,
      currency,
      date,
      subject,
      sender,
      excerpt,
      dateSource;
  final double amount;
  final bool merchantNeedsReview;
  final bool importUncertain;
  final String category, expenseType, essentiality;
  final String? categoryId;
  final bool classificationEdited, possibleDuplicate, importAnyway;
  final bool currencyNeedsReview;
  final bool reviewBlocked;
  final bool needsReview, manualReviewConfirmed, dateNeedsReview;
  final String reviewReason, amountWarning;
  final bool amountIsSuggestion;
  final List<Map<String, dynamic>> amountCandidates;
  bool get amountMissing => needsReview && amount <= 0;
  factory EmailExpenseCandidate.fromJson(Map<String, dynamic> json) =>
      EmailExpenseCandidate(
        id: json['id'] as String,
        accountId: json['accountId'] as String,
        merchant: json['merchant'] as String,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String,
        date: json['date'] as String,
        subject: json['subject'] as String? ?? '',
        sender: json['sender'] as String? ?? '',
        excerpt: json['excerpt'] as String? ?? '',
        dateSource: json['dateSource'] as String? ?? '',
        merchantNeedsReview: json['merchantNeedsReview'] == true,
        importUncertain: json['importUncertain'] == true,
        currencyNeedsReview: json['currencyNeedsReview'] == true,
        reviewBlocked: json['reviewBlocked'] == true,
        needsReview: json['needsReview'] == true,
        reviewReason: json['reviewReason'] as String? ?? '',
        amountWarning: json['amountWarning'] as String? ?? '',
        dateNeedsReview: json['dateNeedsReview'] == true,
        amountIsSuggestion: json['amountIsSuggestion'] == true,
        amountCandidates: (json['amountCandidates'] as List? ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList(),
      );
  EmailExpenseCandidate edited({
    required String merchant,
    required double amount,
    required String date,
    required String currency,
    bool manualReviewConfirmed = false,
  }) => EmailExpenseCandidate(
    id: id,
    accountId: accountId,
    merchant: merchant,
    amount: amount,
    date: date,
    currency: currency,
    subject: subject,
    sender: sender,
    excerpt: excerpt,
    dateSource: dateSource,
    merchantNeedsReview: false,
    importUncertain: importUncertain,
    category: category,
    categoryId: categoryId,
    expenseType: expenseType,
    essentiality: essentiality,
    classificationEdited: classificationEdited,
    possibleDuplicate: possibleDuplicate,
    importAnyway: false,
    currencyNeedsReview: currencyNeedsReview,
    reviewBlocked: reviewBlocked,
    needsReview: needsReview,
    reviewReason: reviewReason,
    manualReviewConfirmed: this.manualReviewConfirmed || manualReviewConfirmed,
    amountWarning: amountWarning,
    dateNeedsReview: dateNeedsReview,
    amountIsSuggestion: manualReviewConfirmed ? false : amountIsSuggestion,
    amountCandidates: amountCandidates,
  );
  EmailExpenseCandidate classified({
    String? category,
    String? categoryId,
    String? expenseType,
    String? essentiality,
    bool? possibleDuplicate,
    bool? importAnyway,
    bool edited = true,
  }) => EmailExpenseCandidate(
    id: id,
    accountId: accountId,
    merchant: merchant,
    amount: amount,
    currency: currency,
    date: date,
    subject: subject,
    sender: sender,
    excerpt: excerpt,
    dateSource: dateSource,
    merchantNeedsReview: merchantNeedsReview,
    importUncertain: importUncertain,
    category: category ?? this.category,
    categoryId: category != null ? categoryId : this.categoryId,
    expenseType: expenseType ?? this.expenseType,
    essentiality: essentiality ?? this.essentiality,
    classificationEdited: edited || classificationEdited,
    possibleDuplicate: possibleDuplicate ?? this.possibleDuplicate,
    importAnyway: importAnyway ?? this.importAnyway,
    currencyNeedsReview: currencyNeedsReview,
    reviewBlocked: reviewBlocked,
    needsReview: needsReview,
    reviewReason: reviewReason,
    manualReviewConfirmed: manualReviewConfirmed,
    amountWarning: amountWarning,
    dateNeedsReview: dateNeedsReview,
    amountIsSuggestion: amountIsSuggestion,
    amountCandidates: amountCandidates,
  );
}

class EmailCaptureService {
  EmailCaptureService({
    required this.accessToken,
    http.Client? client,
    Uri? endpoint,
    Future<String> Function()? timezoneName,
  }) : _client = client ?? http.Client(),
       _endpoint = endpoint ?? WorkerCsvSyncService.endpoint,
       _timezoneName =
           timezoneName ??
           (() async => (await FlutterTimezone.getLocalTimezone()).identifier);
  final Future<String> Function() accessToken;
  final http.Client _client;
  final Uri _endpoint;
  final Future<String> Function() _timezoneName;
  Future<Map<String, dynamic>> request(
    String action, {
    Map<String, Object?>? data,
  }) async {
    final token = await accessToken();
    if (data != null &&
        (action == 'connect' || action == 'scan' || action == 'scan/start')) {
      try {
        data = {...data, 'timezone': await _timezoneName()};
      } catch (_) {
        throw StateError(
          'Could not determine your timezone. Retry after reopening the app.',
        );
      }
    }
    final url = _endpoint.replace(
      path: '/email/$action',
      query: null,
      fragment: null,
    );
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final readOnly = action == 'status' || action == 'scan/progress';
    late http.Response response;
    // Retry only the read-only inbox refresh, never an uncertain Sheets write.
    for (var attempt = 0; ; attempt++) {
      try {
        response =
            await (data == null
                    ? _client.get(url, headers: headers)
                    : _client.post(
                        url,
                        headers: headers,
                        body: jsonEncode(data),
                      ))
                .timeout(Duration(seconds: readOnly ? 15 : 180));
        if (readOnly && response.statusCode >= 500 && attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
          continue;
        }
        break;
      } on http.ClientException {
        if (readOnly && attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
          continue;
        }
        throw StateError(
          action == 'approve'
              ? 'Could not confirm the import response. Check your Sheet and refresh before retrying.'
              : 'Could not reach the email service. Saved results are kept. Tap Refresh to retry.',
        );
      } on TimeoutException {
        if (readOnly && attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
          continue;
        }
        throw StateError(
          'The email service took too long to respond. Saved results are kept. Refresh before retrying.',
        );
      }
    }
    Map<String, dynamic> result;
    try {
      result = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError(
        response.statusCode >= 500
            ? 'Email service interrupted (HTTP ${response.statusCode}). Saved results are kept. Resume the scan.'
            : 'Unexpected email-service response (HTTP ${response.statusCode}). Refresh and retry.',
      );
    }
    if (result['error'] == 'Missing X-Spreadsheet-ID header') {
      throw StateError(
        'The email API is missing from this server. Deploy the updated Worker to ${_endpoint.host}.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw StateError(
        result['error']?.toString() ?? 'Email capture is unavailable.',
      );
    if (action == 'status' &&
        (result['accounts'] is! List || result['items'] is! List))
      throw StateError(
        'Update and configure the Worker before using email capture.',
      );
    return result;
  }

  Future<Map<String, dynamic>> status() => request('status');
  void close() => _client.close();
}

String emailReviewReason(String reason) {
  if (reason.startsWith('rejected_keyword:'))
    return 'The email contains “${reason.split(':').last}”. Confirm it describes a completed expense.';
  return const {
        'no_completion_phrase':
            'No clear confirmation that a payment completed.',
        'amount_conflict': 'The highest-priority payment amounts conflict.',
        'no_amount': 'No positive, eligible payment amount was found.',
        'unsupported_amount_format':
            'The amount or currency format cannot be read safely.',
        'unreadable_content': 'No readable email text was available. The receipt may be an image or attachment.',
        'rejected_transfer': 'This may be a transfer or credit-card repayment rather than a purchase.',
        'invalid_date': 'The payment date could not be read safely.',
        'date_ambiguous': 'The payment date needs verification.',
      }[reason] ??
      'Check the original email and enter the correct expense details.';
}
