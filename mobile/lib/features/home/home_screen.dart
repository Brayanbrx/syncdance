import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/update/update_banner.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            tooltip: 'Mi cuenta',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/account'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Outside Google Play this is how a student learns of a new APK.
          const UpdateBanner(),
          // The two sections: same account, courses and history underneath.
          _Section(
            icon: Icons.directions_run,
            title: 'Bailar',
            text:
                'Elige una rutina y baila frente al teléfono: empieza sola '
                'cuando te ve de cuerpo entero. Si es tu primera vez, empieza '
                'por el Nivel 1.',
            color: Theme.of(context).colorScheme.primaryContainer,
            onTap: () => context.push('/routines'),
          ),
          _Section(
            icon: Icons.mic,
            title: 'Cantar',
            text:
                'Canta con la guía usando audífonos y mira en vivo si tu nota '
                'está arriba o abajo de la melodía. Empieza por «Notas largas».',
            color: Theme.of(context).colorScheme.tertiaryContainer,
            onTap: () => context.push('/singing'),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Mis cursos'),
            subtitle: const Text(
              'Únete con el código de tu instructor y cumple sus tareas',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/courses'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Herramientas'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Preparar cámara'),
            subtitle: const Text('Comprueba el encuadre antes de entrenar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/training/camera'),
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Rutinas de baile'),
            subtitle: const Text('Catálogo, referencias guardadas y maestro'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/routines'),
          ),
          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: const Text('Detectar postura'),
            subtitle: const Text('Prueba de detección corporal en Android'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/training/pose'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Historial de prácticas'),
            subtitle: const Text('Resúmenes guardados en este dispositivo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/training/history'),
          ),
        ],
      ),
    );
  }
}

/// A big entry to one of the sections.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title, text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  Text(text),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}
