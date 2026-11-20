import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_widgets.dart';
import '../../core/update/update_banner.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Mi cuenta',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/account'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          // Outside Google Play this is how a student learns of a new APK.
          const UpdateBanner(),
          Text('¿Qué practicamos hoy?', style: text.headlineMedium),
          const SizedBox(height: 16),
          // The two sections: same account, courses and history underneath.
          _SectionBlock(
            icon: Icons.directions_run_rounded,
            title: 'Bailar',
            text:
                'Baila frente al teléfono y te corrige al momento. Empieza '
                'sola cuando te ve de cuerpo entero. Si es tu primera vez, '
                'empieza por el Nivel 1.',
            background: sync.stage,
            foreground: sync.onStage,
            muted: sync.onStageMuted,
            accent: sync.left,
            onTap: () => context.push('/routines'),
          ),
          const SizedBox(height: 12),
          _SectionBlock(
            icon: Icons.mic_rounded,
            title: 'Cantar',
            text:
                'Canta con la guía usando audífonos y mira en vivo si tu nota '
                'está arriba o abajo de la melodía. Empieza por «Notas largas».',
            background: sync.right,
            foreground: Brand.stageDeep,
            muted: Brand.stageDeep.withValues(alpha: 0.82),
            accent: Brand.stageDeep,
            accentIcon: sync.right,
            onTap: () => context.push('/singing'),
          ),
          const SizedBox(height: 12),
          _WideTile(
            icon: Icons.school_rounded,
            title: 'Mis cursos',
            text: 'Únete con el código de tu instructor y cumple sus tareas',
            onTap: () => context.push('/courses'),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Herramientas'),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ToolTile(
                    icon: Icons.videocam_rounded,
                    title: 'Preparar cámara',
                    text: 'Comprueba el encuadre antes de entrenar',
                    onTap: () => context.push('/training/camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToolTile(
                    icon: Icons.history_rounded,
                    title: 'Historial de prácticas',
                    text: 'Resúmenes guardados en este dispositivo',
                    onTap: () => context.push('/training/history'),
                  ),
                ),
              ],
            ),
          ),
          // A diagnostic for development builds, not for students.
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            _WideTile(
              icon: Icons.accessibility_new_rounded,
              title: 'Detectar postura',
              text: 'Prueba de detección corporal en Android',
              onTap: () => context.push('/training/pose'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A big colored entry to one of the two sections.
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.icon,
    required this.title,
    required this.text,
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.onTap,
    this.accentIcon,
  });

  final IconData icon;
  final String title, text;
  final Color background, foreground, muted, accent;
  final Color? accentIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(28);
    return Material(
      color: background,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // A large, faint echo of the icon gives the block its energy.
            Positioned(
              right: -18,
              bottom: -24,
              child: ExcludeSemantics(
                child: Icon(
                  icon,
                  size: 150,
                  color: foreground.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: accent,
                        child: Icon(
                          icon,
                          size: 28,
                          color: accentIcon ?? Brand.stageDeep,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_forward_rounded, color: foreground),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: foreground,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-width card with an icon, a title and a line of text.
class _WideTile extends StatelessWidget {
  const _WideTile({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String title, text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _IconBadge(icon: icon, color: scheme.primaryContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact card for the tools grid.
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String title, text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(icon: icon, color: scheme.secondaryContainer),
              const SizedBox(height: 12),
              Text(title, style: textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                text,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, size: 24, color: Theme.of(context).colorScheme.onSurface),
  );
}
