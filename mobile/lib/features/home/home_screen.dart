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
          // The main path: the catalog has one-tap Bailar and the best stars.
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.push('/routines'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(Icons.music_note, size: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bailar',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const Text(
                            'Elige una rutina y baila frente al teléfono: '
                            'empieza sola cuando te ve de cuerpo entero. '
                            'Si es tu primera vez, empieza por el Nivel 1.',
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
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
            title: const Text('Rutinas'),
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
