import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The brand's signature: the left side of the body in orange, the right in
/// sky blue, as the practice paints the skeleton.
class BrandStripe extends StatelessWidget {
  const BrandStripe({this.height = 6, this.width, super.key});
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final sync = SyncColors.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Row(
            // Without stretch the childless boxes would have no height.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ColoredBox(color: sync.left)),
              Expanded(child: ColoredBox(color: sync.right)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small heading over a group of items.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: theme.textTheme.titleMedium?.merge(AppTheme.display(700)),
        ),
      ),
    );
  }
}
