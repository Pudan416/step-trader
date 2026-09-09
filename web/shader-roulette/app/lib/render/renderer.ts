import type { VisualGenome } from '../generative/types.ts';
import { drawFallback } from './canvas-fallback.ts';
import { WebGLSceneRenderer } from './webgl-renderer.ts';

export type SceneRenderer = {
  readonly kind: 'webgl2' | 'canvas2d';
  setGenome(genome: VisualGenome): void;
  setPaused(paused: boolean): void;
  resize(width: number, height: number): void;
  renderFrame(time: number): void;
  exportPng(time: number): Promise<Blob>;
  dispose(): void;
};

export function pixelSize(
  cssWidth: number,
  cssHeight: number,
  devicePixelRatio: number,
): { width: number; height: number } {
  const ratio = Math.max(1, Math.min(2, devicePixelRatio || 1));
  return {
    width: Math.max(1, Math.round(cssWidth * ratio)),
    height: Math.max(1, Math.round(cssHeight * ratio)),
  };
}

class CanvasSceneRenderer implements SceneRenderer {
  readonly kind = 'canvas2d' as const;
  private genome: VisualGenome | null = null;
  private paused = false;
  private canvas: HTMLCanvasElement;
  private context: CanvasRenderingContext2D;

  constructor(canvas: HTMLCanvasElement, context: CanvasRenderingContext2D) {
    this.canvas = canvas;
    this.context = context;
  }

  setGenome(genome: VisualGenome): void {
    this.genome = genome;
  }

  setPaused(paused: boolean): void {
    this.paused = paused;
  }

  resize(width: number, height: number): void {
    if (this.canvas.width !== width) this.canvas.width = width;
    if (this.canvas.height !== height) this.canvas.height = height;
  }

  renderFrame(time: number): void {
    if (!this.genome) return;
    drawFallback(
      this.context,
      this.genome,
      this.canvas.width,
      this.canvas.height,
      this.paused ? 0 : time,
    );
  }

  async exportPng(time: number): Promise<Blob> {
    if (!this.genome) throw new Error('Фигура ещё не готова');
    const output = document.createElement('canvas');
    output.width = 2048;
    output.height = 2048;
    const context = output.getContext('2d');
    if (!context) throw new Error('Экспорт недоступен в этом браузере');
    drawFallback(context, this.genome, 2048, 2048, this.paused ? 0 : time);
    const blob = await new Promise<Blob | null>((resolve) =>
      output.toBlob(resolve, 'image/png'),
    );
    if (!blob) throw new Error('Не удалось собрать PNG');
    return blob;
  }

  dispose(): void {}
}

export function createRenderer(
  canvas: HTMLCanvasElement,
  onError: (message: string) => void,
): SceneRenderer {
  const gl = canvas.getContext('webgl2', {
    alpha: false,
    antialias: true,
    powerPreference: 'high-performance',
    preserveDrawingBuffer: false,
  });
  if (gl) {
    try {
      return new WebGLSceneRenderer(canvas, gl, onError);
    } catch (error) {
      onError(error instanceof Error ? error.message : 'WebGL не запустился');
    }
  }
  const context = canvas.getContext('2d');
  if (!context) throw new Error('Этот браузер не поддерживает Canvas');
  return new CanvasSceneRenderer(canvas, context);
}
