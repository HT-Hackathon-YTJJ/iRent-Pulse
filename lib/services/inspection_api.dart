import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for the `api/` service — L1 快篩、L2 影像確認、L3 決策派工.
///
/// Only L1 is blocking: the driver stands at the car waiting for it, one call
/// per photo, reported as each one lands. Everything after the return button is
/// [finalize], which the driver never waits for.
///
/// Point it somewhere else with
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`.
class InspectionApi {
  InspectionApi({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const String _configured = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_configured.isNotEmpty) return _configured;
    // The Android emulator reaches the host loopback through 10.0.2.2; a real
    // handset needs the LAN address passed in with --dart-define.
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// True when the service answers. Checked once when the flow opens so the
  /// screen can fall back to the scripted demo instead of hanging on a socket.
  Future<bool> reachable({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final response = await _client.get(_uri('/healthz')).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// One photo through L1. Blocking by design — this is the wait the whole L0
  /// layer exists to make rare.
  Future<L1Photo> screen({
    required File photo,
    required String orderId,
    required String carNo,
    required String slot,
    required String stage,
    required Map<String, Object?> l0,
    bool retake = false,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/v1/l1/screen'))
      ..fields['order_id'] = orderId
      ..fields['car_no'] = carNo
      ..fields['slot'] = slot
      ..fields['stage'] = stage
      ..fields['l0'] = jsonEncode(l0)
      ..fields['retake'] = retake.toString()
      ..files.add(await http.MultipartFile.fromPath('file', photo.path));

    final streamed = await _client.send(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw InspectionApiException('L1 ${streamed.statusCode}: $body');
    }
    return L1Photo.fromJson(
      jsonDecode(body) as Map<String, Object?>,
      slot: slot,
    );
  }

  /// L2 + L3, once the driver has walked away.
  Future<L3Decision> finalize({
    required String orderId,
    required String carNo,
  }) async {
    final response = await _client.post(
      _uri('/v1/returns/finalize'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'order_id': orderId, 'car_no': carNo}),
    );
    if (response.statusCode != 200) {
      throw InspectionApiException(
        'finalize ${response.statusCode}: ${response.body}',
      );
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    return L3Decision.fromJson(json);
  }

  // -- 車輛歷程留言板 --------------------------------------------------------
  //
  // The board is L2's second source of evidence. It answers 「是這趟造成的嗎」
  // in the case a pickup photo cannot: the previous driver wrote down the dent
  // before this driver ever saw the car. `api/app/board.py` has the full
  // argument, including the rule that a note may only ever move a finding
  // towards 既有 — never towards a charge.
  //
  // The board already exists in the app: it is the 租用履歷 tab of the booking
  // sheet, `VehicleProfile.reviews`. Those entries are local demo data, so
  // [ReturnSession.publishBoard] pushes them to the service when a live return
  // starts — which is what makes the sentence the driver read on the booking
  // screen the same sentence L2 weighs half an hour later.
  //
  // What is still missing is the *write* half: there is no screen where a
  // driver types a note. [addNote] is here for it, and 還車完成 is where it
  // goes — the moment somebody has just walked around the car is the moment
  // they know what is wrong with it.

  /// What the board already said about this car.
  ///
  /// [before] is an ISO-8601 cut-off. Pass the moment the rental started to get
  /// what L2 will see; omit it to show the driver everything.
  Future<List<BoardNote>> notes({
    required String carNo,
    String? before,
  }) async {
    final uri = _uri('/v1/cars/$carNo/notes').replace(
      queryParameters: before == null ? null : {'before': before},
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw InspectionApiException(
        'notes ${response.statusCode}: ${response.body}',
      );
    }
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<Object?>;
    return [
      for (final item in list)
        BoardNote.fromJson(item as Map<String, Object?>),
    ];
  }

  /// Write one entry. [part] and [type] are optional — the service parses them
  /// out of [text] when the UI has not tagged them.
  Future<BoardNote> addNote({
    required String carNo,
    required String text,
    String? orderId,
    String? createdAt,
    String? part,
    String? type,
  }) async {
    final response = await _client.post(
      _uri('/v1/cars/$carNo/notes'),
      headers: const {'content-type': 'application/json; charset=utf-8'},
      body: utf8.encode(
        jsonEncode({
          'text': text,
          'author': 'user',
          'created_at': ?createdAt,
          'order_id': ?orderId,
          'part': ?part,
          'type': ?type,
        }),
      ),
    );
    if (response.statusCode != 200) {
      throw InspectionApiException(
        'addNote ${response.statusCode}: ${response.body}',
      );
    }
    return BoardNote.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>,
    );
  }

  void close() => _client.close();
}

/// One entry on a car's 車輛歷程留言板.
class BoardNote {
  const BoardNote({
    required this.noteId,
    required this.text,
    required this.author,
    required this.createdAt,
    this.part,
    this.type,
    this.confirmed = false,
  });

  final String noteId;
  final String text;
  final String author; // user / staff / system
  final String createdAt;

  /// Filled in when the note named a panel the vision layers also speak of.
  /// Null is normal — most notes are not about damage.
  final String? part;
  final String? type;

  /// True once 客服 has looked. Only a confirmed note is allowed to contradict
  /// a pickup photograph, and even then it asks for a human rather than
  /// deciding.
  final bool confirmed;

  /// True when this note can actually take part in an L2 comparison.
  bool get actionable => part != null && type != null;

  factory BoardNote.fromJson(Map<String, Object?> json) => BoardNote(
    noteId: json['note_id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    author: json['author'] as String? ?? 'user',
    createdAt: json['created_at'] as String? ?? '',
    part: json['part'] as String?,
    type: json['type'] as String?,
    confirmed: json['confirmed'] as bool? ?? false,
  );
}

class InspectionApiException implements Exception {
  InspectionApiException(this.message);
  final String message;
  @override
  String toString() => 'InspectionApiException: $message';
}

// ---------------------------------------------------------------------------

/// L1's verdict on one photo.
///
/// Note what the driver-facing screens are allowed to read: [assessable],
/// [retakeRequired], [cleanliness]. The damage fields are parsed because the
/// ops view needs them, but showing them at the car is the trust failure the
/// spec is built to avoid — an unreviewed AI accusing someone in an empty car
/// park.
class L1Photo {
  const L1Photo({
    required this.photoId,
    required this.slot,
    required this.assessable,
    this.assessableReason,
    this.retakeRequired = false,
    this.retakeHint,
    this.coverageAdequate = true,
    this.coverageHint,
    this.angleVerified,
    this.angleMismatch = false,
    this.cleanliness,
    this.items = const [],
    this.damageCount = 0,
    this.maxSeverity = 'none',
    this.qualityForced = false,
    this.latencyMs = 0,
    this.costUsd = 0,
    this.error,
  });

  final String photoId;
  final String slot;
  final bool assessable;
  final String? assessableReason;
  final bool retakeRequired;
  final String? retakeHint;
  final bool coverageAdequate;
  final String? coverageHint;
  final String? angleVerified;
  final bool angleMismatch;
  final String? cleanliness;
  final List<String> items;
  final int damageCount;
  final String maxSeverity;
  final bool qualityForced;
  final int latencyMs;
  final double costUsd;
  final String? error;

  bool get failed => error != null;

  factory L1Photo.fromJson(Map<String, Object?> json, {required String slot}) {
    final damages = json['observed_damages'] as List<Object?>?;
    return L1Photo(
      photoId: json['photo_id'] as String? ?? '',
      slot: json['slot'] as String? ?? slot,
      assessable: json['assessable'] as bool? ?? true,
      assessableReason: json['assessable_reason'] as String?,
      retakeRequired: json['retake_required'] as bool? ?? false,
      retakeHint: json['retake_hint'] as String?,
      coverageAdequate: json['coverage_adequate'] as bool? ?? true,
      coverageHint: json['coverage_hint'] as String?,
      angleVerified: json['angle_verified'] as String?,
      angleMismatch: json['angle_mismatch'] as bool? ?? false,
      cleanliness: json['cleanliness'] as String?,
      items: (json['items'] as List<Object?>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      damageCount: damages?.length ?? 0,
      maxSeverity: json['max_severity'] as String? ?? 'none',
      qualityForced: json['quality_forced'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0,
      error: json['error'] as String?,
    );
  }
}

/// What L3 did with the car. Never rendered at the counter.
class L3Decision {
  const L3Decision({
    required this.status,
    required this.rule,
    this.reason,
    this.queues = const [],
    this.explain = '',
    this.notifyUser,
    this.costUsd = 0,
  });

  final String status; // 可租用 / 待清潔 / 停用
  final int rule;
  final String? reason;
  final List<String> queues;
  final String explain;
  final String? notifyUser;
  final double costUsd;

  factory L3Decision.fromJson(Map<String, Object?> json) {
    final decision = json['decision'] as Map<String, Object?>? ?? json;
    return L3Decision(
      status: decision['status'] as String? ?? '可租用',
      rule: (decision['rule'] as num?)?.toInt() ?? 0,
      reason: decision['reason'] as String?,
      queues: (decision['queues'] as List<Object?>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      explain: decision['explain'] as String? ?? '',
      notifyUser: decision['notify_user'] as String?,
      costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0,
    );
  }
}
