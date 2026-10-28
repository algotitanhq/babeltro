-- Tables every scene shares, built once when the port loads.
--
-- SQLite has exactly one floating type, the 64-bit REAL. Go's effects compute
-- in float32. A double can be rounded to float32 with arithmetic alone
-- (Veltkamp's split, 1968): with S = 2^29 + 1,
--
--     f32(x) = x*S - (x*S - x)
--
-- keeps the top 24 bits of x's 53, rounding to nearest, ties to even: exactly
-- what float32 does, for every x in float32's normal range. It needs x three
-- times, and SQL has no local variables, so the queries compute a value in
-- one subquery and round it in the next one. That is the whole trick.

-- nums: 0, 1, 2, … for the scenes that need a counter (no generate_series in
-- sql.js, so a recursive CTE fills it once).
CREATE TABLE nums (n INTEGER PRIMARY KEY);
INSERT INTO nums
  WITH RECURSIVE c(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM c WHERE n < 8191)
  SELECT n FROM c;

-- sintab: Go's fmath.SinTab, 8192 float32 sines of a full turn. The sine is
-- the one sql.js compiles in (extension-functions.c, C libm), rounded to
-- float32 like Go's float32(math.Sin(a)).
CREATE TABLE sintab (i INTEGER PRIMARY KEY, s REAL);
INSERT INTO sintab
  SELECT n, s * 536870913.0 - (s * 536870913.0 - s)
  FROM (SELECT n, sin(2 * pi() * n / 8192) AS s FROM nums);

-- stops: the colour anchors of go/internal/palette, one row each.
CREATE TABLE stops (pal TEXT, k INTEGER, pos REAL, r REAL, g REAL, b REAL);
INSERT INTO stops VALUES
  ('sunset', 0, 0.00, 0.02, 0.00, 0.06),
  ('sunset', 1, 0.18, 0.25, 0.02, 0.38),
  ('sunset', 2, 0.38, 0.72, 0.05, 0.45),
  ('sunset', 3, 0.56, 0.98, 0.25, 0.22),
  ('sunset', 4, 0.74, 1.00, 0.62, 0.15),
  ('sunset', 5, 0.88, 1.00, 0.93, 0.55),
  ('sunset', 6, 1.00, 1.00, 1.00, 0.96),
  ('ice',    0, 0.00, 0.00, 0.00, 0.03),
  ('ice',    1, 0.25, 0.00, 0.10, 0.30),
  ('ice',    2, 0.50, 0.00, 0.55, 0.85),
  ('ice',    3, 0.72, 0.35, 0.90, 1.00),
  ('ice',    4, 0.90, 0.80, 1.00, 1.00),
  ('ice',    5, 1.00, 1.00, 1.00, 1.00),
  ('ember',  0, 0.00, 0.00, 0.00, 0.00),
  ('ember',  1, 0.20, 0.25, 0.00, 0.00),
  ('ember',  2, 0.45, 0.80, 0.10, 0.00),
  ('ember',  3, 0.68, 1.00, 0.45, 0.00),
  ('ember',  4, 0.85, 1.00, 0.80, 0.15),
  ('ember',  5, 1.00, 1.00, 1.00, 0.85);

-- palette: 256 colours per ramp, as the 8 hex digits of the pixel's bytes
-- (R, G, B, A). A frame is the concatenation of its pixels' `hex`, turned
-- into a blob by unhex(). The key packs ramp and index into one rowid, so a
-- lookup is a single B-tree seek: sunset is 0-255, ice 256-511, ember 512-767.
CREATE TABLE palette (id INTEGER PRIMARY KEY, hex TEXT);
INSERT INTO palette
  WITH
  ramp(pal, base) AS (VALUES ('sunset', 0), ('ice', 256), ('ember', 512)),
  -- the segment [a, b] that holds t = i/255. Go takes the first one, so
  -- min(a.k): SQLite fills the other, bare columns from that same row
  seg AS (
    SELECT ramp.base + n AS id, n / 255.0 AS t, min(a.k), a.pos, a.r, a.g, a.b,
           b.pos AS bpos, b.r AS br, b.g AS bg, b.b AS bb
    FROM ramp
    JOIN nums ON n < 256
    JOIN stops a ON a.pal = ramp.pal
    JOIN stops b ON b.pal = a.pal AND b.k = a.k + 1
    WHERE n / 255.0 BETWEEN a.pos AND b.pos
    GROUP BY id
  ),
  -- u = (t - a.pos) / (b.pos - a.pos), clamped to [0, 1]
  lin AS (
    SELECT id, r, g, b, br, bg, bb,
           max(0.0, min(1.0, iif(bpos > pos, (t - pos) / (bpos - pos), 0.0))) AS u
    FROM seg
  ),
  -- smoothstep keeps the gradients from banding
  smooth AS (SELECT *, u * u * (3 - 2 * u) AS s FROM lin),
  rgb AS (
    SELECT id, r + (br - r) * s AS r, g + (bg - g) * s AS g, b + (bb - b) * s AS b
    FROM smooth
  )
  -- f2b: uint8(v*255 + 0.5), clamped
  SELECT id, printf('%02X%02X%02XFF',
    iif(r <= 0, 0, iif(r >= 1, 255, CAST(r * 255 + 0.5 AS INTEGER))),
    iif(g <= 0, 0, iif(g >= 1, 255, CAST(g * 255 + 0.5 AS INTEGER))),
    iif(b <= 0, 0, iif(b >= 1, 255, CAST(b * 255 + 0.5 AS INTEGER))))
  FROM rgb;
