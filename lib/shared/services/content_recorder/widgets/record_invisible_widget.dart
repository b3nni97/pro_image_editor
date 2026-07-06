import 'package:flutter/widgets.dart';
import '/shared/widgets/extended/repaint/extended_repaint_boundary.dart';
import '../controllers/content_recorder_controller.dart';

/// A widget that records an invisible child widget.
class RecordInvisibleWidget extends StatefulWidget {
  /// Creates an instance of [RecordInvisibleWidget].
  ///
  /// [child] is the widget to be recorded.
  /// [controller] is the controller used for managing the recording.
  const RecordInvisibleWidget({
    super.key,
    required this.child,
    required this.controller,
  });

  /// The child widget. This widget will not be recorded.
  final Widget child;

  /// The controller used for managing the recording.
  final ContentRecorderController controller;

  @override
  State<RecordInvisibleWidget> createState() => _RecordInvisibleWidgetState();
}

class _RecordInvisibleWidgetState extends State<RecordInvisibleWidget> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Widget?>(
        stream: widget.controller.recorderStream.stream,
        builder: (context, snapshot) {
          if (!widget.controller.recordReadyHelper.isCompleted) {
            widget.controller.recordReadyHelper.complete(true);
          }

          // The recorder slot is ALWAYS present (empty while nothing is
          // being recorded) so the tree shape never changes when a
          // recording starts or ends. Conditionally inserting it shifted
          // [RecordInvisibleWidget.child] between stack positions 0 and 1,
          // which remounted (or, when keyed, reparented) the entire editor
          // subtree mid-session — visible as a black canvas until the next
          // full repaint.
          return Stack(
            children: [
              ExtendedRepaintBoundary(
                key: widget.controller.recorderKey,
                child: snapshot.data ?? const SizedBox.shrink(),
              ),
              widget.child,
            ],
          );
        });
  }
}
