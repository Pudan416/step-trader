export type GenerateShaderInput = { seed?: number };

export function parseGenerateShaderInput(value: unknown): GenerateShaderInput {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(
      'Input must be an object with an optional unsigned 32-bit seed',
    );
  }
  const entries = Object.entries(value);
  if (entries.some(([key]) => key !== 'seed'))
    throw new TypeError('Only seed is supported');
  const seed = (value as { seed?: unknown }).seed;
  if (seed === undefined) return {};
  if (
    !Number.isInteger(seed) ||
    (seed as number) < 0 ||
    (seed as number) > 0xffffffff
  ) {
    throw new TypeError('seed must be an unsigned 32-bit integer');
  }
  return { seed: seed as number };
}

type ModelContext = {
  registerTool(
    tool: {
      name: string;
      title: string;
      description: string;
      inputSchema: object;
      annotations: { readOnlyHint: false; untrustedContentHint: false };
      execute(input: unknown): unknown | Promise<unknown>;
    },
    options: { signal: AbortSignal },
  ): void | Promise<void>;
};

export function registerGenerateShaderTool(
  execute: (input: GenerateShaderInput) => { seed: number; title: string },
): () => void {
  const context = (document as Document & { modelContext?: ModelContext })
    .modelContext;
  if (!context?.registerTool) return () => {};
  const lifecycle = new AbortController();
  try {
    void Promise.resolve(
      context.registerTool(
        {
          name: 'generate_shader',
          title: 'Generate shader artwork',
          description:
            'Generate and visibly display a new Shader Roulette artwork, optionally using a reproducible unsigned 32-bit seed.',
          inputSchema: {
            type: 'object',
            properties: {
              seed: { type: 'integer', minimum: 0, maximum: 4294967295 },
            },
            additionalProperties: false,
          },
          annotations: { readOnlyHint: false, untrustedContentHint: false },
          execute(input) {
            return execute(parseGenerateShaderInput(input));
          },
        },
        { signal: lifecycle.signal },
      ),
    ).catch(() => {});
  } catch {
    return () => lifecycle.abort();
  }
  return () => lifecycle.abort();
}
