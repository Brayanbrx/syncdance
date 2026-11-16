import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/coaching/courses_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/performances/performance_detail_screen.dart';
import '../../features/performances/performances_screen.dart';
import '../../features/performances/record_performance_screen.dart';
import '../../features/routines/routines_screen.dart';
import '../../features/training/presentation/camera_training_screen.dart';
import '../../features/training/presentation/session_history_screen.dart';
import '../../features/training/pose/adapters/mlkit_pose_estimator.dart';

/// A restored session starts at '/home' without network access.
GoRouter createAppRouter({String initialLocation = '/login'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/training/history',
      builder: (context, state) => const SessionHistoryScreen(),
    ),
    GoRoute(
      path: '/training/camera',
      builder: (context, state) => const CameraTrainingScreen(),
    ),
    GoRoute(
      path: '/training/pose',
      builder: (context, state) =>
          CameraTrainingScreen(createPoseEstimator: MlKitPoseEstimator.new),
    ),
    GoRoute(
      path: '/routines',
      builder: (context, state) => RoutinesScreen(
        startRoutineId: int.tryParse(state.uri.queryParameters['start'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/courses',
      builder: (context, state) => const CoursesScreen(),
    ),
    GoRoute(
      path: '/performances',
      builder: (context, state) => const PerformancesScreen(),
    ),
    GoRoute(
      path: '/performances/record',
      builder: (context, state) => const RecordPerformanceScreen(),
    ),
    GoRoute(
      path: '/performances/:id',
      builder: (context, state) =>
          PerformanceDetailScreen(performanceId: state.pathParameters['id']!),
    ),
  ],
);
