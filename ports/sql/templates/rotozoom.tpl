-- ROTOZOOM: a rotated, zoomed walk over a tiling texture, as in
-- go/internal/fx/rotozoom.go.
--
-- The texture is float64 maths, done once. The sampling grid is float32, and
-- every float32 operation is rounded with f32(v) = v*S - (v*S - v), S = 2^29+1
-- (see tables.sql); each subquery rounds what the previous one computed, and
-- `LIMIT -1` keeps SQLite from inlining them into each other.

-- @run resize
-- (Each step is MATERIALIZED: inlined, every column used twice would be
-- computed twice, and so on down the chain.)
-- The 512x512 texture, built the first time only: a tileable rainbow plasma
-- (every frequency a whole number of cycles per tile), concentric rings, a
-- hue-saturation-lightness ramp, and a dark grid so the motion reads.
CREATE TABLE IF NOT EXISTS roto_tex (id INTEGER PRIMARY KEY, hex TEXT);
INSERT INTO roto_tex
  WITH
  p AS (
    SELECT y.n * 512 + x.n AS id, x.n AS x, y.n AS y, x.n / 512.0 AS fx, y.n / 512.0 AS fy, 2 * pi() AS tp
    FROM nums y CROSS JOIN nums x
    WHERE y.n < 512 AND x.n < 512 AND NOT EXISTS (SELECT 1 FROM roto_tex)
  ),
  v AS MATERIALIZED (
    SELECT id, x, y,
           sin(fx * tp * 3 + fy * tp * 2) * 0.5 + sin(fy * tp * 5 - fx * tp * 4) * 0.3
           + sin((fx + fy) * tp * 7) * 0.2
           + sin(sqrt((x - 256.0) * (x - 256.0) + (y - 256.0) * (y - 256.0)) / 512 * 12 * tp) * 0.35 AS v
    FROM p
  ),
  -- hue = math.Mod(v*0.55 + 0.5, 1), wrapped into [0, 1); a - trunc(a) is
  -- exactly fmod(a, 1), and SQLite has no fmod
  hsl AS MATERIALIZED (
    SELECT id, x, y, v, v * 0.55 + 0.5 - CAST(v * 0.55 + 0.5 AS INTEGER) AS hue, 0.48 + 0.14 * v AS l
    FROM v
  ),
  pq AS MATERIALIZED (
    SELECT id, x, y, iif(hue < 0, hue + 1, hue) AS hue,
           iif(l < 0.5, l * (1 + 0.70), l + 0.70 - l * 0.70) AS q, l
    FROM hsl
  ),
  -- HSL2RGB's hue2rgb, once per channel: red at h + 1/3, green at h, blue at h - 1/3
  ch AS MATERIALIZED (
    SELECT id, x, y, c.k, 2 * l - q AS p, q, hue + c.off AS t
    FROM pq CROSS JOIN (SELECT 0 AS k, 1.0 / 3 AS off UNION ALL SELECT 1, 0.0 UNION ALL SELECT 2, -(1.0 / 3)) c
  ),
  wrap AS MATERIALIZED (SELECT id, x, y, k, p, q, iif(t < 0, t + 1, iif(t > 1, t - 1, t)) AS t FROM ch),
  lit AS MATERIALIZED (
    SELECT id, x, y, k,
           CASE WHEN t < 1.0 / 6 THEN p + (q - p) * 6 * t
                WHEN t < 1.0 / 2 THEN q
                WHEN t < 2.0 / 3 THEN p + (q - p) * (2.0 / 3 - t) * 6
                ELSE p END
           * iif(x % 64 < 3 OR y % 64 < 3, 0.28, 1.0) AS c
    FROM wrap
  ),
  -- canvas.FromFloat: uint8(c*255 + 0.5), clamped
  byte AS (SELECT id, k, iif(c <= 0, 0, iif(c >= 1, 255, CAST(c * 255 + 0.5 AS INTEGER))) AS v FROM lit)
  SELECT id, printf('%02X%02X%02XFF', sum(v * (k = 0)), sum(v * (k = 1)), sum(v * (k = 2)))
  FROM byte GROUP BY id;

-- the frame's rotation, zoom and offset; then the row and column halves of
-- the rotation, which is all the per-pixel products there are
DROP TABLE IF EXISTS roto_k;
CREATE TABLE roto_k (zoom REAL, offx REAL, offy REAL);
DROP TABLE IF EXISTS roto_row;
CREATE TABLE roto_row (y INTEGER PRIMARY KEY, dc REAL, ds REAL);
DROP TABLE IF EXISTS roto_col;
CREATE TABLE roto_col (x INTEGER PRIMARY KEY, xc REAL, xs REAL);
DROP TABLE IF EXISTS roto_rot;
CREATE TABLE roto_rot (cosa REAL, sina REAL);

-- @run frame
-- ang = t*0.45; cosA = Cos(ang), sinA = Sin(ang), from the tables
DELETE FROM roto_rot;
INSERT INTO roto_rot
  WITH
  t AS (SELECT F32(:n / 60.0) AS t),
  a AS (SELECT F32(t * F32(0.45)) AS a, (8192 / (2 * pi())) AS inv FROM t)
  SELECT c, s FROM a JOIN sintab ON i = CAST(F32(a * F32(inv)) AS INTEGER) & 8191;

-- zoom = 0.55 + 0.45*Sin(t*0.7) + 0.35, then zoom/float32(w)*6.5;
-- offx = Sin(t*0.31)*180 + t*26, offy = Cos(t*0.27)*180 + t*19
DELETE FROM roto_k;
INSERT INTO roto_k
  WITH
  t AS (SELECT F32(:n / 60.0) AS t, F32(8192 / (2 * pi())) AS inv),
  a AS (
    SELECT t, CAST(F32(F32(t * F32(0.7)) * inv) AS INTEGER) & 8191 AS i7,
              CAST(F32(F32(t * F32(0.31)) * inv) AS INTEGER) & 8191 AS i31,
              CAST(F32(F32(t * F32(0.27)) * inv) AS INTEGER) & 8191 AS i27
    FROM t
  ),
  b AS (
    SELECT F32(F32(F32(0.55) + F32(F32(0.45) * s7.s)) + F32(0.35)) AS zoom,
           F32(F32(s31.s * 180) + F32(t * 26)) AS offx,
           F32(F32(c27.c * 180) + F32(t * 19)) AS offy
    FROM a
    JOIN sintab s7 ON s7.i = i7 JOIN sintab s31 ON s31.i = i31 JOIN sintab c27 ON c27.i = i27
  )
  SELECT F32(F32(zoom / w) * 6.5), offx, offy FROM b, size;

-- dy*cosA and dy*sinA per row, dx*cosA and dx*sinA per column: the same
-- float32 products Go computes per pixel (dx, dy are exact: halves)
REPLACE INTO roto_row
  SELECT n, F32((n - h * 0.5) * cosa), F32((n - h * 0.5) * sina) FROM size, roto_rot, nums WHERE n < h;
REPLACE INTO roto_col
  SELECT n, F32((n - w * 0.5) * cosa), F32((n - w * 0.5) * sina) FROM size, roto_rot, nums WHERE n < w;

-- @excerpt ROTOZOOM
-- tx = (dx*cosA - dy*sinA) * zoom * 34; ty = (dx*sinA + dy*cosA) * zoom * 34;
-- the texel is (int(tx + offx) & 511, int(ty + offy) & 511). Rows outer,
-- columns inner: CROSS JOIN fixes the order group_concat() sees.
WITH
r1 AS (
  SELECT F32(xc - ds) AS tx, F32(xs + dc) AS ty, zoom, offx, offy
  FROM roto_k CROSS JOIN roto_row CROSS JOIN roto_col
  LIMIT -1
),
r2 AS (SELECT F32(tx * zoom) AS tx, F32(ty * zoom) AS ty, offx, offy FROM r1 LIMIT -1),
r3 AS (SELECT F32(tx * 34) AS tx, F32(ty * 34) AS ty, offx, offy FROM r2 LIMIT -1),
r4 AS (SELECT tx + offx AS tx, ty + offy AS ty FROM r3 LIMIT -1)
SELECT unhex(group_concat(hex, ''))
FROM r4 JOIN roto_tex ON id = (CAST(F32(ty) AS INTEGER) & 511) * 512 + (CAST(F32(tx) AS INTEGER) & 511);
-- @end
