// The generated reference, as the page imports it. plugins/site.ts makes the virtual module from the repository's
// files at build time (plugins/repo.ts), so the page never reads the disk.
import data from 'virtual:shipyard-reference';
import type { ReferenceData } from '../../plugins/repo';

export const REF = data as ReferenceData;
