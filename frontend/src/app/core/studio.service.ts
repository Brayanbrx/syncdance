import { HttpClient, HttpEvent } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import {
  Choreography,
  CoursePractices,
  DifficultyMap,
  FollowModeCode,
  MusicRights,
  QualityReport,
  StudioCourse,
  StudioCourseDetail,
  StudioRoutine,
} from './api.models';

export interface RoutineFields {
  name?: string;
  description?: string;
  difficulty?: string;
  style?: string;
}

/** /api/studio/: an instructor's own routines and courses. */
@Injectable({ providedIn: 'root' })
export class StudioService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/studio`;

  routines(): Observable<StudioRoutine[]> {
    return this.http.get<StudioRoutine[]>(`${this.base}/routines/`);
  }

  routine(id: number): Observable<StudioRoutine> {
    return this.http.get<StudioRoutine>(`${this.base}/routines/${id}/`);
  }

  /** Upload with progress events (the video can weigh up to 200 MB). */
  create(fields: RoutineFields, video: File): Observable<HttpEvent<StudioRoutine>> {
    const form = new FormData();
    for (const [key, value] of Object.entries(fields)) form.append(key, value ?? '');
    form.append('master_video', video);
    return this.http.post<StudioRoutine>(`${this.base}/routines/`, form, {
      reportProgress: true,
      observe: 'events',
    });
  }

  update(id: number, fields: RoutineFields): Observable<StudioRoutine> {
    return this.http.patch<StudioRoutine>(`${this.base}/routines/${id}/`, fields);
  }

  replaceVideo(id: number, video: File): Observable<HttpEvent<StudioRoutine>> {
    const form = new FormData();
    form.append('master_video', video);
    return this.http.patch<StudioRoutine>(`${this.base}/routines/${id}/`, form, {
      reportProgress: true,
      observe: 'events',
    });
  }

  publish(id: number, courses: number[], musicRights: MusicRights): Observable<StudioRoutine> {
    return this.http.post<StudioRoutine>(`${this.base}/routines/${id}/publish/`, {
      courses,
      music_rights: musicRights,
    });
  }

  /** Save the tempo and steps (bpm null clears them). */
  saveChoreography(id: number, draft: Choreography): Observable<StudioRoutine> {
    return this.http.put<StudioRoutine>(`${this.base}/routines/${id}/choreography/`, draft);
  }

  unpublish(id: number): Observable<StudioRoutine> {
    return this.http.post<StudioRoutine>(`${this.base}/routines/${id}/unpublish/`, {});
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/routines/${id}/`);
  }

  quality(id: number): Observable<QualityReport> {
    return this.http.get<QualityReport>(`${this.base}/routines/${id}/quality/`);
  }

  /** Ask an administrator to add the published routine to the catalog. */
  proposeForCatalog(id: number): Observable<StudioRoutine> {
    return this.http.post<StudioRoutine>(`${this.base}/routines/${id}/catalog/`, {});
  }

  /** Withdraw the proposal, or take the routine out of the catalog. */
  leaveCatalog(id: number): Observable<StudioRoutine> {
    return this.http.delete<StudioRoutine>(`${this.base}/routines/${id}/catalog/`);
  }

  courses(): Observable<StudioCourse[]> {
    return this.http.get<StudioCourse[]>(`${this.base}/courses/`);
  }

  course(id: number): Observable<StudioCourseDetail> {
    return this.http.get<StudioCourseDetail>(`${this.base}/courses/${id}/`);
  }

  difficultyMap(
    course: number,
    routine: number,
    followMode: FollowModeCode,
    speed: number,
  ): Observable<DifficultyMap> {
    return this.http.get<DifficultyMap>(`${this.base}/courses/${course}/map/`, {
      params: { routine, follow_mode: followMode, speed },
    });
  }

  practices(course: number): Observable<CoursePractices> {
    return this.http.get<CoursePractices>(`${this.base}/courses/${course}/practices/`);
  }

  /** The comment, when given, is saved as an observation the student reads. */
  rate(practice: string, rating: number, comment = ''): Observable<{ rating: number }> {
    return this.http.put<{ rating: number }>(`${this.base}/practices/${practice}/rating/`, {
      rating,
      comment,
    });
  }

  unrate(practice: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/practices/${practice}/rating/`);
  }
}
