// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// A small value used as the default epsilon for comparisons.
const epsilon = 1e-10;

/// Some utility methods for working with [Vector2]
extension Vector2Utils on Vector2 {
  /// Converts this [Vector2] to an [Offset].
  Offset get offset => Offset(x, y);

  /// Converts this [Vector2] to a [Vector3]. The z component is set to `0`.
  Vector3 get vector3 => Vector3(x, y, 0);
}

/// Some utility methods for working with [Offset]
extension VectorFromOffset on Offset {
  /// Converts this [Offset] to a [Vector2].
  Vector2 get vector2 => Vector2(dx, dy);

  /// Converts this [Offset] to a [Vector3]. The z component is set to `0`.
  Vector3 get vector3 => Vector3(dx, dy, 0);
}

/// Some utility methods for working with [Vector3]
extension Vector2FromVector3 on Vector3 {
  /// Converts this [Vector3] to a [Vector2]. The z component is discarded.
  Vector2 get vector2 => Vector2(x, y);
}

/// Some utility methods for working with [Aabb2].
extension Aabb2Utils on Aabb2 {
  double get width => max.x - min.x;
  double get height => max.y - min.y;

  /// Returns a list of the vertices of this [Aabb2].
  List<Vector2> get vertices => [
        Vector2(this.min.x, this.min.y),
        Vector2(this.max.x, this.min.y),
        Vector2(this.max.x, this.max.y),
        Vector2(this.min.x, this.max.y),
      ];

  /// Converts this [Aabb2] to a [Rect].
  Rect get rect => Rect.fromLTRB(
        this.min.x,
        this.min.y,
        this.max.x,
        this.max.y,
      );

  Polygon2 get polygon => Polygon2(vertices);
}

/// Some utility methods for working with [Rect] and [Aabb2].
extension RectToAabb2 on Rect {
  /// Converts this [Rect] to an [Aabb2].
  Aabb2 get aabb2 => Aabb2.minMax(
        Vector2(left, top),
        Vector2(right, bottom),
      );
}

extension RectTransform on Rect {
  Rect transform(Matrix4 t) {
    return MatrixUtils.transformRect(t, this);
  }
}

extension SizeArea on Size {
  double get area => width * height;
}

class LineSegment2 {
  LineSegment2(this.point0, this.point1);

  final Vector2 point0;
  final Vector2 point1;

  /// Returns an intersection point between this and [other], if exists
  Vector2? intersectsWithLineSegment(LineSegment2 other) {
    final p = point0;
    final r = point1 - point0;

    final q = other.point0;
    final s = other.point1 - other.point0;

    final cross = r.cross(s);

    final _t = (q - p).cross(s);
    final t = _t / cross;

    final _u = (q - p).cross(r);
    final u = _u / cross;

    final crossAbs = cross.abs();

    if (crossAbs < epsilon && _u.abs() < epsilon) {
      // Collinear.
      return null;
    }

    if (crossAbs < epsilon && _u.abs() >= epsilon) {
      // Parallel, no intersection
      return null;
    }

    if (crossAbs >= epsilon && t > 0 && t < 1 && u > 0 && u < 1) {
      // Intersection
      return p + r * t;
    }

    // No intersection
    return null;
  }

  bool containsPoint(Vector2 point) {
    final d0 = point1 - point0;
    final d1 = point - point0;

    final dot = d0.dot(d1);
    return dot < epsilon;
  }
}

class Polygon2 {
  const Polygon2(this.vertices);

  final List<Vector2> vertices;

  Aabb2 get boundingBox {
    final minX = vertices.map((v) => v.x).reduce(math.min);
    final maxX = vertices.map((v) => v.x).reduce(math.max);
    final minY = vertices.map((v) => v.y).reduce(math.min);
    final maxY = vertices.map((v) => v.y).reduce(math.max);

    return Aabb2.minMax(
      Vector2(minX, minY),
      Vector2(maxX, maxY),
    );
  }

  Polygon2 shift(Vector2 d) {
    return Polygon2(vertices.map((v) => v + d).toList());
  }

  List<LineSegment2> get lineSegments {
    final segments = <LineSegment2>[];

    for (var i = 0; i < vertices.length; i++) {
      final j = (i + 1) % vertices.length;
      segments.add(LineSegment2(vertices[i], vertices[j]));
    }

    return segments;
  }

  /// Computes the convex hull of this polygon
  Polygon2 computeConvexHull() {
    final vertices = this.vertices.toList();

    // Sort vertices by x coordinate
    vertices.sort((a, b) => a.x.compareTo(b.x));

    // Compute the upper hull
    final upper = <Vector2>[];
    for (final p in vertices) {
      while (upper.length >= 2) {
        final q = upper[upper.length - 1];
        final r = upper[upper.length - 2];

        if ((q - r).cross(p - r) <= 0) {
          upper.removeLast();
        } else {
          break;
        }
      }

      upper.add(p);
    }

    // Compute the lower hull
    final lower = <Vector2>[];
    for (var i = vertices.length - 1; i >= 0; i--) {
      final p = vertices[i];
      while (lower.length >= 2) {
        final q = lower[lower.length - 1];
        final r = lower[lower.length - 2];

        if ((q - r).cross(p - r) <= 0) {
          lower.removeLast();
        } else {
          break;
        }
      }

      lower.add(p);
    }

    // Remove the last point of each list, since it's the same as the first
    upper.removeLast();
    lower.removeLast();

    // Concatenate the two lists
    final hull = <Vector2>[];
    hull.addAll(upper);
    hull.addAll(lower);

    return Polygon2(hull);
  }

  /// Computes the area of this polygon
  double computeArea() {
    var area = 0.0;

    for (var i = 0; i < vertices.length; i++) {
      final j = (i + 1) % vertices.length;

      final p = vertices[i];
      final q = vertices[j];

      area += p.cross(q);
    }

    return area / 2;
  }
}

/// A 2D quadrilateral.
class Quad2 {
  /// Creates a [Quad2] from the given points.
  Quad2(this.point0, this.point1, this.point2, this.point3);

  /// Creates a [Quad2] from a given [size]. The top-left corner is at `(0, 0)`.
  Quad2.fromSize(Size size)
      : this(
          Vector2(0, size.height),
          Vector2(size.width, size.height),
          Vector2(size.width, 0),
          Vector2(0, 0),
        );

  final Vector2 point0;
  final Vector2 point1;
  final Vector2 point2;
  final Vector2 point3;

  /// Returns the bounding box of this [Quad2].
  Aabb2 get boundingBox {
    final xMin = vertices.map((v) => v.x).reduce(math.min);
    final xMax = vertices.map((v) => v.x).reduce(math.max);
    final yMin = vertices.map((v) => v.y).reduce(math.min);
    final yMax = vertices.map((v) => v.y).reduce(math.max);

    return Aabb2.minMax(
      Vector2(xMin, yMin),
      Vector2(xMax, yMax),
    );
  }

  /// Returns a list of the vertices of this [Quad2].
  List<Vector2> get vertices => [point0, point1, point2, point3];

  Triangle? _cachedTri1;
  Triangle get tri1 {
    if (_cachedTri1 != null) return _cachedTri1!;

    return _cachedTri1 = Triangle.points(
      point0.vector3,
      point1.vector3,
      point2.vector3,
    );
  }

  Triangle? _cachedTri2;
  Triangle get tri2 {
    if (_cachedTri2 != null) return _cachedTri2!;

    return _cachedTri2 = Triangle.points(
      point0.vector3,
      point2.vector3,
      point3.vector3,
    );
  }

  /// Whether this [Quad2] contains the given [point].
  bool containsPoint(Vector2 point) {
    if (tri1.containsPoint(point.vector3)) return true;
    if (tri2.containsPoint(point.vector3)) return true;

    return false;
  }

  /// Transforms this [Quad2] by the given transformation matrix.
  Quad2 transform(Matrix4 t) {
    return Quad2(
      t.perspectiveTransform(point0.vector3).vector2,
      t.perspectiveTransform(point1.vector3).vector2,
      t.perspectiveTransform(point2.vector3).vector2,
      t.perspectiveTransform(point3.vector3).vector2,
    );
  }

  /// Computes the signed area of this [Quad2] using the shoelace formula.
  double get area {
    var area = 0.0;

    for (var i = 0; i < 4; i++) {
      var j = (i + 1) % 4;

      area += vertices[i].x * vertices[j].y;
      area -= vertices[i].y * vertices[j].x;
    }

    return area / 2;
  }

  /// Returns a [Path] representing this [Quad2].
  Path get path {
    final path = Path();

    path.moveTo(point0.x, point0.y);
    path.lineTo(point1.x, point1.y);
    path.lineTo(point2.x, point2.y);
    path.lineTo(point3.x, point3.y);

    path.close();
    return path;
  }

  List<LineSegment2> get lineSegments => [
        LineSegment2(point0, point1),
        LineSegment2(point1, point2),
        LineSegment2(point2, point3),
        LineSegment2(point3, point0),
      ];

  Vector2? intersectsWithLineSegment(LineSegment2 lineSegment) {
    for (final segment in lineSegments) {
      final intersection = segment.intersectsWithLineSegment(lineSegment);
      if (intersection != null) return intersection;
    }

    return null;
  }
}

class Triangle {
  Triangle.points(this.point0, this.point1, this.point2);

  final Vector3 point0;
  final Vector3 point1;
  final Vector3 point2;
}

/// Some utility methods for working with [Triangle].
extension TriangleContainsPoint on Triangle {
  /// Whether this [Triangle] contains the given [point].
  bool containsPoint(Vector3 point) {
    final a = point0 - point;
    final b = point1 - point;
    final c = point2 - point;

    final u = b.cross(c);
    final v = c.cross(a);
    final w = a.cross(b);

    if (u.dot(v) < -epsilon) {
      return false;
    }

    if (u.dot(w) < -epsilon) {
      return false;
    }

    return true;
  }
}

/// Linearly interpolates between two [Matrix4]s using [Matrix4Tween].
Matrix4 lerpMatrix4(Matrix4? a, Matrix4? b, double t) {
  return Matrix4Tween(begin: a, end: b).lerp(t);
}

/// Computes an adjugate matrix.
Matrix3 matrix3Adj(Matrix3 m) {
  return Matrix3(
    m[4] * m[8] - m[5] * m[7],
    m[2] * m[7] - m[1] * m[8],
    m[1] * m[5] - m[2] * m[4],
    m[5] * m[6] - m[3] * m[8],
    m[0] * m[8] - m[2] * m[6],
    m[2] * m[3] - m[0] * m[5],
    m[3] * m[7] - m[4] * m[6],
    m[1] * m[6] - m[0] * m[7],
    m[0] * m[4] - m[1] * m[3],
  );
}
