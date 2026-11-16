import { NgTemplateOutlet } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PublicRelease, formatSize } from '../../core/api.models';
import { PanelService } from '../../core/panel.service';
import { DancerComponent } from './dancer.component';

type ReleaseState =
  | { kind: 'loading' }
  | { kind: 'ready'; release: PublicRelease }
  | { kind: 'none' }
  | { kind: 'error' };

@Component({
  selector: 'sd-landing',
  imports: [DancerComponent, NgTemplateOutlet, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './landing.page.html',
  styleUrl: './landing.page.scss',
})
export class LandingPage implements OnInit {
  private readonly panel = inject(PanelService);

  readonly state = signal<ReleaseState>({ kind: 'loading' });
  readonly onAndroid = /android/i.test(navigator.userAgent);
  readonly size = formatSize;

  ngOnInit(): void {
    this.panel.latestRelease().subscribe({
      next: (release) => this.state.set({ kind: 'ready', release }),
      error: (error: unknown) =>
        this.state.set({
          kind: error instanceof HttpErrorResponse && error.status === 404 ? 'none' : 'error',
        }),
    });
  }
}
