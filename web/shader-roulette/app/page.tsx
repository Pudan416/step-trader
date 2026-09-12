'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ControlDock } from '@/app/components/control-dock';
import {
  ShaderStage,
  type ShaderStageHandle,
} from '@/app/components/shader-stage';
import { generateGenome } from '@/app/lib/generative/genome';
import {
  generateArtwork,
  FAMILY_LABELS,
} from '@/app/lib/generative/flat-genome';
import {
  newRandomSeed,
  readRecipe,
  recipeHref,
  type Recipe,
} from '@/app/lib/seed-url';
import { titleForGenome } from '@/app/lib/title';
import { registerGenerateShaderTool } from '@/app/lib/webmcp';
import {
  generateCollection,
  finishLabel,
} from '@/app/lib/generative/sculpture';
import type { Collection } from '@/app/lib/generative/types';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';

const INITIAL_SEED = 0x8f31c7a2;

export default function Home() {
  const [recipe, setRecipe] = useState<Recipe>({
    seed: INITIAL_SEED,
    version: 3,
    variation: 0,
    collection: 'all',
  });
  const { seed } = recipe;
  const [paused, setPaused] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [mode, setMode] = useState<'webgl2' | 'canvas2d'>('webgl2');
  const [message, setMessage] = useState('');
  const [exporting, setExporting] = useState(false);
  const stageRef = useRef<ShaderStageHandle>(null);
  const messageTimer = useRef<number | null>(null);
  const genome = useMemo(() => {
    const g =
      recipe.version === 3
        ? generateCollection(seed, recipe.variation, recipe.collection)
        : recipe.version === 2
          ? generateArtwork(seed, recipe.variation)
          : generateGenome(seed);
    return {
      ...g,
      identity: `${recipe.version}-${seed}-${recipe.variation}-${recipe.collection ?? ''}`,
    };
  }, [seed, recipe]);
  const title = useMemo(
    () =>
      genome.flat || genome.sculpture ? genome.title : titleForGenome(genome),
    [genome],
  );
  const description = `${title}: ${genome.sculpture ? 'скульптурная форма' : genome.geometry}, ${finishLabel(genome)}, вариация ${recipe.variation + 1}`;

  const announce = useCallback((value: string) => {
    setMessage(value);
    if (messageTimer.current) window.clearTimeout(messageTimer.current);
    messageTimer.current = window.setTimeout(() => setMessage(''), 2200);
  }, []);

  const applyRecipe = useCallback((next: Recipe) => {
    setRecipe(next);
    window.history.replaceState(
      null,
      '',
      recipeHref(next, new URL(window.location.href)),
    );
  }, []);

  const reroll = useCallback(() => {
    let nextSeed = newRandomSeed();
    for (let i = 0; i < 16; i++) {
      const next = generateCollection(nextSeed, 0, recipe.collection);
      if (
        next.sculpture?.model !== genome.sculpture?.model ||
        next.geometry !== genome.geometry ||
        next.material !== genome.material
      )
        break;
      nextSeed = newRandomSeed();
    }
    applyRecipe({
      seed: nextSeed,
      version: 3,
      variation: 0,
      collection: recipe.collection ?? 'all',
    });
    announce('Новая форма');
  }, [announce, applyRecipe, genome, recipe.collection]);

  const vary = useCallback(() => {
    applyRecipe({
      ...recipe,
      seed,
      version: recipe.version === 1 ? 3 : recipe.version,
      collection: recipe.version === 1 ? 'classic' : recipe.collection,
      variation: (recipe.variation + 1) % 1000000,
    });
    announce('Новая вариация');
  }, [announce, applyRecipe, recipe, seed]);

  const handleStageError = useCallback(
    (error: string) => {
      setMode('canvas2d');
      announce(error);
    },
    [announce],
  );

  useEffect(() => {
    const urlRecipe = readRecipe(window.location.search);
    if (urlRecipe !== null) setRecipe(urlRecipe);
    else
      applyRecipe({
        seed: INITIAL_SEED,
        version: 3,
        variation: 0,
        collection: 'all',
      });
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => {
      setReducedMotion(query.matches);
      if (query.matches) setPaused(true);
    };
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, [applyRecipe]);

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
        applyRecipe({
          seed: nextSeed,
          version: 3,
          variation: 0,
          collection: recipe.collection ?? 'all',
        });
        const nextGenome = generateCollection(nextSeed, 0, recipe.collection);
        return {
          seed: nextSeed,
          title: nextGenome.sculpture
            ? nextGenome.title
            : titleForGenome(nextGenome),
        };
      }),
    [applyRecipe, recipe.collection],
  );

  const copyLink = async () => {
    const link = recipeHref(recipe, new URL(window.location.href));
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
      anchor.download = `shader-roulette-${seed.toString(16).toUpperCase().padStart(8, '0')}-v${recipe.version}-${recipe.variation}.png`;
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
    <main
      className={`roulette-shell ${genome.flat ? 'flat-edition' : ''} ${recipe.version === 3 ? 'sculpture-edition' : ''}`}
    >
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
        <p className="counter">
          {recipe.version === 3
            ? `${genome.sculpture ? 'STUDY' : 'CLASSIC'} / ${String(recipe.variation + 1).padStart(2, '0')}`
            : genome.flat
              ? `${FAMILY_LABELS[genome.flat.family]} / ${String(recipe.variation + 1).padStart(2, '0')}`
              : `∞ / ${genome.geometry.toUpperCase()}`}
        </p>
      </header>
      <ToggleGroup
        className="collection-switch"
        aria-label="Коллекция форм"
        value={[
          recipe.version === 3
            ? (recipe.collection ?? 'all')
            : recipe.version === 1
              ? 'classic'
              : 'archive',
        ]}
        onValueChange={(values) => {
          const collection = values[0] as Collection | undefined;
          if (collection)
            applyRecipe({
              seed: newRandomSeed(),
              version: 3,
              variation: 0,
              collection,
            });
        }}
      >
        <ToggleGroupItem value="all">Все</ToggleGroupItem>
        <ToggleGroupItem value="new">Новые</ToggleGroupItem>
        <ToggleGroupItem value="classic">Классика</ToggleGroupItem>
      </ToggleGroup>
      <section className="identity" aria-live="polite">
        <p className="eyebrow">
          {genome.sculpture
            ? `${finishLabel(genome)} · ${genome.sculpture.etching > 0.1 ? 'Гравировка' : 'Поверхность'}`
            : genome.flat
              ? `Архив плоских форм · ${genome.material === 'contour' ? 'Контур' : genome.material === 'film' ? 'Перелив' : genome.material === 'matte' ? 'Мягкий цвет' : 'Заливка'}`
              : `${genome.dimension} · ${genome.material}`}
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
        onVary={vary}
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
