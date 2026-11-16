import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';

import { AuthService } from './auth.service';

/** The panel opens only for platform administrators (superuser or Administrator role). */
export const adminGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth
    .ensureMe()
    .pipe(
      map((me) =>
        me?.is_platform_admin
          ? true
          : router.createUrlTree(['/panel/ingresar'], me ? { queryParams: { sinacceso: 1 } } : {}),
      ),
    );
};
