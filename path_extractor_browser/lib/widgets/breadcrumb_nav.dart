import 'package:flutter/material.dart';

class BreadcrumbNav extends StatelessWidget {
  final List<String> pathSegments;
  final void Function(int index) onTap;

  const BreadcrumbNav({
    super.key,
    required this.pathSegments,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < pathSegments.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right, size: 16),
            if (i == pathSegments.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  pathSegments[i],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              )
            else
              TextButton(
                onPressed: () => onTap(i),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(pathSegments[i]),
              ),
          ],
        ],
      ),
    );
  }
}
