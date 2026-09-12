ALTER TABLE public.user_preferences
    ADD COLUMN IF NOT EXISTS allowed_canvas_fills text[];

UPDATE public.user_preferences
SET allowed_canvas_fills = ARRAY['flat', 'gradient', 'rings', 'hatch', 'outline']
WHERE allowed_canvas_fills IS NULL OR cardinality(allowed_canvas_fills) = 0;

ALTER TABLE public.user_preferences
    ALTER COLUMN allowed_canvas_fills SET DEFAULT ARRAY['flat', 'gradient', 'rings', 'hatch', 'outline']::text[];
