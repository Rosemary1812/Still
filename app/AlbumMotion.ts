import { Easing, reduceMotion, type AnimatedValue } from "nsh";

// Timings and curves of the album shelf at shopify.com/editions, in milliseconds.
export const liftMs = 1000;
export const dropMs = 400;
export const pullMs = 700;
export const introMs = 400;
export const staggerMs = 75;
/** How far a cover rises off its shelf, as a share of its side, and how far it leans back at rest, in degrees. */
export const rise = 0.107;
export const recline = 14.9;
/** How far the camera is from the shelves, in cover sides. */
export const camera = 18.1;
/** The detail view shows a cover this many times its size on the shelf. */
export const closeUp = 1.58;
export const outQuart = Easing.out(Easing.poly(4));
export const inQuart = Easing.in(Easing.poly(4));
// SwiftUI's spring(response: 0.35, dampingFraction: 0.85) of the CD cabinet.
export const spineSpring = { stiffness: 322, damping: 30.5, mass: 1 };

type Ended = Promise<{ finished: boolean }>;

/** Moves a value along the pull-out curve: a cubic ease-in over the first 30%, then a cubic ease-out. */
export function pull(value: AnimatedValue, from: number, to: number): Ended {
  if (reduceMotion()) { value.set(to); return Promise.resolve({ finished: true }); }
  return value.keyframes([
    { offset: 0, value: from, easing: Easing.in(Easing.cubic) },
    { offset: 0.3, value: from + (to - from) * 0.3, easing: Easing.out(Easing.cubic) },
    { offset: 1, value: to },
  ], { duration: pullMs });
}

/** Leans a cover after the pointer on a loose spring; `reach` is the largest angle about x and y, in degrees. */
export function lean(rx: AnimatedValue, ry: AnimatedValue, at: { x: number; y: number }, size: number, reach: [number, number], mass = 1) {
  if (reduceMotion() || size <= 0) return;
  const spring = { stiffness: 80, damping: 6, mass };
  rx.spring(reach[0] * (2 * at.y / size - 1), spring);
  ry.spring(reach[1] * (2 * at.x / size - 1), spring);
}

export function settle(rx: AnimatedValue, ry: AnimatedValue) {
  rx.timing(0, { duration: dropMs * 2, easing: outQuart });
  ry.timing(0, { duration: dropMs * 2, easing: outQuart });
}
