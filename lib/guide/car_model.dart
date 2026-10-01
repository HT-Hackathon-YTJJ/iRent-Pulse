import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// The low-poly car the orbit guide draws its outline from.
///
/// Built offline by `tool/aqua_outline/` and shipped as one JSON asset:
/// vertices in metres (x forward, y to the car's left, z up, ground at 0,
/// origin mid-length), triangles, and the detail lines — windows, door cuts,
/// lamps, grille, plates — that are drawn on the body rather than modelled
/// into it.
///
/// Everything the renderer needs per frame that does not depend on where the
/// camera is — face normals, centroids, the edge table and which edges are
/// creases — is worked out once here, so a frame is only projection,
/// rasterisation and sampling.
class CarModel {
  CarModel._({
    required this.vertices,
    required this.faces,
    required this.faceParts,
    required this.faceNormals,
    required this.faceCentres,
    required this.edges,
    required this.creases,
    required this.lines,
    required this.hull,
    required this.length,
    required this.width,
    required this.height,
  });

  static const String asset = 'assets/models/aqua_outline.json';

  /// Face part ids, as written by the exporter.
  static const int partBody = 0;
  static const int partWheel = 1;
  static const int partTrim = 2;
  static const int partWell = 3;

  /// Edges whose faces meet at more than this are drawn as lines even when
  /// both faces are in view: the arch lips, the bumper corners, the hood's
  /// shut line. Anything gentler is surface, not outline.
  static const double creaseDegrees = 32;

  /// xyz per vertex.
  final Float32List vertices;

  /// Three vertex indices per triangle.
  final Int32List faces;
  final Uint8List faceParts;

  /// Unit normal per face, pointing out of the car.
  final Float32List faceNormals;
  final Float32List faceCentres;

  /// Per edge: vertex a, vertex b, face 1, face 2 (-1 on an open boundary).
  final Int32List edges;

  /// 1 where the edge is a crease, see [creaseDegrees].
  final Uint8List creases;

  final List<DetailLine> lines;

  /// Vertices on the convex hull, roof antenna left out. A bounding box only
  /// ever touches these, so predicting the detector's box costs a few hundred
  /// projections instead of the whole mesh.
  final Int32List hull;

  final double length;
  final double width;
  final double height;

  int get vertexCount => vertices.length ~/ 3;
  int get faceCount => faces.length ~/ 3;
  int get edgeCount => edges.length ~/ 4;

  static Future<CarModel> load([String path = asset]) async {
    final text = await rootBundle.loadString(path);
    return CarModel.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  factory CarModel.fromJson(Map<String, dynamic> json) {
    final vertices = Float32List.fromList([
      for (final v in json['vertices'] as List) (v as num).toDouble(),
    ]);
    final faces = Int32List.fromList([
      for (final f in json['faces'] as List) (f as num).toInt(),
    ]);
    final parts = Uint8List.fromList([
      for (final p in json['face_parts'] as List) (p as num).toInt(),
    ]);
    final faceCount = faces.length ~/ 3;

    final normals = Float32List(faceCount * 3);
    final centres = Float32List(faceCount * 3);
    for (var f = 0; f < faceCount; f++) {
      final a = faces[f * 3] * 3, b = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      final ux = vertices[b] - vertices[a];
      final uy = vertices[b + 1] - vertices[a + 1];
      final uz = vertices[b + 2] - vertices[a + 2];
      final vx = vertices[c] - vertices[a];
      final vy = vertices[c + 1] - vertices[a + 1];
      final vz = vertices[c + 2] - vertices[a + 2];
      var nx = uy * vz - uz * vy;
      var ny = uz * vx - ux * vz;
      var nz = ux * vy - uy * vx;
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 1e-12) {
        nx /= len;
        ny /= len;
        nz /= len;
      }
      normals[f * 3] = nx;
      normals[f * 3 + 1] = ny;
      normals[f * 3 + 2] = nz;
      for (var k = 0; k < 3; k++) {
        centres[f * 3 + k] =
            (vertices[a + k] + vertices[b + k] + vertices[c + k]) / 3;
      }
    }

    // Edge table: each undirected edge once, with the two faces that share it.
    final vertexCount = vertices.length ~/ 3;
    final index = <int, int>{};
    final edgeList = <int>[];
    for (var f = 0; f < faceCount; f++) {
      for (var k = 0; k < 3; k++) {
        final p = faces[f * 3 + k];
        final q = faces[f * 3 + (k + 1) % 3];
        final lo = math.min(p, q), hi = math.max(p, q);
        final key = lo * vertexCount + hi;
        final at = index[key];
        if (at == null) {
          index[key] = edgeList.length;
          edgeList.addAll([lo, hi, f, -1]);
        } else if (edgeList[at + 3] < 0) {
          edgeList[at + 3] = f;
        }
      }
    }
    final edges = Int32List.fromList(edgeList);
    final creases = Uint8List(edges.length ~/ 4);
    final cosLimit = math.cos(creaseDegrees * math.pi / 180);
    for (var e = 0; e < creases.length; e++) {
      final f1 = edges[e * 4 + 2], f2 = edges[e * 4 + 3];
      if (f2 < 0) {
        creases[e] = 1;
        continue;
      }
      final dot =
          normals[f1 * 3] * normals[f2 * 3] +
          normals[f1 * 3 + 1] * normals[f2 * 3 + 1] +
          normals[f1 * 3 + 2] * normals[f2 * 3 + 2];
      if (dot < cosLimit) creases[e] = 1;
    }

    final lines = <DetailLine>[
      for (final raw in json['lines'] as List)
        DetailLine(
          name: (raw as Map<String, dynamic>)['name'] as String,
          points: Float32List.fromList([
            for (final v in raw['p'] as List) (v as num).toDouble(),
          ]),
          normals: Float32List.fromList([
            for (final v in raw['n'] as List) (v as num).toDouble(),
          ]),
        ),
    ];

    final hullJson = json['hull'] as List?;
    final hull = hullJson == null
        ? Int32List.fromList(List<int>.generate(vertexCount, (i) => i))
        : Int32List.fromList([for (final i in hullJson) (i as num).toInt()]);

    final dims = json['dimensions'] as Map<String, dynamic>;
    return CarModel._(
      vertices: vertices,
      faces: faces,
      faceParts: parts,
      faceNormals: normals,
      faceCentres: centres,
      edges: edges,
      creases: creases,
      lines: lines,
      hull: hull,
      length: (dims['length'] as num).toDouble(),
      width: (dims['width'] as num).toDouble(),
      height: (dims['height'] as num).toDouble(),
    );
  }
}

/// A line drawn on the body: a window edge, a lamp, a door cut.
///
/// Each point carries the surface normal under it, so a line on the far side
/// of the car can be dropped without consulting the depth buffer at all.
class DetailLine {
  const DetailLine({
    required this.name,
    required this.points,
    required this.normals,
  });

  final String name;
  final Float32List points;
  final Float32List normals;

  int get length => points.length ~/ 3;
}
