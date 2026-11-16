import { HttpClient, HttpEvent } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';

/**
 * Files of a processed routine version. They need the session, so they are
 * fetched as blobs (an <img> or <video> cannot send the token).
 */
@Injectable({ providedIn: 'root' })
export class RoutineMediaService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/routines`;

  poster(id: number, version: number): Observable<Blob> {
    return this.http.get(`${this.base}/${id}/references/${version}/poster/`, {
      responseType: 'blob',
    });
  }

  /** The video students play for a version, with download progress. */
  video(id: number, version: number): Observable<HttpEvent<Blob>> {
    return this.http.get(`${this.base}/${id}/references/${version}/video/`, {
      responseType: 'blob',
      reportProgress: true,
      observe: 'events',
    });
  }
}
