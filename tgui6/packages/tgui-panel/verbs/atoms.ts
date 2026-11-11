import type { VerbArgBase } from 'common/verb-constants';
import { atom } from 'jotai';

export type VerbArg = VerbArgBase & {
  name: string;
};

export type Verb = {
  type: string;
  name: string;
  args: VerbArg[];
};

export type Target = {
  name: string;
  ref: string;
};

export const adminVerbsAtom = atom<Verb[]>([]);
export const adminTargetsAtom = atom<Target[]>([]);
export const typepathsAtom = atom<string[]>([]);
export const focusCommandBarAtom = atom<number>(0);
// hippie -- what a focus asks for: a talk key's verb (and text after it), or a
// key typed on the map in classic mode
export type FocusRequest = {
  verb?: string;
  prefill?: string;
  // the letter a talk key types, for when it was really typed (see CommandBar)
  typed?: string;
} | null;
export const focusRequestAtom = atom<FocusRequest>(null);
export const clearCommandBarAtom = atom<number>(0);
export const initializeCommandBarAtom = atom<number>(0);
export const hotkeysAtom = atom<boolean>(true);
