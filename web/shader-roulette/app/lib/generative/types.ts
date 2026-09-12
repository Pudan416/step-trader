export type DimensionMode = 'graphic' | 'volumetric' | 'hybrid';

export type GeometryFamily =
  | 'organism'
  | 'relic'
  | 'ribbon'
  | 'glyph'
  | 'field'
  | 'constellation';

export type MaterialFamily =
  | 'matte'
  | 'glass'
  | 'film'
  | 'plasma'
  | 'metal'
  | 'ink'
  | 'contour';

export type PaletteRoles = {
  background: string;
  dark: string;
  light: string;
  accent: string;
  emission: string;
};

export type RareMutation =
  | 'slice'
  | 'hollow-core'
  | 'chromatic-edge'
  | 'satellite'
  | 'flatland';

export type VisualGenome = {
  sculpture?: Sculpture;
  identity?: string;
  flat?: { family: FlatFamily; variation: number };
  seed: number;
  dimension: DimensionMode;
  geometry: GeometryFamily;
  material: MaterialFamily;
  palette: PaletteRoles;
  params: {
    scale: number;
    rotation: number;
    lobes: number;
    warp: number;
    hollow: number;
    thickness: number;
    roughness: number;
    metallic: number;
    transmission: number;
    bloom: number;
    grain: number;
    cameraZ: number;
    satelliteCount: number;
  };
  motion: { tempo: number; breathe: number; orbit: number; phase: number };
  rareMutation: [] | [RareMutation];
  title: string;
};

export type FlatFamily =
  | 'rosette'
  | 'spark'
  | 'organism'
  | 'loop'
  | 'crescent'
  | 'emblem'
  | 'fan'
  | 'ribbon';

export type Collection = 'all' | 'new' | 'classic';
export type Sculpture = {
  model: number;
  points: number[];
  section: number;
  folds: number;
  twist: number;
  relief: number;
  etching: number;
};
