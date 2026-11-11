/**
 * A ProgressBar's colors, stored as { mode, hi, lo }:
 *   high - good at or above hi, average between, bad below lo
 *   low  - good at or below lo, average between, bad above hi
 */

export const RANGE_MODES = [
  { mode: 'none', label: 'One color' },
  { mode: 'high', label: 'High is good' },
  { mode: 'low', label: 'Low is good' },
];

const num = (value, fallback) => {
  const n = Number(value);
  return value === '' || value === undefined || !Number.isFinite(n)
    ? fallback : n;
};

export const rangesObject = r => {
  if (!r || !r.mode || r.mode === 'none') {
    return {};
  }
  const hi = num(r.hi, 0.66);
  const lo = num(r.lo, 0.33);
  if (r.mode === 'high') {
    return {
      good: [hi, Infinity],
      average: [lo, hi],
      bad: [-Infinity, lo],
    };
  }
  return {
    good: [-Infinity, lo],
    average: [lo, hi],
    bad: [hi, Infinity],
  };
};

/** The ranges as lines of JS object literal (without the braces). */
export const rangesLines = r => {
  const obj = rangesObject(r);
  const show = n => {
    if (n === Infinity) {
      return 'Infinity';
    }
    if (n === -Infinity) {
      return '-Infinity';
    }
    return String(n);
  };
  return Object.keys(obj).map(name => (
    `${name}: [${show(obj[name][0])}, ${show(obj[name][1])}],`
  ));
};
