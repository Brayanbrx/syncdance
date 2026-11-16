import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';

import { AuthService } from './auth.service';

/** The studio opens for instructors and platform administrators. */
export const studioGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth
    .ensureMe()
    .pipe(
      map((me) =>
        me && (me.role === 'INSTRUCTOR' || me.is_platform_admin)
          ? true
          : router.createUrlTree(['/ingresar'], me ? { queryParams: { sinacceso: 1 } } : {}),
      ),
    );
};
