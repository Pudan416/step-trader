import assert from 'node:assert/strict';
import test from 'node:test';

import { createRenderer, pixelSize } from './renderer.ts';

test('renderer uses deterministic fallback when WebGL2 is absent', () => {
  const context2d = { save() {}, restore() {} };
  const canvas = {
    getContext(kind: string) {
      return kind === '2d' ? context2d : null;
    },
    addEventListener() {},
    removeEventListener() {},
  };
  const renderer = createRenderer(
    canvas as unknown as HTMLCanvasElement,
    () => {},
  );
  assert.equal(renderer.kind, 'canvas2d');
});

test('preview dimensions cap device pixel ratio at two', () => {
  assert.deepEqual(pixelSize(375, 667, 3), { width: 750, height: 1334 });
});

test('preview dimensions never use a ratio below one', () => {
  assert.deepEqual(pixelSize(320, 240, 0.5), { width: 320, height: 240 });
});
