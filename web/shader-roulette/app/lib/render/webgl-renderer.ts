import type { VisualGenome } from '../generative/types.ts';
import { FLAT_FRAGMENT_SHADER, FLAT_IDS } from './flat-shaders.ts';
import { SCULPTURE_FRAGMENT_SHADER } from './sculpture-shader.ts';
import {
  DIMENSION_IDS,
  FRAGMENT_SHADER_SOURCE,
  GEOMETRY_IDS,
  MATERIAL_IDS,
  VERTEX_SHADER_SOURCE,
} from './shaders.ts';

function compile(
  gl: WebGL2RenderingContext,
  type: number,
  source: string,
): WebGLShader {
  const shader = gl.createShader(type);
  if (!shader) throw new Error('Не удалось создать шейдер');
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const message = gl.getShaderInfoLog(shader) || 'Неизвестная ошибка шейдера';
    gl.deleteShader(shader);
    throw new Error(message);
  }
  return shader;
}

function link(
  gl: WebGL2RenderingContext,
  kind: 'classic' | 'flat' | 'sculpture' = 'classic',
): WebGLProgram {
  const vertex = compile(gl, gl.VERTEX_SHADER, VERTEX_SHADER_SOURCE);
  const fragment = compile(
    gl,
    gl.FRAGMENT_SHADER,
    kind === 'sculpture'
      ? SCULPTURE_FRAGMENT_SHADER
      : kind === 'flat'
        ? FLAT_FRAGMENT_SHADER
        : FRAGMENT_SHADER_SOURCE,
  );
  const program = gl.createProgram();
  if (!program) throw new Error('Не удалось создать графическую программу');
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const message =
      gl.getProgramInfoLog(program) || 'Не удалось связать шейдеры';
    gl.deleteProgram(program);
    throw new Error(message);
  }
  return program;
}

function color(hex: string): [number, number, number] {
  return [1, 3, 5].map((index) => {
    const srgb = Number.parseInt(hex.slice(index, index + 2), 16) / 255;
    return srgb <= 0.04045 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4;
  }) as [number, number, number];
}

export class WebGLSceneRenderer {
  readonly kind = 'webgl2' as const;
  private gl: WebGL2RenderingContext;
  private program: WebGLProgram | null = null;
  private vao: WebGLVertexArrayObject | null = null;
  private genome: VisualGenome | null = null;
  private lost = false;
  private disposed = false;
  private canvas: HTMLCanvasElement;
  private onError: (message: string) => void;

  constructor(
    canvas: HTMLCanvasElement,
    gl: WebGL2RenderingContext,
    onError: (message: string) => void,
  ) {
    this.canvas = canvas;
    this.gl = gl;
    this.onError = onError;
    this.handleLost = this.handleLost.bind(this);
    this.handleRestored = this.handleRestored.bind(this);
    canvas.addEventListener('webglcontextlost', this.handleLost);
    canvas.addEventListener('webglcontextrestored', this.handleRestored);
    this.rebuild();
  }

  private rebuild(): void {
    if (this.program) this.gl.deleteProgram(this.program);
    if (this.vao) this.gl.deleteVertexArray(this.vao);
    this.program = link(
      this.gl,
      this.genome?.sculpture
        ? 'sculpture'
        : this.genome?.flat
          ? 'flat'
          : 'classic',
    );
    this.vao = this.gl.createVertexArray();
    this.gl.bindVertexArray(this.vao);
    this.gl.useProgram(this.program);
    if (this.genome) this.uploadGenome(this.genome);
  }

  private handleLost(event: Event): void {
    event.preventDefault();
    this.lost = true;
  }

  private handleRestored(): void {
    try {
      this.lost = false;
      this.rebuild();
    } catch (error) {
      this.onError(
        error instanceof Error
          ? error.message
          : 'Не удалось восстановить графику',
      );
    }
  }

  private uniform(name: string): WebGLUniformLocation | null {
    return this.program ? this.gl.getUniformLocation(this.program, name) : null;
  }

  private uploadGenome(genome: VisualGenome): void {
    const gl = this.gl;
    gl.useProgram(this.program);
    gl.uniform1i(
      this.uniform('u_geometry'),
      genome.sculpture
        ? genome.sculpture.model
        : genome.flat
          ? FLAT_IDS[genome.flat.family]
          : GEOMETRY_IDS[genome.geometry],
    );
    gl.uniform1i(this.uniform('u_material'), MATERIAL_IDS[genome.material]);
    gl.uniform1i(this.uniform('u_dimension'), DIMENSION_IDS[genome.dimension]);
    gl.uniform3fv(this.uniform('u_palette0'), color(genome.palette.background));
    gl.uniform3fv(this.uniform('u_palette1'), color(genome.palette.dark));
    gl.uniform3fv(this.uniform('u_palette2'), color(genome.palette.light));
    gl.uniform3fv(this.uniform('u_palette3'), color(genome.palette.accent));
    gl.uniform4f(
      this.uniform('u_params0'),
      genome.params.scale,
      genome.params.rotation,
      genome.params.lobes,
      genome.params.warp,
    );
    gl.uniform4f(
      this.uniform('u_params1'),
      genome.params.hollow,
      genome.params.thickness,
      genome.params.roughness,
      genome.params.bloom,
    );
    gl.uniform4f(
      this.uniform('u_motion'),
      genome.motion.tempo,
      genome.motion.breathe,
      genome.motion.orbit,
      genome.motion.phase,
    );
    gl.uniform1f(this.uniform('u_seed'), genome.seed % 65521);
    gl.uniform1f(this.uniform('u_camera'), genome.params.cameraZ);
    gl.uniform1i(this.uniform('u_satellites'), genome.params.satelliteCount);
    gl.uniform1f(
      this.uniform('u_frameFit'),
      genome.identity?.startsWith('3-') ? 1 : 0,
    );
    if (genome.sculpture) {
      const s = genome.sculpture;
      gl.uniform4fv(this.uniform('u_points[0]'), new Float32Array(s.points));
      gl.uniform4f(
        this.uniform('u_surface'),
        s.section,
        s.folds,
        s.twist,
        s.relief,
      );
      gl.uniform1f(this.uniform('u_etching'), s.etching);
    }
  }

  setGenome(genome: VisualGenome): void {
    const changedEdition =
      !!this.genome?.flat !== !!genome.flat ||
      !!this.genome?.sculpture !== !!genome.sculpture;
    this.genome = genome;
    if (changedEdition && !this.lost) this.rebuild();
    if (!this.lost) this.uploadGenome(genome);
  }

  // The stage owns elapsed time and passes the frozen frame while paused.
  setPaused(_paused: boolean): void {}

  resize(width: number, height: number): void {
    if (this.canvas.width !== width) this.canvas.width = width;
    if (this.canvas.height !== height) this.canvas.height = height;
    this.gl.viewport(0, 0, width, height);
  }

  renderFrame(time: number): void {
    if (this.disposed || this.lost || !this.program || !this.genome) return;
    this.gl.useProgram(this.program);
    this.gl.bindVertexArray(this.vao);
    this.gl.uniform2f(
      this.uniform('u_resolution'),
      this.canvas.width,
      this.canvas.height,
    );
    this.gl.uniform1f(this.uniform('u_time'), time);
    this.gl.drawArrays(this.gl.TRIANGLES, 0, 3);
  }

  async exportPng(time: number): Promise<Blob> {
    const output = document.createElement('canvas');
    output.width = 2048;
    output.height = 2048;
    const gl = output.getContext('webgl2', {
      alpha: false,
      antialias: true,
      preserveDrawingBuffer: true,
    });
    if (!gl || !this.genome)
      throw new Error('Экспорт недоступен в этом браузере');
    const renderer = new WebGLSceneRenderer(output, gl, this.onError);
    renderer.setGenome(this.genome);
    renderer.resize(2048, 2048);
    renderer.renderFrame(time);
    const blob = await new Promise<Blob | null>((resolve) =>
      output.toBlob(resolve, 'image/png'),
    );
    renderer.dispose();
    if (!blob) throw new Error('Не удалось собрать PNG');
    return blob;
  }

  dispose(): void {
    this.disposed = true;
    this.canvas.removeEventListener('webglcontextlost', this.handleLost);
    this.canvas.removeEventListener(
      'webglcontextrestored',
      this.handleRestored,
    );
    if (this.vao) this.gl.deleteVertexArray(this.vao);
    if (this.program) this.gl.deleteProgram(this.program);
    this.vao = null;
    this.program = null;
  }
}
