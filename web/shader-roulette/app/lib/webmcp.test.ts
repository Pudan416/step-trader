import assert from 'node:assert/strict';
import test from 'node:test';

import { parseGenerateShaderInput } from './webmcp.ts';

test('accepts an omitted seed or an unsigned 32-bit seed', () => {
  assert.deepEqual(parseGenerateShaderInput({}), {});
  assert.deepEqual(parseGenerateShaderInput({ seed: 36657 }), { seed: 36657 });
});

test('rejects malformed WebMCP generation input', () => {
  assert.throws(
    () => parseGenerateShaderInput({ seed: -1 }),
    /unsigned 32-bit/,
  );
  assert.throws(
    () => parseGenerateShaderInput({ seed: '36657' }),
    /unsigned 32-bit/,
  );
});
