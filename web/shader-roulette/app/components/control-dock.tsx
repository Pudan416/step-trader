'use client';

import { Copy, Download, Pause, Play } from 'lucide-react';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';

type Props = {
  paused: boolean;
  exporting: boolean;
  seedLabel: string;
  onReroll(): void;
  onTogglePaused(): void;
  onCopy(): void;
  onDownload(): void;
};

function IconAction({
  label,
  disabled,
  onClick,
  children,
}: {
  label: string;
  disabled?: boolean;
  onClick(): void;
  children: React.ReactNode;
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <button
            className="icon-action"
            type="button"
            aria-label={label}
            disabled={disabled}
            onClick={onClick}
          />
        }
      >
        {children}
      </TooltipTrigger>
      <TooltipContent className="tooltip-ink">{label}</TooltipContent>
    </Tooltip>
  );
}

export function ControlDock({
  paused,
  exporting,
  seedLabel,
  onReroll,
  onTogglePaused,
  onCopy,
  onDownload,
}: Props) {
  return (
    <TooltipProvider delay={250}>
      <div className="control-dock" aria-label="Управление генератором">
        <button className="again-button" type="button" onClick={onReroll}>
          ЕЩЁ <span aria-hidden="true">↗</span>
        </button>
        <span className="dock-divider" aria-hidden="true" />
        <button
          className="seed-button"
          type="button"
          onClick={onCopy}
          aria-label="Скопировать ссылку на фигуру"
        >
          {seedLabel}
        </button>
        <IconAction
          label={paused ? 'Продолжить движение' : 'Остановить движение'}
          onClick={onTogglePaused}
        >
          {paused ? (
            <Play size={17} strokeWidth={1.8} />
          ) : (
            <Pause size={17} strokeWidth={1.8} />
          )}
        </IconAction>
        <IconAction label="Скопировать ссылку" onClick={onCopy}>
          <Copy size={17} strokeWidth={1.8} />
        </IconAction>
        <IconAction
          label={exporting ? 'Собираю PNG' : 'Скачать PNG'}
          disabled={exporting}
          onClick={onDownload}
        >
          <Download size={17} strokeWidth={1.8} />
        </IconAction>
      </div>
    </TooltipProvider>
  );
}
