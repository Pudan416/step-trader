import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DIMENSION_IDS,
  FRAGMENT_SHADER_SOURCE,
  GEOMETRY_IDS,
  MATERIAL_IDS,
  VERTEX_SHADER_SOURCE,
} from './shaders.ts';

test('the shader pair targets WebGL2', () => {
  assert.match(VERTEX_SHADER_SOURCE, /^#version 300 es/);
  assert.match(FRAGMENT_SHADER_SOURCE, /^#version 300 es/);
});

test('the fragment shader declares every renderer uniform', () => {
  for (const name of [
    'u_resolution',
    'u_time',
    'u_geometry',
    'u_material',
    'u_dimension',
    'u_palette0',
    'u_palette1',
    'u_palette2',
    'u_palette3',
    'u_params0',
    'u_params1',
  ]) {
    assert.match(
      FRAGMENT_SHADER_SOURCE,
      new RegExp(`uniform\\s+[^;]+\\s+${name}\\s*;`),
    );
  }
});

test('renderer ids include all public genome selectors', () => {
  assert.equal(Object.keys(GEOMETRY_IDS).length, 6);
  assert.equal(Object.keys(MATERIAL_IDS).length, 7);
  assert.equal(Object.keys(DIMENSION_IDS).length, 3);
});
