import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/catalog_session.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            tooltip: 'Cambiar cuenta',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              catalogSession.signOut();
              context.go('/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Prepara tu espacio para practicar baile y comprueba '
              'que tu cuerpo se vea completo en la cámara.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Preparar cámara'),
            subtitle: const Text('Comprueba el encuadre antes de entrenar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/training/camera'),
          ),
          ListTile(
            title: const Text('Rutinas'),
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
          ListTile(
            title: const Text('Análisis de videos (secundario)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/performances'),
          ),
        ],
      ),
    );
  }
}
