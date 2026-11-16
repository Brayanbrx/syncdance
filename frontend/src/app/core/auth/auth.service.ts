import { HttpBackend, HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import {
  Observable,
  catchError,
  finalize,
  map,
  of,
  shareReplay,
  switchMap,
  tap,
  throwError,
} from 'rxjs';

import { environment } from '../../../environments/environment';
import { Me } from '../api.models';

interface Tokens {
  access: string;
  refresh?: string;
}

const ACCESS = 'syncdance.access';
const REFRESH = 'syncdance.refresh';

/**
 * Tokens live in sessionStorage: closing the tab ends the panel session.
 * Token calls go through HttpBackend so the interceptor never loops on them.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly raw = new HttpClient(inject(HttpBackend));
  private refreshing$: Observable<string> | null = null;

  readonly me = signal<Me | null>(null);
  readonly isPlatformAdmin = computed(() => this.me()?.is_platform_admin === true);

  get accessToken(): string | null {
    return sessionStorage.getItem(ACCESS);
  }

  login(username: string, password: string): Observable<Me> {
    return this.raw
      .post<Tokens>(`${environment.apiBaseUrl}/auth/login/`, { username, password })
      .pipe(
        tap((tokens) => this.store(tokens)),
        switchMap(() => this.loadMe()),
      );
  }

  /** The signed-in account, from memory or the server; null without a session. */
  ensureMe(): Observable<Me | null> {
    if (this.me()) return of(this.me());
    if (!this.accessToken && !sessionStorage.getItem(REFRESH)) return of(null);
    return this.loadMe().pipe(catchError(() => of(null)));
  }

  /** One refresh at a time: rotation makes a refresh token single-use. */
  refreshAccess(): Observable<string> {
    const refresh = sessionStorage.getItem(REFRESH);
    if (!refresh) return throwError(() => new Error('Sin sesión'));
    this.refreshing$ ??= this.raw
      .post<Tokens>(`${environment.apiBaseUrl}/auth/token/refresh/`, { refresh })
      .pipe(
        tap((tokens) => this.store(tokens)),
        map((tokens) => tokens.access),
        catchError((error) => {
          this.clear();
          return throwError(() => error);
        }),
        finalize(() => (this.refreshing$ = null)),
        shareReplay(1),
      );
    return this.refreshing$;
  }

  logout(): void {
    const refresh = sessionStorage.getItem(REFRESH);
    if (refresh) {
      // Best effort: the server blacklists the refresh token.
      this.raw.post(`${environment.apiBaseUrl}/auth/logout/`, { refresh }).subscribe({
        error: () => undefined,
      });
    }
    this.clear();
  }

  private loadMe(): Observable<Me> {
    return this.http
      .get<Me>(`${environment.apiBaseUrl}/auth/me/`)
      .pipe(tap((me) => this.me.set(me)));
  }

  private store(tokens: Tokens): void {
    sessionStorage.setItem(ACCESS, tokens.access);
    if (tokens.refresh) sessionStorage.setItem(REFRESH, tokens.refresh);
  }

  private clear(): void {
    sessionStorage.removeItem(ACCESS);
    sessionStorage.removeItem(REFRESH);
    this.me.set(null);
  }
}
