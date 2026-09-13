alter table public.user_preferences
    add column if not exists modern_palette_categories text[];

update public.user_preferences
set modern_palette_categories = array[
    'pastel',
    'vintage',
    'retro',
    'neon',
    'warm',
    'cold',
    'spring',
    'summer',
    'fall',
    'winter'
]::text[]
where modern_palette_categories is null
   or cardinality(modern_palette_categories) = 0;

alter table public.user_preferences
    alter column modern_palette_categories set default array[
        'pastel',
        'vintage',
        'retro',
        'neon',
        'warm',
        'cold',
        'spring',
        'summer',
        'fall',
        'winter'
    ]::text[],
    alter column modern_palette_categories set not null;
