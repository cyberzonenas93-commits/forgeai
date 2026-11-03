// lib/ui/features/exports/exports_screen.dart  —  DJ Software section patch
//
// Add the following imports to the top of exports_screen.dart:
//
//   import '../../../models/dj_export_models.dart';
//   import 'dj_export_sheet.dart';
//
// Then insert the widget below into your exports list, after the existing
// Rekordbox / Serato CSV / Traktor / M3U section(s).
//
// ─────────────────────────────────────────────────────────────────────────────
// HOW TO INSERT
// ─────────────────────────────────────────────────────────────────────────────
// In your existing ExportsScreen build / _buildExportsList method, add:
//
//   _DjSoftwareSection(
//     playlistName: playlistName,   // from screen args / state
//     matches: matches,             // List<TrackMatch>
//   ),
//
// before or after the existing format sections. A thin Divider or
// SizedBox(height: 16) between sections keeps the visual rhythm.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/dj_export_models.dart';
import '../../../models/library_models.dart'; // TrackMatch
import 'dj_export_sheet.dart';

/// Drop-in section widget for the exports screen.
/// Renders a "DJ Software" header card with VirtualDJ and Serato buttons.
class DjSoftwareSection extends ConsumerWidget {
  const DjSoftwareSection({
    super.key,
    required this.playlistName,
    required this.matches,
  });

  final String playlistName;
  final List<TrackMatch> matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Text(
            'DJ Software',
            style: tt.titleSmall?.copyWith(
              color: cs.onSurface.withOpacity(0.55),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),

        // VirtualDJ
        _ExportTile(
          icon: Icons.queue_music,
          title: 'VirtualDJ',
          subtitle: 'Writes a .vdjfolder playlist file',
          accentColor: const Color(0xFFE53935), // VDJ red
          onTap: () => showDjExportSheet(
            context: context,
            ref: ref,
            target: DjTarget.virtualDj,
            playlistName: playlistName,
            matches: matches,
          ),
        ),

        const SizedBox(height: 8),

        // Serato
        _ExportTile(
          icon: Icons.album,
          title: 'Serato DJ',
          subtitle: 'Writes a binary .crate file',
          accentColor: const Color(0xFF00BCD4), // Serato teal
          onTap: () => showDjExportSheet(
            context: context,
            ref: ref,
            target: DjTarget.serato,
            playlistName: playlistName,
            matches: matches,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private tile widget
// ─────────────────────────────────────────────────────────────────────────────

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.bodyLarge),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.55)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}
