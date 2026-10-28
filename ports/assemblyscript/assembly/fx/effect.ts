import { FB } from '../canvas';

/**
 * One scene. Go's fx.Effect is an interface; AssemblyScript has interfaces
 * too, but an abstract base class is what it dispatches best: a virtual call
 * is a switch on the object's class id, compiled into the module.
 */
export abstract class Effect {
  /** Rebuild whatever depends on the resolution. */
  abstract resize(w: i32, h: i32): void;
  /** Once per frame, before drawing. t is the time in seconds. */
  abstract prepare(t: f64, dt: f64, frame: i32, w: i32, h: i32): void;
  /** Draw rows [y0, y1) of fb. */
  abstract draw(fb: FB, y0: i32, y1: i32): void;
  /** The rung of the optimisation ladder; 0 is the optimised default. */
  setStep(n: i32): void {}
}
