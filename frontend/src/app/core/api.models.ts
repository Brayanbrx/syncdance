export interface Page<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

export type Role = 'STUDENT' | 'INSTRUCTOR' | 'ADMIN';

export const ROLE_LABELS: Record<Role, string> = {
  STUDENT: 'Estudiante',
  INSTRUCTOR: 'Instructor',
  ADMIN: 'Administrador',
};

export interface Me {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: Role;
  is_platform_admin: boolean;
}

export interface PublicRelease {
  version_name: string;
  version_code: number;
  size_bytes: number;
  sha256: string;
  notes: string;
  min_android: string;
  published_at: string | null;
  download_url: string;
}

export interface PanelRelease {
  id: number;
  version_name: string;
  version_code: number;
  size_bytes: number;
  sha256: string;
  notes: string;
  min_android: string;
  is_published: boolean;
  published_at: string | null;
  uploaded_by: string | null;
  created_at: string;
}

export interface PanelUser {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: Role;
  is_active: boolean;
  is_superuser: boolean;
  last_login: string | null;
  date_joined: string;
}

export interface NewUser {
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: Role;
  password: string;
}

export type ReferenceStatus = 'PENDING' | 'PROCESSING' | 'READY' | 'FAILED';

export interface PanelRoutine {
  id: number;
  name: string;
  style: string;
  difficulty: 'BEGINNER' | 'INTERMEDIATE' | 'ADVANCED';
  curriculum_position: number | null;
  generator: string;
  instructor: string;
  duration_ms: number;
  is_active: boolean;
  sessions: number;
  reference_status: ReferenceStatus | null;
  reference_version: number | null;
}

export interface PanelCourse {
  id: number;
  name: string;
  instructor: string;
  join_code: string;
  accepts_students: boolean;
  students: number;
  assignments: number;
  created_at: string;
}

export interface PlatformSummary {
  users: {
    students: number;
    instructors: number;
    admins: number;
    inactive: number;
    joined_last_7_days: number;
  };
  practice: {
    sessions: number;
    games: number;
    sessions_last_7_days: number;
    active_students_last_7_days: number;
  };
  catalog: {
    routines: number;
    active_routines: number;
    references_ready: number;
    references_processing: number;
    references_failed: number;
  };
  courses: { courses: number; enrollments: number; assignments: number };
  latest_release: PublicRelease | null;
}

/** "93,0 MB" for people; the exact bytes stay in the API. */
export function formatSize(bytes: number): string {
  const mb = bytes / (1024 * 1024);
  return `${mb.toLocaleString('es', { maximumFractionDigits: 1 })} MB`;
}

/** The API's own message when it gives one, else a fixed sentence. */
export function apiError(error: unknown, fallback: string): string {
  const body = (error as { error?: unknown })?.error;
  if (body && typeof body === 'object') {
    const messages = Object.values(body as Record<string, unknown>)
      .flatMap((value) => (Array.isArray(value) ? value : [value]))
      .filter((value): value is string => typeof value === 'string');
    if (messages.length) return messages.join(' ');
  }
  if (typeof body === 'string' && body.length < 300) return body;
  return fallback;
}
