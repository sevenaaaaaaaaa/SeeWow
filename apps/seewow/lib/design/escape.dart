import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Escape rule, written once.
///
/// **Innermost open surface wins.** A panel inside the player beats the player,
/// the player beats the shell, a dialog beats whatever is under it. Nothing
/// global binds Escape, because a global binding cannot know which surface is
/// innermost and would fire while the user is editing text.
///
/// A surface opts in by wrapping itself in [EscapeToPop]. It works whenever
/// focus is anywhere inside that surface, which is the case as soon as the user
/// has touched it — and it deliberately does nothing when focus is elsewhere,
/// so Escape in a text field still means "cancel the edit".
class EscapeToPop extends StatelessWidget {
  const EscapeToPop({super.key, required this.child, this.onEscape});

  final Widget child;

  /// Defaults to popping the current route.
  final VoidCallback? onEscape;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape):
          onEscape ?? () => Navigator.of(context).maybePop(),
    },
    child: child,
  );
}
