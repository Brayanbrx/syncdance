import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed, discardPeriodicTasks, fakeAsync, tick } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';

import { QualityReport, ReferenceStatus, StudioRoutine } from '../../core/api.models';
import { StudioRoutinePage } from './studio-routine.page';

const URL = '/api/studio/routines/7/';

function routine(status: ReferenceStatus): StudioRoutine {
  return {
    id: 7,
    name: 'Salsa',
    kind: 'DANCE',
    description: '',
    difficulty: 'BEGINNER',
    style: '',
    visibility: 'COURSES',
    is_published: false,
    published_at: null,
    music_rights: '',
    rights_declared_at: null,
    catalog_review: '',
    catalog_requested_at: null,
    catalog_reviewed_at: null,
    catalog_review_note: '',
    duration_ms: 0,
    is_active: true,
    processing: {
      status,
      version: 1,
      error: '',
      finished_at: null,
      light_video: false,
      poster: false,
      warnings: [],
    },
    choreography: {
      bpm: null,
      first_beat_ms: null,
      steps: [],
      stale: false,
      unpublished_changes: false,
    },
    courses: [],
    created_at: '2026-11-17T00:00:00Z',
    updated_at: '2026-11-17T00:00:00Z',
  };
}

const quality: QualityReport = {
  version: 'reference-quality-v1',
  samples: 10,
  duration_ms: 1000,
  single_person: 1,
  no_usable_pose: 0,
  multiple_people: 0,
  problems: [],
  min_usable_ratio: 0.8,
  publishable: true,
};

describe('StudioRoutinePage while the video is processed', () => {
  it('keeps what the instructor fills in and survives a failed check', fakeAsync(() => {
    TestBed.configureTestingModule({
      imports: [StudioRoutinePage],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        {
          provide: ActivatedRoute,
          useValue: { snapshot: { paramMap: convertToParamMap({ id: '7' }) } },
        },
      ],
    });
    const http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(StudioRoutinePage);
    const page = fixture.componentInstance;
    fixture.detectChanges();
    http.expectOne(URL).flush(routine('PROCESSING'));
    http
      .expectOne('/api/studio/courses/')
      .flush([{ id: 3, name: 'Danza', join_code: 'X', accepts_students: true, students: 1 }]);

    // Filled in while the worker runs.
    page.form.controls.name.setValue('Salsa en pareja');
    page.toggle(3, true);
    page.rights.set('OWN');

    tick(5000);
    http.expectOne(URL).error(new ProgressEvent('offline'));
    tick(5000);
    http.expectOne(URL).flush(routine('PROCESSING'));
    expect(page.form.controls.name.value).toBe('Salsa en pareja');
    expect([...page.chosen()]).toEqual([3]);
    expect(page.rights()).toBe('OWN');

    tick(5000);
    http.expectOne(URL).flush(routine('READY'));
    http.expectOne(`${URL}quality/`).flush(quality);
    expect(page.ready()).toBeTrue();
    expect(page.form.controls.name.value).toBe('Salsa en pareja');
    expect(page.canPublish()).toBeTrue();

    // Ready: no more checks.
    tick(15000);
    http.expectNone(URL);
    discardPeriodicTasks();
  }));
});
