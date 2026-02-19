// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:vector_math/vector_math_64.dart';
import 'package:cassowary/cassowary.dart';
import 'geometry.dart';

bool _shouldSolve(Polygon2 polygon, Quad2 quad) {
  // Check if we even need to solve anything first.
  final verticesNotInQuad = <Vector2>[];

  for (final v in polygon.vertices) {
    if (!quad.containsPoint(v)) {
      verticesNotInQuad.add(v);
    }
  }

  return verticesNotInQuad.isNotEmpty;
}

Quad2 _normalizeQuad(Quad2 quad) {
  // Check if the quad is clockwise or counter-clockwise, and force it to be
  // clockwise.
  if (quad.area > 0.0) {
    return Quad2(
      quad.point0,
      quad.point3,
      quad.point2,
      quad.point1,
    );
  } else {
    return quad;
  }
}

class FitPolygonInQuadSolver {
  // TODO: Solve for polygon's convex hull instead of the polygon itself.
  static Aabb2 solve(Polygon2 polygon, Quad2 quad, {bool enableResize = false}) {
    // If all vertices are in the quad, we don't need to do anything.
    if (!enableResize && !_shouldSolve(polygon, quad)) {
      return polygon.boundingBox;
    }

    final normalizedQuad = _normalizeQuad(quad);

    // Use the Dart implementation
    return _fitPolygonInQuadImpl(polygon, normalizedQuad, enableResize: enableResize);
  }
}

void _addBasicConstraints(
  Solver solver,
  Polygon2 polygon,
  Quad2 normalizedQuad,
  Param xNew,
  Param yNew,
  Param alphaX,
  Param? alphaY, {
  bool enableResize = false,
}) {
  final aabb = polygon.boundingBox;

  final quadMin = normalizedQuad.boundingBox.min;
  final quadMax = normalizedQuad.boundingBox.max;

  final xMin = quadMin.x;
  final xMax = quadMax.x;
  final yMin = quadMin.y;
  final yMax = quadMax.y;

  solver.addConstraints([
    xNew >= cm(xMin),
    xNew <= cm(xMax),
    yNew >= cm(yMin),
    yNew <= cm(yMax),
    alphaX >= cm(0.0),
  ]);

  if (!enableResize) {
    solver.addConstraint(alphaX <= cm(1.0));
  }

  if (alphaY != null) {
    solver.addConstraint(alphaY >= cm(0.0));
    if (!enableResize) {
      solver.addConstraint(alphaY <= cm(1.0));
    }
  }

  final dv = polygon.vertices.map((v) => v - aabb.min).toList();

  // Quadrilateral fitting constraints
  for (final d in dv) {
    final dx = d.x;
    final dy = d.y;

    for (final i in [0, 1, 2, 3]) {
      final j = (i + 1) % 4;

      final quadI = normalizedQuad.vertices[i];
      final quadJ = normalizedQuad.vertices[j];

      final _alphaY = alphaY ?? alphaX;

      final constraint = cm(quadJ.x - quadI.x) *
                  (yNew + _alphaY * cm(dy) - cm(quadI.y)) -
              cm(quadJ.y - quadI.y) * (xNew + alphaX * cm(dx) - cm(quadI.x)) <=
          cm(0);

      solver.addConstraint(constraint);
    }
  }
}

Aabb2 _fitPolygonInQuadImpl(Polygon2 polygon, Quad2 normalizedQuad, {bool enableResize = false}) {
  final aabb = polygon.boundingBox;
  final aabbSize = aabb.max - aabb.min;

  final solver = Solver();

  // The parameters we want to solve for.
  final xNew = Param(aabb.min.x);
  final yNew = Param(aabb.min.y);
  final alpha = Param(1.0);

  _addBasicConstraints(
    solver,
    polygon,
    normalizedQuad,
    xNew,
    yNew,
    alpha,
    null,
    enableResize: enableResize
  );

  final objectiveConstraint1 = enableResize ? alpha.equals(cm(1000.0)) : alpha.equals(cm(1.0));
  objectiveConstraint1.priority = Priority.strong;

  solver.addConstraint(objectiveConstraint1);
  solver.flushUpdates();

  if (!enableResize) {
    // We have solved for alpha, now we can solve for xNew and yNew.
    final constAlpha = alpha.value;
    solver.removeConstraint(objectiveConstraint1);
    solver.addConstraint(alpha.equals(cm(constAlpha)));

    // Distance constraints
    final yDist = Param(0.0);
    final xDist = Param(0.0);

    solver.addConstraints([
      yDist >= cm(0.0),
      xDist >= cm(0.0),
      yDist >= cm(aabb.min.y) - yNew,
      yDist >= yNew - cm(aabb.min.y),
      xDist >= cm(aabb.min.x) - xNew,
      xDist >= xNew - cm(aabb.min.x),
    ]);

    final objectiveConstraint2 = ((xDist + yDist)).equals(cm(0.0));
    objectiveConstraint2.priority = Priority.required - 1;

    solver.addConstraints([objectiveConstraint2]);
    solver.flushUpdates();
  }

  final newAabb = Aabb2.minMax(
    Vector2(xNew.value, yNew.value),
    Vector2(
      xNew.value + aabbSize.x * alpha.value,
      yNew.value + aabbSize.y * alpha.value,
    ),
  );

  return newAabb;
}
