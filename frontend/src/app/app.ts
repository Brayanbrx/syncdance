import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

/** Each area (landing, panel) brings its own layout. */
@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  template: '<router-outlet />',
})
export class App {}
