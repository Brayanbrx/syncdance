import { HttpClient, HttpEvent, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import {
  CatalogProposal,
  NewUser,
  Page,
  PanelCourse,
  PanelRelease,
  PanelRoutine,
  PanelUser,
  PilotMetrics,
  PlatformSummary,
  PublicRelease,
  Role,
} from './api.models';

const api = environment.apiBaseUrl;

@Injectable({ providedIn: 'root' })
export class PanelService {
  private readonly http = inject(HttpClient);

  /** Public: the build the landing page offers (404 when none is published). */
  latestRelease(): Observable<PublicRelease> {
    return this.http.get<PublicRelease>(`${api}/app/latest/`);
  }

  summary(): Observable<PlatformSummary> {
    return this.http.get<PlatformSummary>(`${api}/panel/summary/`);
  }

  pilot(): Observable<PilotMetrics> {
    return this.http.get<PilotMetrics>(`${api}/panel/pilot/`);
  }

  users(filters: {
    page: number;
    role?: Role | '';
    active?: '' | 'true' | 'false';
    search?: string;
  }): Observable<Page<PanelUser>> {
    let params = new HttpParams().set('page', filters.page);
    if (filters.role) params = params.set('role', filters.role);
    if (filters.active) params = params.set('active', filters.active);
    if (filters.search?.trim()) params = params.set('search', filters.search.trim());
    return this.http.get<Page<PanelUser>>(`${api}/panel/users/`, { params });
  }

  createUser(user: NewUser): Observable<PanelUser> {
    return this.http.post<PanelUser>(`${api}/panel/users/`, user);
  }

  updateUser(id: number, changes: Partial<PanelUser>): Observable<PanelUser> {
    return this.http.patch<PanelUser>(`${api}/panel/users/${id}/`, changes);
  }

  setPassword(id: number, password: string): Observable<void> {
    return this.http.post<void>(`${api}/panel/users/${id}/set-password/`, { password });
  }

  routines(page: number): Observable<Page<PanelRoutine>> {
    return this.http.get<Page<PanelRoutine>>(`${api}/panel/routines/`, {
      params: { page },
    });
  }

  setRoutineActive(id: number, isActive: boolean): Observable<PanelRoutine> {
    return this.http.patch<PanelRoutine>(`${api}/panel/routines/${id}/`, { is_active: isActive });
  }

  /** Routines instructors proposed for the catalog, oldest first. */
  proposals(): Observable<CatalogProposal[]> {
    return this.http.get<CatalogProposal[]>(`${api}/panel/proposals/`);
  }

  approveProposal(id: number): Observable<void> {
    return this.http.post<void>(`${api}/panel/proposals/${id}/approve/`, {});
  }

  rejectProposal(id: number, note: string): Observable<void> {
    return this.http.post<void>(`${api}/panel/proposals/${id}/reject/`, { note });
  }

  courses(page: number): Observable<Page<PanelCourse>> {
    return this.http.get<Page<PanelCourse>>(`${api}/panel/courses/`, { params: { page } });
  }

  releases(): Observable<Page<PanelRelease>> {
    return this.http.get<Page<PanelRelease>>(`${api}/panel/releases/`);
  }

  /** Multipart upload with progress events for the progress bar. */
  uploadRelease(form: FormData): Observable<HttpEvent<PanelRelease>> {
    return this.http.post<PanelRelease>(`${api}/panel/releases/`, form, {
      reportProgress: true,
      observe: 'events',
    });
  }

  updateRelease(id: number, changes: Partial<PanelRelease>): Observable<PanelRelease> {
    return this.http.patch<PanelRelease>(`${api}/panel/releases/${id}/`, changes);
  }

  deleteRelease(id: number): Observable<void> {
    return this.http.delete<void>(`${api}/panel/releases/${id}/`);
  }
}
