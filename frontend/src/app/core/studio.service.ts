import { HttpClient, HttpEvent } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import { MusicRights, QualityReport, StudioCourse, StudioRoutine } from './api.models';

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
  private readonly routinesBase = `${environment.apiBaseUrl}/routines`;

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

  unpublish(id: number): Observable<StudioRoutine> {
    return this.http.post<StudioRoutine>(`${this.base}/routines/${id}/unpublish/`, {});
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/routines/${id}/`);
  }

  quality(id: number): Observable<QualityReport> {
    return this.http.get<QualityReport>(`${this.base}/routines/${id}/quality/`);
  }

  /** Thumbnail of a processed version (authenticated, so fetched as a blob). */
  poster(id: number, version: number): Observable<Blob> {
    return this.http.get(`${this.routinesBase}/${id}/references/${version}/poster/`, {
      responseType: 'blob',
    });
  }

  /** The video students play for a version, with download progress. */
  video(id: number, version: number): Observable<HttpEvent<Blob>> {
    return this.http.get(`${this.routinesBase}/${id}/references/${version}/video/`, {
      responseType: 'blob',
      reportProgress: true,
      observe: 'events',
    });
  }

  courses(): Observable<StudioCourse[]> {
    return this.http.get<StudioCourse[]>(`${this.base}/courses/`);
  }
}
