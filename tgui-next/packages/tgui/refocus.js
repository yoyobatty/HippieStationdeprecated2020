import { tridentVersion } from './byond';

export const refocusLayout = () => {
  // IE8: Focus method is seemingly fucked.
  // (tridentVersion is null on non-Trident engines; `null <= 4` is true in JS)
  if (tridentVersion !== null && tridentVersion <= 4) {
    return;
  }
  const element = document.getElementById('Layout__content');
  if (element) {
    element.focus();
  }
};
