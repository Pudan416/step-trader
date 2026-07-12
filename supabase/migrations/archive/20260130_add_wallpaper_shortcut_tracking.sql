-- Migration: Add wallpaper shortcut tracking to user_preferences
-- Tracks whether user has set up and used the canvas wallpaper shortcut

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_preferences' AND column_name = 'has_wallpaper_shortcut'
    ) THEN
        ALTER TABLE user_preferences ADD COLUMN has_wallpaper_shortcut boolean NOT NULL DEFAULT false;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_preferences' AND column_name = 'wallpaper_shortcut_uses'
    ) THEN
        ALTER TABLE user_preferences ADD COLUMN wallpaper_shortcut_uses int NOT NULL DEFAULT 0;
    END IF;
END
$$;

COMMENT ON COLUMN user_preferences.has_wallpaper_shortcut IS 'Whether the user has used the canvas wallpaper shortcut at least once';
COMMENT ON COLUMN user_preferences.wallpaper_shortcut_uses IS 'Total number of times the user has used the canvas wallpaper shortcut';
