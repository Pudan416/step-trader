'use client';

import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from 'react';

import type { VisualGenome } from '@/app/lib/generative/types';
import {
  createRenderer,
  pixelSize,
  type SceneRenderer,
} from '@/app/lib/render/renderer';

export type ShaderStageHandle = { exportPng(): Promise<Blob> };

type ShaderStageProps = {
  genome: VisualGenome;
  paused: boolean;
  reducedMotion: boolean;
  description: string;
  onError(message: string): void;
  onMode(mode: SceneRenderer['kind']): void;
  onReroll(): void;
};

type ActiveRenderer = { renderer: SceneRenderer; getTime: () => number };

function CanvasLayer({
  genome,
  paused,
  active,
  hidden,
  reducedMotion,
  description,
  onError,
  onMode,
  onActivate,
}: {
  genome: VisualGenome;
  paused: boolean;
  active: boolean;
  hidden: boolean;
  reducedMotion: boolean;
  description: string;
  onError(message: string): void;
  onMode(mode: SceneRenderer['kind']): void;
  onActivate(value: ActiveRenderer): void;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const pausedRef = useRef(paused || reducedMotion);

  useEffect(() => {
    pausedRef.current = paused || reducedMotion;
  }, [paused, reducedMotion]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let renderer: SceneRenderer;
    try {
      renderer = createRenderer(canvas, onError);
    } catch (error) {
      onError(
        error instanceof Error ? error.message : 'Графика не запустилась',
      );
      return;
    }
    renderer.setGenome(genome);
    const startedAt = performance.now();
    let frozenAt = 0;
    let frame = 0;
    const getTime = () =>
      pausedRef.current ? frozenAt : (performance.now() - startedAt) / 1000;
    const resize = () => {
      const bounds = canvas.getBoundingClientRect();
      const size = pixelSize(
        bounds.width,
        bounds.height,
        window.devicePixelRatio,
      );
      renderer.resize(size.width, size.height);
    };
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    resize();
    const loop = () => {
      const nextTime = getTime();
      if (!pausedRef.current) frozenAt = nextTime;
      renderer.setPaused(pausedRef.current);
      renderer.renderFrame(nextTime);
      frame = requestAnimationFrame(loop);
    };
    loop();
    onMode(renderer.kind);
    if (active) onActivate({ renderer, getTime });
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
      renderer.dispose();
    };
  }, [active, genome, onActivate, onError, onMode]);

  return (
    <canvas
      ref={canvasRef}
      className={`shader-canvas ${active ? 'is-active' : 'is-leaving'}`}
      role={hidden ? undefined : 'img'}
      aria-hidden={hidden || undefined}
      aria-label={hidden ? undefined : description}
    />
  );
}

export const ShaderStage = forwardRef<ShaderStageHandle, ShaderStageProps>(
  function ShaderStage(
    { genome, paused, reducedMotion, description, onError, onMode, onReroll },
    ref,
  ) {
    const [layers, setLayers] = useState<VisualGenome[]>([genome]);
    const activeRenderer = useRef<ActiveRenderer | null>(null);

    useEffect(() => {
      const frame = window.requestAnimationFrame(() =>
        setLayers((current) =>
          current.at(-1)?.seed === genome.seed
            ? current
            : reducedMotion
              ? [genome]
              : [current.at(-1) ?? genome, genome],
        ),
      );
      const timer = reducedMotion
        ? null
        : window.setTimeout(() => setLayers([genome]), 520);
      return () => {
        window.cancelAnimationFrame(frame);
        if (timer !== null) window.clearTimeout(timer);
      };
    }, [genome, reducedMotion]);

    const activate = useCallback((value: ActiveRenderer) => {
      activeRenderer.current = value;
    }, []);

    useImperativeHandle(ref, () => ({
      async exportPng() {
        const active = activeRenderer.current;
        if (!active) throw new Error('Фигура ещё не готова');
        return active.renderer.exportPng(active.getTime());
      },
    }));

    return (
      <button
        className="shader-stage"
        type="button"
        aria-label="Сгенерировать новую форму"
        onClick={onReroll}
      >
        {layers.map((layer, index) => {
          const active = index === layers.length - 1;
          return (
            <CanvasLayer
              key={`${layer.seed}-${index}`}
              genome={layer}
              paused={paused}
              active={active}
              hidden={!active}
              reducedMotion={reducedMotion}
              description={description}
              onError={onError}
              onMode={onMode}
              onActivate={activate}
            />
          );
        })}
      </button>
    );
  },
);
