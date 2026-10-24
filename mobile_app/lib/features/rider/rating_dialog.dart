import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

class RatingDialog extends StatefulWidget {
  final String rideId;
  final String driverName;
  final String vehicleInfo;
  final double fareAmount;
  final VoidCallback onDismissed;

  const RatingDialog({
    super.key,
    required this.rideId,
    required this.driverName,
    required this.vehicleInfo,
    required this.fareAmount,
    required this.onDismissed,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _selectedRating = 5;
  final Set<String> _selectedBadges = {'FELT 100% SAFE', 'SAFE DRIVING'};
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  final List<Map<String, String>> _safetyBadges = const [
    {'en': 'FELT 100% SAFE', 'ar': 'شعور تام بالأمان والراحة'},
    {'en': 'SAFE DRIVING', 'ar': 'قيادة آمنة ومريحة'},
    {'en': 'CLEAN VEHICLE', 'ar': 'سيارة نظيفة ومرتبة'},
    {'en': 'RESPECTFUL & POLITE', 'ar': 'تعامل راقي ومحترم'},
    {'en': 'PERFECT NAVIGATION', 'ar': 'مسار دقيق وسريع'},
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    await SupabaseService().submitDriverRating(
      rideId: widget.rideId,
      rating: _selectedRating.toDouble(),
      badges: _selectedBadges.toList(),
      comment: _commentController.text.trim(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you! Your feedback strengthens Rafik ride safety.'),
          backgroundColor: AppTheme.sageSafe,
        ),
      );
      Navigator.pop(context);
      widget.onDismissed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white12),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Badge
            const PillBadge(
              text: 'TRIP COMPLETED • RATE CAPTAIN',
              textColor: AppTheme.sageSafe,
              bgColor: Color(0x1F6B8E23),
              borderColor: Color(0x3D6B8E23),
            ),
            const SizedBox(height: 16),

            // Driver Details
            CircleAvatar(
              radius: 32,
              backgroundColor: AppTheme.roseGold.withOpacity(0.2),
              child: const Icon(Icons.person_outline_rounded, color: AppTheme.roseGold, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              widget.driverName,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.vehicleInfo,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.fareAmount.toStringAsFixed(2)} LE Paid',
              style: const TextStyle(
                color: AppTheme.roseGold,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            // 5-Star Row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starNum = index + 1;
                final isFilled = starNum <= _selectedRating;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedRating = starNum);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFilled ? const Color(0xFFFFB300) : Colors.white24,
                      size: 38,
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            // Safety Badges
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SAFETY & EXPERIENCE BADGES',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _safetyBadges.map((badge) {
                final isSelected = _selectedBadges.contains(badge['en']);
                return FilterChip(
                  label: Text(badge['en']!),
                  selected: isSelected,
                  selectedColor: AppTheme.roseGold.withOpacity(0.25),
                  backgroundColor: const Color(0xFF1B0E14),
                  side: BorderSide(
                    color: isSelected ? AppTheme.roseGold : Colors.white12,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.roseGold : AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (selected) {
                        _selectedBadges.add(badge['en']!);
                      } else {
                        _selectedBadges.remove(badge['en']!);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Comment Box
            TextField(
              controller: _commentController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Add an optional note to Captain...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF190B12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.roseGold),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRating,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.roseGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : const Text(
                        'SUBMIT RATING & CLOSE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
