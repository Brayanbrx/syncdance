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
  visibility: 'CATALOG' | 'COURSES';
  published_at: string | null;
  catalog_review: CatalogReview;
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
    proposals_pending: number;
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

// ---- Studio (instructors) ----

export type Difficulty = 'BEGINNER' | 'INTERMEDIATE' | 'ADVANCED';

export const DIFFICULTY_LABELS: Record<Difficulty, string> = {
  BEGINNER: 'Principiante',
  INTERMEDIATE: 'Intermedio',
  ADVANCED: 'Avanzado',
};

export type MusicRights = 'OWN' | 'LICENSED' | 'FREE';

export const MUSIC_RIGHTS_LABELS: Record<MusicRights, string> = {
  OWN: 'Es música propia',
  LICENSED: 'Tengo licencia o permiso para usarla',
  FREE: 'Es música libre de derechos',
};

/** The SyncDance catalog review of an instructor's routine ('' = never proposed). */
export type CatalogReview = '' | 'PENDING' | 'APPROVED' | 'REJECTED';

/** The reference of the current master video. */
export interface RoutineProcessing {
  status: ReferenceStatus;
  version: number;
  error: string;
  finished_at: string | null;
  /** Students download the 720p version made for the app. */
  light_video: boolean;
  poster: boolean;
}

/** A routine an instructor proposed for the catalog, as the panel reviews it. */
export interface CatalogProposal {
  id: number;
  name: string;
  description: string;
  style: string;
  difficulty: Difficulty;
  instructor: string;
  duration_ms: number;
  music_rights: MusicRights | '';
  rights_declared_at: string | null;
  catalog_requested_at: string | null;
  /** In how many of its instructor's courses it is published. */
  courses: number;
  processing: RoutineProcessing | null;
  /** Share of samples with one measurable dancer; null when unknown. */
  single_person: number | null;
}

export interface StudioRoutine {
  id: number;
  name: string;
  description: string;
  difficulty: Difficulty;
  style: string;
  visibility: 'CATALOG' | 'COURSES';
  is_published: boolean;
  published_at: string | null;
  music_rights: MusicRights | '';
  rights_declared_at: string | null;
  catalog_review: CatalogReview;
  catalog_requested_at: string | null;
  catalog_reviewed_at: string | null;
  /** Why an administrator did not accept it for the catalog. */
  catalog_review_note: string;
  duration_ms: number;
  is_active: boolean;
  processing: RoutineProcessing | null;
  courses: number[];
  created_at: string;
  updated_at: string;
}

export interface StudioCourse {
  id: number;
  name: string;
  join_code: string;
  accepts_students: boolean;
  students: number;
}

export interface QualityReport {
  version: string;
  samples: number;
  duration_ms: number | null;
  single_person: number | null;
  no_usable_pose: number | null;
  multiple_people: number | null;
  problems: { start_ms: number; end_ms: number; kind: string }[];
  min_usable_ratio: number;
  publishable: boolean;
}

export type RoutineTone = 'ok' | 'warn' | 'danger' | 'neutral';

/** One label for where a routine stands, from draft to published. */
export function routineState(routine: StudioRoutine): { label: string; tone: RoutineTone } {
  if (routine.is_published && routine.visibility === 'CATALOG') {
    return { label: 'En el catálogo', tone: 'ok' };
  }
  if (routine.is_published) {
    const n = routine.courses.length;
    return { label: `Publicada en ${n} ${n === 1 ? 'curso' : 'cursos'}`, tone: 'ok' };
  }
  switch (routine.processing?.status) {
    case 'READY':
      return { label: 'Lista para publicar', tone: 'neutral' };
    case 'FAILED':
      return { label: 'Con error', tone: 'danger' };
    case 'PENDING':
    case 'PROCESSING':
      return { label: 'Procesando el video', tone: 'warn' };
    default:
      return { label: 'Borrador', tone: 'neutral' };
  }
}

/** 0.873 -> "87 %"; unknown stays "—", never 0. */
export function percent(ratio: number | null): string {
  return ratio === null ? '—' : `${Math.round(ratio * 100)} %`;
}

/** 93500 -> "1:33,5" (minutes, seconds and tenths when present). */
export function clock(ms: number): string {
  const tenths = Math.round(ms / 100);
  const seconds = Math.floor(tenths / 10);
  const rest = tenths % 10;
  const text = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  return rest ? `${text},${rest}` : text;
}
