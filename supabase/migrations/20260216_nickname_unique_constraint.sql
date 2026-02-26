-- Prevent duplicate nicknames. NULLs are allowed (users without a nickname).
-- The TOCTOU race in tg-admin's /setnick and random-nickname flows can
-- produce duplicates without a DB-level constraint.

ALTER TABLE users ADD CONSTRAINT users_nickname_unique UNIQUE (nickname);
