import assert from 'node:assert/strict';
import test from 'node:test';
import { generateSculpture, generateCollection } from './sculpture.ts';
import { generateGenome } from './genome.ts';
import { readRecipe, recipeHref } from '../seed-url.ts';

test('classic collection returns the original artwork and mixed generation includes it', () => {
  assert.deepEqual(
    generateCollection(1357911, 0, 'classic'),
    generateGenome(1357911),
  );
  const corpus = Array.from({ length: 100 }, (_, seed) =>
    generateCollection(seed, 0, 'all'),
  );
  assert.ok(corpus.some((g) => g.sculpture));
  assert.ok(corpus.some((g) => !g.sculpture && !g.flat));
});

test('swept forms stay finite, broad, and safely inside their frame', () => {
  const signatures = new Set<string>();
  for (let seed = 0; seed < 256; seed++) {
    const g = generateSculpture(seed, seed % 3),
      s = g.sculpture!;
    assert.equal(s.points.length, 129 * 4);
    let minX = 2,
      maxX = -2,
      minY = 2,
      maxY = -2;
    for (let i = 0; i < s.points.length; i += 4) {
      const [x, y, r, z] = s.points.slice(i, i + 4);
      assert.ok([x, y, r, z].every(Number.isFinite));
      assert.ok(r! > 0.025 && r! < 0.4);
      assert.ok(Math.hypot(x!, y!) + r! <= 0.86, `${seed}: clipped figure`);
      minX = Math.min(minX, x! - r!);
      maxX = Math.max(maxX, x! + r!);
      minY = Math.min(minY, y! - r!);
      maxY = Math.max(maxY, y! + r!);
    }
    assert.ok(
      maxX - minX > 0.8 && maxY - minY > 0.65,
      `${seed}: collapses into a strip`,
    );
    signatures.add(
      s.points
        .filter((_, i) => i % 16 === 0)
        .map((v) => v.toFixed(2))
        .join(','),
    );
  }
  assert.equal(signatures.size, 256);
});

test('variations preserve the construction and palette but change the geometry', () => {
  const a = generateSculpture(31),
    b = generateSculpture(31, 1);
  assert.equal(a.sculpture!.model, b.sculpture!.model);
  assert.deepEqual(a.palette, b.palette);
  assert.notDeepEqual(a.sculpture!.points, b.sculpture!.points);
  assert.deepEqual(b, generateSculpture(31, 1));
});

test('edition 3 links restore selection and variation without rewriting legacy URLs', () => {
  const recipe = {
    seed: 31,
    version: 3 as const,
    variation: 4,
    collection: 'classic' as const,
  };
  assert.deepEqual(
    readRecipe(
      new URL(recipeHref(recipe, new URL('https://example.com/'))).search,
    ),
    recipe,
  );
  assert.deepEqual(readRecipe('?seed=31'), {
    seed: 31,
    version: 1,
    variation: 0,
  });
});
