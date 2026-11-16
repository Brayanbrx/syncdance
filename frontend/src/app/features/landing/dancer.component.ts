import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  NgZone,
  OnDestroy,
  inject,
} from '@angular/core';

type Point = readonly [number, number];
type Joint =
  | 'head'
  | 'neck'
  | 'shoulderL'
  | 'shoulderR'
  | 'elbowL'
  | 'elbowR'
  | 'wristL'
  | 'wristR'
  | 'hipL'
  | 'hipR'
  | 'kneeL'
  | 'kneeR'
  | 'ankleL'
  | 'ankleR';
type Pose = Record<Joint, Point>;
type Side = 'left' | 'right' | 'center';

// Seen like the app's front camera (a mirror): the dancer's left is on the left.
const STAND: Pose = {
  head: [120, 46],
  neck: [120, 76],
  shoulderL: [96, 88],
  shoulderR: [144, 88],
  elbowL: [86, 128],
  elbowR: [154, 128],
  wristL: [82, 166],
  wristR: [158, 166],
  hipL: [106, 172],
  hipR: [134, 172],
  kneeL: [102, 230],
  kneeR: [138, 230],
  ankleL: [100, 288],
  ankleR: [140, 288],
};

const pose = (changes: Partial<Pose>): Pose => ({ ...STAND, ...changes });

/** Four moves of an original routine, each with the rating the game gives. */
const MOVES: { pose: Pose; rating: string }[] = [
  {
    rating: 'PERFECT',
    pose: pose({
      elbowL: [74, 60],
      wristL: [58, 26],
      elbowR: [166, 60],
      wristR: [182, 26],
      kneeL: [94, 230],
      ankleL: [82, 288],
      kneeR: [146, 230],
      ankleR: [158, 288],
    }),
  },
  {
    rating: 'GREAT',
    pose: pose({
      head: [112, 48],
      neck: [114, 78],
      elbowL: [62, 92],
      wristL: [26, 94],
      elbowR: [160, 124],
      wristR: [138, 150],
      kneeL: [84, 222],
      ankleL: [64, 284],
    }),
  },
  {
    rating: 'PERFECT',
    pose: pose({
      head: [120, 52],
      neck: [120, 82],
      shoulderL: [96, 94],
      shoulderR: [144, 94],
      elbowL: [92, 132],
      wristL: [116, 110],
      elbowR: [148, 132],
      wristR: [124, 110],
      kneeR: [152, 200],
      ankleR: [146, 254],
    }),
  },
  {
    rating: 'GOOD',
    pose: pose({
      head: [128, 48],
      neck: [126, 78],
      elbowR: [178, 92],
      wristR: [214, 94],
      elbowL: [80, 124],
      wristL: [102, 150],
      kneeR: [156, 222],
      ankleR: [176, 284],
    }),
  },
];

const BONES: { from: Joint; to: Joint; side: Side }[] = [
  { from: 'neck', to: 'head', side: 'center' },
  { from: 'shoulderL', to: 'shoulderR', side: 'center' },
  { from: 'hipL', to: 'hipR', side: 'center' },
  { from: 'shoulderL', to: 'hipL', side: 'left' },
  { from: 'shoulderR', to: 'hipR', side: 'right' },
  { from: 'shoulderL', to: 'elbowL', side: 'left' },
  { from: 'elbowL', to: 'wristL', side: 'left' },
  { from: 'shoulderR', to: 'elbowR', side: 'right' },
  { from: 'elbowR', to: 'wristR', side: 'right' },
  { from: 'hipL', to: 'kneeL', side: 'left' },
  { from: 'kneeL', to: 'ankleL', side: 'left' },
  { from: 'hipR', to: 'kneeR', side: 'right' },
  { from: 'kneeR', to: 'ankleR', side: 'right' },
];

const JOINTS: { joint: Joint; side: Side }[] = (
  ['shoulderL', 'elbowL', 'wristL', 'hipL', 'kneeL', 'ankleL'] as Joint[]
)
  .map((joint) => ({ joint, side: 'left' as Side }))
  .concat(
    (['shoulderR', 'elbowR', 'wristR', 'hipR', 'kneeR', 'ankleR'] as Joint[]).map((joint) => ({
      joint,
      side: 'right' as Side,
    })),
  );

const MOVE_MS = 520;
const HOLD_MS = 420;

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);

@Component({
  selector: 'sd-dancer',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <figure class="dancer">
      <svg viewBox="0 0 240 320" role="img" aria-labelledby="dancer-title">
        <title id="dancer-title">
          Esqueleto de una persona bailando, como lo dibuja la app sobre la cámara
        </title>
        @for (bone of bones; track $index) {
          <line
            [attr.x1]="start[bone.from][0]"
            [attr.y1]="start[bone.from][1]"
            [attr.x2]="start[bone.to][0]"
            [attr.y2]="start[bone.to][1]"
            [class]="bone.side"
          />
        }
        <circle class="head" [attr.cx]="start.head[0]" [attr.cy]="start.head[1]" r="17" />
        @for (dot of joints; track dot.joint) {
          <circle
            [attr.cx]="start[dot.joint][0]"
            [attr.cy]="start[dot.joint][1]"
            r="5.5"
            [class]="'joint ' + dot.side"
          />
        }
      </svg>
      <p class="rating" aria-hidden="true">{{ firstRating }}</p>
      <figcaption>
        <span class="key key--left">Tu izquierda</span>
        <span class="key key--right">Tu derecha</span>
      </figcaption>
    </figure>
  `,
  styles: `
    .dancer {
      margin: 0;
      position: relative;
      display: grid;
      justify-items: center;
    }
    svg {
      width: min(100%, 22rem);
      height: auto;
      overflow: visible;
    }
    line {
      stroke-width: 7;
      stroke-linecap: round;
    }
    .left {
      stroke: var(--left);
      fill: var(--left);
    }
    .right {
      stroke: var(--right);
      fill: var(--right);
    }
    .center {
      stroke: #c9cff0;
      opacity: 0.75;
    }
    .head {
      fill: none;
      stroke: #c9cff0;
      stroke-width: 5;
    }
    .joint {
      stroke: var(--stage);
      stroke-width: 2.5;
    }
    .rating {
      position: absolute;
      top: 0;
      right: 0;
      margin: 0;
      font: 800 var(--step-2) / 1 var(--display);
      font-stretch: 75%;
      letter-spacing: 0.04em;
      color: var(--left);
      transform-origin: right center;
    }
    .rating.pop {
      animation: pop 600ms cubic-bezier(0.2, 1.4, 0.4, 1);
    }
    @keyframes pop {
      from {
        opacity: 0;
        transform: scale(0.6) rotate(-6deg);
      }
      to {
        opacity: 1;
        transform: none;
      }
    }
    figcaption {
      display: flex;
      gap: 1.25rem;
      font-size: var(--step--1);
      color: #c9cff0;
    }
    .key::before {
      content: '';
      display: inline-block;
      width: 0.7em;
      height: 0.7em;
      border-radius: 50%;
      margin-right: 0.4em;
      vertical-align: 0.05em;
    }
    .key--left::before {
      background: var(--left);
    }
    .key--right::before {
      background: var(--right);
    }
  `,
})
export class DancerComponent implements AfterViewInit, OnDestroy {
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly zone = inject(NgZone);
  private frame = 0;

  readonly bones = BONES;
  readonly joints = JOINTS;
  readonly start: Pose = MOVES[0].pose;
  readonly firstRating = MOVES[0].rating;

  ngAfterViewInit(): void {
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (reduce) return; // a still, readable pose
    this.zone.runOutsideAngular(() => this.animate());
  }

  ngOnDestroy(): void {
    cancelAnimationFrame(this.frame);
  }

  /** Per frame, outside change detection: only SVG attributes move. */
  private animate(): void {
    const root = this.host.nativeElement;
    const lines = Array.from(root.querySelectorAll('line'));
    const dots = Array.from(root.querySelectorAll<SVGCircleElement>('circle.joint'));
    const head = root.querySelector<SVGCircleElement>('circle.head')!;
    const rating = root.querySelector<HTMLElement>('.rating')!;
    const cycle = MOVE_MS + HOLD_MS;
    let shown = 0;
    const began = performance.now();

    const tick = (now: number) => {
      const elapsed = now - began;
      const index = Math.floor(elapsed / cycle) % MOVES.length;
      const from = MOVES[index].pose;
      const toIndex = (index + 1) % MOVES.length;
      const to = MOVES[toIndex].pose;
      const t = ease(Math.min(1, (elapsed % cycle) / MOVE_MS));
      const at = (joint: Joint): Point => [
        from[joint][0] + (to[joint][0] - from[joint][0]) * t,
        from[joint][1] + (to[joint][1] - from[joint][1]) * t,
      ];
      BONES.forEach((bone, i) => {
        const [x1, y1] = at(bone.from);
        const [x2, y2] = at(bone.to);
        lines[i].setAttribute('x1', x1.toFixed(1));
        lines[i].setAttribute('y1', y1.toFixed(1));
        lines[i].setAttribute('x2', x2.toFixed(1));
        lines[i].setAttribute('y2', y2.toFixed(1));
      });
      JOINTS.forEach((dot, i) => {
        const [x, y] = at(dot.joint);
        dots[i].setAttribute('cx', x.toFixed(1));
        dots[i].setAttribute('cy', y.toFixed(1));
      });
      const [hx, hy] = at('head');
      head.setAttribute('cx', hx.toFixed(1));
      head.setAttribute('cy', hy.toFixed(1));
      // The rating lands when the move does, like in the game.
      if (t === 1 && shown !== toIndex) {
        shown = toIndex;
        rating.textContent = MOVES[toIndex].rating;
        rating.style.color = MOVES[toIndex].rating === 'GOOD' ? 'var(--right)' : 'var(--left)';
        rating.classList.remove('pop');
        void rating.offsetWidth; // restart the CSS animation
        rating.classList.add('pop');
      }
      this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  }
}
