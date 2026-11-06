import { toFixed } from 'common/math';

// hippie -- shared by the redone power windows (Apc.js, Smes.js,
// PowerMonitor.js)

// Watts as the game writes them (DisplayPower): W, kW, MW, GW
export const formatPower = watts => {
  const value = Math.abs(watts || 0);
  const units = [[1e9, 'GW'], [1e6, 'MW'], [1e3, 'kW']];
  for (let [size, unit] of units) {
    if (value >= size) {
      const scaled = (watts || 0) / size;
      return toFixed(scaled, scaled < 10 ? 2 : 1) + ' ' + unit;
    }
  }
  return toFixed(watts || 0) + ' W';
};

// "4 min", "1 h 5 min", "40 s"
export const formatDuration = seconds => {
  if (seconds === null || seconds === undefined) {
    return null;
  }
  if (seconds < 60) {
    return Math.round(seconds) + ' s';
  }
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) {
    return minutes + ' min';
  }
  return Math.floor(minutes / 60) + ' h ' + (minutes % 60) + ' min';
};

// A channel's status from the APC: 0 off, 1 off by auto, 2 on, 3 on by auto
export const channelOn = status => status >= 2;
export const channelAuto = status => status === 1 || status === 3;
