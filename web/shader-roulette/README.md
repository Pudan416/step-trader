# Shader Roulette

A one-page generative-art engine built around deterministic visual genomes. Each unsigned 32-bit seed selects a coherent geometry family, material, palette, composition, and motion profile; the same seed always recreates the same identity.

## Local development

```bash
npm run dev
npm test
npm run build
```

The app uses WebGL2 for its full renderer and falls back to deterministic Canvas 2D artwork when WebGL2 is unavailable. Use `?seed=0x00008F31` to reopen a particular result.
