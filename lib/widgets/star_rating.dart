import 'package:flutter/material.dart';

/// Read-only star display for an average rating (e.g. station cards).
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({super.key, required this.rating, this.reviewCount, this.size = 16});

  final double rating;
  final int? reviewCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (reviewCount == 0) {
      return Text('No reviews yet', style: TextStyle(color: Colors.grey.shade600, fontSize: size * 0.75));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          final filled = i < rating.round();
          return Icon(filled ? Icons.star : Icons.star_border, color: Colors.amber, size: size);
        }),
        const SizedBox(width: 4),
        Text(
          reviewCount != null ? '${rating.toStringAsFixed(1)} ($reviewCount)' : rating.toStringAsFixed(1),
          style: TextStyle(color: Colors.grey.shade700, fontSize: size * 0.75),
        ),
      ],
    );
  }
}

/// Tappable star row for submitting a rating (1-5).
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({super.key, required this.rating, required this.onChanged, this.size = 32});

  final int rating;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Minimum 48dp tap target regardless of the visual icon size.
    final tapSize = size + 8 < 48 ? 48.0 : size + 8;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starValue = i + 1;
        return IconButton(
          onPressed: () => onChanged(starValue),
          icon: Icon(starValue <= rating ? Icons.star : Icons.star_border, color: Colors.amber, size: size),
          tooltip: '$starValue star${starValue == 1 ? '' : 's'}',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: tapSize, height: tapSize),
        );
      }),
    );
  }
}
