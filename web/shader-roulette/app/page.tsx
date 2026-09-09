'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ControlDock } from '@/app/components/control-dock';
import {
  ShaderStage,
  type ShaderStageHandle,
} from '@/app/components/shader-stage';
import { generateGenome } from '@/app/lib/generative/genome';
import { newRandomSeed, readSeed, seedHref } from '@/app/lib/seed-url';
import { titleForGenome } from '@/app/lib/title';
import { registerGenerateShaderTool } from '@/app/lib/webmcp';

const INITIAL_SEED = 0x8f31c7a2;

export default function Home() {
  const [seed, setSeed] = useState(INITIAL_SEED);
  const [paused, setPaused] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [mode, setMode] = useState<'webgl2' | 'canvas2d'>('webgl2');
  const [message, setMessage] = useState('');
  const [exporting, setExporting] = useState(false);
  const stageRef = useRef<ShaderStageHandle>(null);
  const messageTimer = useRef<number | null>(null);
  const genome = useMemo(() => generateGenome(seed), [seed]);
  const title = useMemo(() => titleForGenome(genome), [genome]);
  const description = `${title}: ${genome.dimension} ${genome.geometry}, ${genome.material} material`;

  const announce = useCallback((value: string) => {
    setMessage(value);
    if (messageTimer.current) window.clearTimeout(messageTimer.current);
    messageTimer.current = window.setTimeout(() => setMessage(''), 2200);
  }, []);

  const applySeed = useCallback((nextSeed: number) => {
    setSeed(nextSeed >>> 0);
    window.history.replaceState(
      null,
      '',
      seedHref(nextSeed, new URL(window.location.href)),
    );
  }, []);

  const reroll = useCallback(() => {
    applySeed(newRandomSeed());
    announce('Новая форма');
  }, [announce, applySeed]);

  const handleStageError = useCallback(
    (error: string) => {
      setMode('canvas2d');
      announce(error);
    },
    [announce],
  );

  useEffect(() => {
    const urlSeed = readSeed(window.location.search);
    if (urlSeed !== null) setSeed(urlSeed);
    else applySeed(INITIAL_SEED);
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => {
      setReducedMotion(query.matches);
      if (query.matches) setPaused(true);
    };
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, [applySeed]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (
        event.code !== 'Space' ||
        target?.closest('button, a, input, textarea, select')
      )
        return;
      event.preventDefault();
      reroll();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [reroll]);

  useEffect(
    () =>
      registerGenerateShaderTool(({ seed: requestedSeed }) => {
        const nextSeed = requestedSeed ?? newRandomSeed();
        applySeed(nextSeed);
        const nextGenome = generateGenome(nextSeed);
        return { seed: nextSeed, title: titleForGenome(nextGenome) };
      }),
    [applySeed],
  );

  const copyLink = async () => {
    const link = seedHref(seed, new URL(window.location.href));
    try {
      await navigator.clipboard.writeText(link);
    } catch {
      const input = document.createElement('textarea');
      input.value = link;
      input.style.position = 'fixed';
      input.style.opacity = '0';
      document.body.appendChild(input);
      input.select();
      document.execCommand('copy');
      input.remove();
    }
    announce('Ссылка скопирована');
  };

  const download = async () => {
    if (!stageRef.current || exporting) return;
    setExporting(true);
    try {
      const blob = await stageRef.current.exportPng();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `shader-roulette-${seed.toString(16).toUpperCase().padStart(8, '0')}.png`;
      anchor.click();
      URL.revokeObjectURL(url);
      announce('PNG готов');
    } catch (error) {
      announce(
        error instanceof Error ? error.message : 'Не удалось скачать PNG',
      );
    } finally {
      setExporting(false);
    }
  };

  return (
    <main className="roulette-shell">
      <ShaderStage
        ref={stageRef}
        genome={genome}
        paused={paused}
        reducedMotion={reducedMotion}
        description={description}
        onError={handleStageError}
        onMode={setMode}
        onReroll={reroll}
      />
      <header className="site-header">
        <p className="wordmark">SHADER ROULETTE</p>
        <p className="counter">∞ / {genome.geometry.toUpperCase()}</p>
      </header>
      <section className="identity" aria-live="polite">
        <p className="eyebrow">
          {genome.dimension} · {genome.material}
        </p>
        <h1>{title}</h1>
      </section>
      {mode === 'canvas2d' ? (
        <span className="mode-badge">Canvas mode</span>
      ) : null}
      <ControlDock
        paused={paused}
        exporting={exporting}
        seedLabel={`#${seed.toString(16).toUpperCase().slice(-4).padStart(4, '0')}`}
        onReroll={reroll}
        onTogglePaused={() => setPaused((value) => !value)}
        onCopy={copyLink}
        onDownload={download}
      />
      <p
        className={`toast-message ${message ? 'is-visible' : ''}`}
        aria-live="polite"
        aria-atomic="true"
      >
        {message}
      </p>
      <p className="space-hint" aria-hidden="true">
        SPACE TO REROLL
      </p>
    </main>
  );
}
