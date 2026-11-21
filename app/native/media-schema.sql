CREATE TABLE media_resources(
    photo TEXT PRIMARY KEY NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK(kind IN ('video', 'live')),
    motion TEXT NOT NULL,
    original_still TEXT,
    duration REAL CHECK(duration > 0),
    CHECK((kind = 'live') = (original_still IS NOT NULL))
);
PRAGMA user_version=1;
