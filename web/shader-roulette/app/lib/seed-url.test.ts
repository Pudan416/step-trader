import assert from 'node:assert/strict';
import test from 'node:test';

import { readSeed, seedHref } from './seed-url.ts';

test('reads decimal and hexadecimal seeds', () => {
  assert.equal(readSeed('?seed=36657'), 36657);
  assert.equal(readSeed('?seed=0x8f31'), 36657);
});

test('rejects missing, negative, and overflowing seeds', () => {
  assert.equal(readSeed(''), null);
  assert.equal(readSeed('?seed=-1'), null);
  assert.equal(readSeed('?seed=4294967296'), null);
});

test('writes an eight-digit hexadecimal seed without discarding the base path', () => {
  assert.equal(
    seedHref(0x8f31, new URL('https://example.com/art?old=1')),
    'https://example.com/art?seed=0x00008F31',
  );
});
