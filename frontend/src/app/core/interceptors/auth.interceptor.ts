import { HttpErrorResponse, HttpInterceptorFn, HttpRequest } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, switchMap, throwError } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthService } from '../auth/auth.service';

const withToken = (request: HttpRequest<unknown>, token: string | null) =>
  token ? request.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : request;

/** Adds the access token to API calls and renews it once after a 401. */
export const authInterceptor: HttpInterceptorFn = (request, next) => {
  if (!request.url.startsWith(environment.apiBaseUrl)) return next(request);
  const auth = inject(AuthService);
  const router = inject(Router);
  return next(withToken(request, auth.accessToken)).pipe(
    catchError((error: unknown) => {
      if (!(error instanceof HttpErrorResponse) || error.status !== 401 || !auth.accessToken) {
        return throwError(() => error);
      }
      return auth.refreshAccess().pipe(
        switchMap((token) => next(withToken(request, token))),
        catchError((refreshError: unknown) => {
          router.navigate(['/panel/ingresar'], { queryParams: { expirada: 1 } });
          return throwError(() => refreshError);
        }),
      );
    }),
  );
};
