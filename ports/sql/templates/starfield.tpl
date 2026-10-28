-- STARFIELD: a warp-speed star tunnel, as in go/internal/fx/starfield.go.
--
-- The stars are a table, updated every frame; the float32 maths is rounded
-- with f32(v) = v*S - (v*S - v), S = 2^29+1 (see tables.sql). The streaks are
-- Bresenham lines drawn additively, and in SQL the line algorithm becomes a
-- recursive CTE that walks all 1600 lines at once.

-- @run resize
-- The backdrop, a deep-navy vignette in float64, built once per size.
DROP TABLE IF EXISTS star_bg;
CREATE TABLE star_bg (id INTEGER PRIMARY KEY, r INTEGER, g INTEGER, b INTEGER, hex TEXT);
INSERT INTO star_bg
  WITH
  v AS (
    SELECT y.n * w + x.n AS id,
           (x.n / CAST(w AS REAL) - 0.5) * (x.n / CAST(w AS REAL) - 0.5)
           + (y.n / CAST(h AS REAL) - 0.5) * (y.n / CAST(h AS REAL) - 0.5) AS v
    FROM size CROSS JOIN nums y CROSS JOIN nums x WHERE y.n < h AND x.n < w
  ),
  c AS (
    SELECT id, max(0.0, 0.02 - v * 0.03) AS r, max(0.0, 0.02 - v * 0.025) AS g, max(0.0, 0.05 - v * 0.03) AS b
    FROM v
  ),
  -- canvas.FromFloat: uint8(c*255 + 0.5), clamped
  u AS (
    SELECT id, iif(r <= 0, 0, iif(r >= 1, 255, CAST(r * 255 + 0.5 AS INTEGER))) AS r,
               iif(g <= 0, 0, iif(g >= 1, 255, CAST(g * 255 + 0.5 AS INTEGER))) AS g,
               iif(b <= 0, 0, iif(b >= 1, 255, CAST(b * 255 + 0.5 AS INTEGER))) AS b
    FROM c
  )
  SELECT id, r, g, b, printf('%02X%02X%02XFF', r, g, b) FROM u;

DROP TABLE IF EXISTS star;
CREATE TABLE star (i INTEGER PRIMARY KEY, x REAL, y REAL, z REAL);
DROP TABLE IF EXISTS star_rng;
CREATE TABLE star_rng (rng INTEGER);
DROP TABLE IF EXISTS star_rand;
CREATE TABLE star_rand (k INTEGER PRIMARY KEY, r INTEGER, f REAL);  -- k-th call: state, Float32()
DROP TABLE IF EXISTS star_proj;
CREATE TABLE star_proj (i INTEGER PRIMARY KEY, x0 INTEGER, y0 INTEGER, x1 INTEGER, y1 INTEGER,
                        r INTEGER, g INTEGER, b INTEGER);
DROP TABLE IF EXISTS star_px;
CREATE TABLE star_px (id INTEGER PRIMARY KEY, hex TEXT);

-- @run start
-- 1600 stars from fmath.Rng(0x6005E): x, y and z, three calls each, in that
-- order. Float32() is the top 24 bits over 2^24: exact. xorshift32 in SQL has
-- no ^ and no uint32: a ^ b = (a | b) - (a & b), left shifts masked.
DELETE FROM star_rand;
INSERT INTO star_rand
  WITH RECURSIVE g(k, x) AS (
    SELECT 0, 393310                                     -- 0x6005E
    UNION ALL
    SELECT k + 1, (SELECT (b | ((b << 5) & 4294967295)) - (b & ((b << 5) & 4294967295))
                   FROM (SELECT (a | (a >> 17)) - (a & (a >> 17)) AS b
                   FROM (SELECT (g.x | ((g.x << 13) & 4294967295)) - (g.x & ((g.x << 13) & 4294967295)) AS a
                         LIMIT -1) LIMIT -1))
    FROM g WHERE k < 4800
  )
  SELECT k, x, (x >> 8) / 16777216.0 FROM g WHERE k > 0;
DELETE FROM star_rng;
INSERT INTO star_rng SELECT r FROM star_rand WHERE k = 4800;
DELETE FROM star;
INSERT INTO star
  SELECT n,
         F32((fx.f * 2 - 1) * F32(1.6)), F32((fy.f * 2 - 1) * F32(1.6)), F32(F32(fz.f * 40) + F32(0.2))
  FROM nums
  JOIN star_rand fx ON fx.k = 3 * n + 1
  JOIN star_rand fy ON fy.k = 3 * n + 2
  JOIN star_rand fz ON fz.k = 3 * n + 3
  WHERE n < 1600;

-- @run frame
-- The generator, run ahead: a frame respawns at most every star, two calls
-- each.
DELETE FROM star_rand;
INSERT INTO star_rand
  WITH RECURSIVE g(k, x) AS (
    SELECT 0, rng FROM star_rng
    UNION ALL
    SELECT k + 1, (SELECT (b | ((b << 5) & 4294967295)) - (b & ((b << 5) & 4294967295))
                   FROM (SELECT (a | (a >> 17)) - (a & (a >> 17)) AS b
                   FROM (SELECT (g.x | ((g.x << 13) & 4294967295)) - (g.x & ((g.x << 13) & 4294967295)) AS a
                         LIMIT -1) LIMIT -1))
    FROM g WHERE k < 3200
  )
  SELECT k, x, (x >> 8) / 16777216.0 FROM g WHERE k > 0;

-- the generator moves on by two calls per star reborn this frame
UPDATE star_rng SET rng = coalesce((
  SELECT r FROM star_rand WHERE k = 2 * (
    SELECT count(*) FROM star WHERE F32(z - F32(F32(2.5 + min(:n / 60.0, 3) * 4) * F32(1 / 60.0))) < F32(0.8))), rng);

-- @excerpt STARFIELD
-- Every star moves dz closer, dz = float32(2.5 + min(t, 3)*4) * float32(1/60).
-- A star that passes the camera goes back 40 units with a new x and y: the
-- k-th star to do so this frame (in star order) takes calls 2k-1 and 2k.
REPLACE INTO star
  WITH
  k AS (SELECT F32(F32(2.5 + min(:n / 60.0, 3) * 4) * F32(1 / 60.0)) AS dz),
  m AS (SELECT i, x, y, F32(z - dz) AS z FROM star, k),
  s AS (SELECT *, z < F32(0.8) AS reborn, sum(z < F32(0.8)) OVER (ORDER BY i) AS nth FROM m)
  SELECT i,
         iif(reborn, F32((fx.f * 2 - 1) * F32(1.1)), x),
         iif(reborn, F32((fy.f * 2 - 1) * F32(1.1)), y),
         iif(reborn, F32(z + 40), z)
  FROM s
  LEFT JOIN star_rand fx ON fx.k = 2 * nth - 1
  LEFT JOIN star_rand fy ON fy.k = 2 * nth;

-- Perspective, head and tail: the tail is where the star was 2.4 steps ago.
-- Brighter and bluer as it gets close.
REPLACE INTO star_proj
  WITH
  k AS (
    SELECT w * 0.5 AS cx, h * 0.5 AS cy, F32(w * F32(0.78)) AS zoom,
           F32(F32(2.5 + min(:n / 60.0, 3) * 4) * F32(1 / 60.0)) AS dz
    FROM size
  ),
  p AS (
    SELECT i, x, y, cx, cy, zoom, F32(1 / z) AS f, F32(1 / F32(z + F32(dz * F32(2.4)))) AS f2,
           F32(1 - F32(z / 40)) AS near
    FROM star, k
  ),
  q AS (SELECT *, F32(near * near) AS b FROM p)
  SELECT i,
    CAST(F32(cx + F32(F32(x * f) * zoom)) AS INTEGER), CAST(F32(cy + F32(F32(y * f) * zoom)) AS INTEGER),
    CAST(F32(cx + F32(F32(x * f2) * zoom)) AS INTEGER), CAST(F32(cy + F32(F32(y * f2) * zoom)) AS INTEGER),
    CAST(F32(F32(120 * b) + 40) AS INTEGER), CAST(F32(F32(190 * b) + 40) AS INTEGER),
    CAST(F32(255 * F32(F32(0.25) + F32(F32(0.75) * b))) AS INTEGER)
  FROM q;

-- The streaks: Bresenham from tail to head, every line at once. A row is
-- one star at one point of its line, with the line's error term.
DELETE FROM star_px;
INSERT INTO star_px
  WITH RECURSIVE
  line(i, x, y, x1, y1, dx, dy, sx, sy, err, r, g, b) AS (
    SELECT i, x0, y0, x1, y1, abs(x1 - x0), -abs(y1 - y0), iif(x0 < x1, 1, -1), iif(y0 < y1, 1, -1),
           abs(x1 - x0) - abs(y1 - y0), r, g, b
    FROM star_proj
    UNION ALL
    SELECT i, x + iif(2 * err >= dy, sx, 0), y + iif(2 * err <= dx, sy, 0), x1, y1, dx, dy, sx, sy,
           err + iif(2 * err >= dy, dy, 0) + iif(2 * err <= dx, dx, 0), r, g, b
    FROM line
    WHERE x <> x1 OR y <> y1
  ),
  -- the bright head pixel of each star overwrites what is under it, and the
  -- lines of later stars add on top: per pixel, the last head, then the sum
  -- of the lines drawn after it
  head AS (
    SELECT y1 * w + x1 AS id, max(i) AS i FROM star_proj, size
    WHERE x1 >= 0 AND x1 < w AND y1 >= 0 AND y1 < h GROUP BY id
  ),
  hit AS (
    SELECT y * w + x AS id, i, r, g, b FROM line, size WHERE x >= 0 AND x < w AND y >= 0 AND y < h
  ),
  extra AS (
    SELECT hit.id, sum(hit.r) AS r, sum(hit.g) AS g, sum(hit.b) AS b
    FROM hit LEFT JOIN head ON head.id = hit.id
    WHERE hit.i > coalesce(head.i, -1)
    GROUP BY hit.id
  ),
  px AS (SELECT id FROM head UNION SELECT id FROM hit),
  total AS (
    SELECT px.id,
           iif(head.i IS NULL, bg.r, 255) + coalesce(extra.r, 0) AS r,
           iif(head.i IS NULL, bg.g, 238) + coalesce(extra.g, 0) AS g,
           iif(head.i IS NULL, bg.b, 204) + coalesce(extra.b, 0) AS b
    FROM px JOIN star_bg bg ON bg.id = px.id LEFT JOIN head ON head.id = px.id LEFT JOIN extra ON extra.id = px.id
  )
  SELECT id, printf('%02X%02X%02XFF', min(r, 255), min(g, 255), min(b, 255)) FROM total;
-- @end

-- the backdrop, with the stars over it
SELECT unhex(group_concat(coalesce(star_px.hex, star_bg.hex), ''))
FROM star_bg LEFT JOIN star_px ON star_px.id = star_bg.id;
