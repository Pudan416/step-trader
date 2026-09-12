import assert from 'node:assert/strict';
import test from 'node:test';
import { generateArtwork } from './flat-genome.ts';
import { readRecipe, recipeHref } from '../seed-url.ts';

test('new artwork is a bounded flat figure and reaches distinct families', () => {
  const families = new Set<string>();
  for (let seed = 0; seed < 512; seed++) {
    const g = generateArtwork(seed);
    assert.equal(g.dimension, 'graphic');
    assert.ok(g.flat);
    families.add(g.flat.family);
    assert.equal(g.params.satelliteCount, 0);
    assert.ok(g.params.scale <= 1);
  }
  assert.ok(families.size >= 8);
});

test('variations keep family, palette and identity while changing shape parameters', () => {
  for (const seed of [0, 1, 31, 0xffffffff]) {
    const original = generateArtwork(seed);
    const varied = generateArtwork(seed, 1);
    assert.equal(varied.flat?.family, original.flat?.family);
    assert.deepEqual(varied.palette, original.palette);
    assert.equal(varied.seed, seed);
    assert.notDeepEqual(varied.params, original.params);
    assert.deepEqual(varied, generateArtwork(seed, 1));
  }
});

test('shared variation links restore the entire recipe and old links stay legacy', () => {
  const url = new URL(recipeHref({seed: 31, version: 2, variation: 7}, new URL('https://example.com/?old=1')));
  assert.deepEqual(readRecipe(url.search), {seed: 31, version: 2, variation: 7});
  assert.deepEqual(readRecipe('?seed=0x0000001F'), {seed: 31, version: 1, variation: 0});
  assert.equal(readRecipe('?seed=garbage'), null);
  assert.deepEqual(readRecipe('?seed=31&v=2&variation=-3'), {seed: 31, version: 2, variation: 0});
});
