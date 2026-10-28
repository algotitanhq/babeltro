-- TUNNEL: polar coordinates, as in go/internal/fx/tunnel.go.
--
-- Every float32 operation of the Go code is a double operation followed by
-- f32(v) = v * 536870913.0 - (v * 536870913.0 - v) (see tables.sql), and
-- since that needs v three times, each subquery rounds what the previous one
-- computed. `LIMIT -1` keeps SQLite from inlining them into each other.

-- @run resize
-- The geometry, as a view: distance and angle of every pixel, computed when
-- read. TUNNEL/1 reads it every frame, like Go's drawDirect; the default
-- rung stores it once in a table, like Go's Resize. The frame reads either
-- through the view tunnel_src: changing rung is a CREATE VIEW.
DROP VIEW IF EXISTS tunnel_geometry;
-- @excerpt TUNNEL/1
CREATE VIEW tunnel_geometry AS
  WITH
  c AS (
    SELECT w, h, w / 2.0 AS cx, h / 2.0 AS cy,
           (w + h) * (2.2 * 536870913.0 - (2.2 * 536870913.0 - 2.2)) AS scale,
           (w + h) * (0.02 * 536870913.0 - (0.02 * 536870913.0 - 0.02)) AS soft,
           2 * pi() * 536870913.0 - (2 * pi() * 536870913.0 - 2 * pi()) AS turn
    FROM size
  ),
  k AS (
    SELECT w, h, cx, cy, turn,
           scale * 536870913.0 - (scale * 536870913.0 - scale) AS scale,
           soft * 536870913.0 - (soft * 536870913.0 - soft) AS soft
    FROM c
  ),
  -- dx, dy are multiples of 0.5: exact, and so is dx*dx + dy*dy
  p AS (
    SELECT y.n * w + x.n AS id, scale, soft, turn,
           sqrt((x.n - cx) * (x.n - cx) + (y.n - cy) * (y.n - cy)) AS r,
           atan2(y.n - cy, x.n - cx) AS a
    FROM k CROSS JOIN nums y CROSS JOIN nums x
    WHERE y.n < h AND x.n < w
    LIMIT -1
  ),
  -- r = float32(sqrt(...)) + soft, a = float32(atan2(dy, dx)) / float32(2π)
  q AS (
    SELECT id, scale,
           (r * 536870913.0 - (r * 536870913.0 - r)) + soft AS r,
           (a * 536870913.0 - (a * 536870913.0 - a)) / turn AS a
    FROM p LIMIT -1
  ),
  -- depth = scale / r, angle = a + 0.5 (a fraction of a turn, in [0, 1))
  s AS (
    SELECT id,
           scale / (r * 536870913.0 - (r * 536870913.0 - r)) AS depth,
           (a * 536870913.0 - (a * 536870913.0 - a)) + 0.5 AS angle
    FROM q LIMIT -1
  )
  SELECT id,
         depth * 536870913.0 - (depth * 536870913.0 - depth) AS depth,
         angle * 536870913.0 - (angle * 536870913.0 - angle) AS angle
  FROM s;
-- @end

DROP TABLE IF EXISTS tunnel_px;
CREATE TABLE tunnel_px (id INTEGER PRIMARY KEY, depth REAL, angle REAL);
INSERT INTO tunnel_px SELECT * FROM tunnel_geometry;

-- the float32 constants of the loop, and the frame's two time terms
DROP TABLE IF EXISTS tunnel_k;
CREATE TABLE tunnel_k AS
  SELECT
    0.16 * 536870913.0 - (0.16 * 536870913.0 - 0.16) AS k_ring,
    0.09 * 536870913.0 - (0.09 * 536870913.0 - 0.09) AS k_twist,
    0.32 * 536870913.0 - (0.32 * 536870913.0 - 0.32) AS k_check,
    0.02 * 536870913.0 - (0.02 * 536870913.0 - 0.02) AS k_fog,
    0.55 * 536870913.0 - (0.55 * 536870913.0 - 0.55) AS w_ring,
    0.45 * 536870913.0 - (0.45 * 536870913.0 - 0.45) AS w_spoke,
    0.7  * 536870913.0 - (0.7  * 536870913.0 - 0.7)  AS dark;
DROP TABLE IF EXISTS tunnel_t;
CREATE TABLE tunnel_t (adv REAL, spin REAL);

-- @run frame
-- tm = float32(Beat); adv = tm*3, spin = tm*0.25 (exact: a power of two)
DELETE FROM tunnel_t;
INSERT INTO tunnel_t
  SELECT (t * 3) * 536870913.0 - ((t * 3) * 536870913.0 - (t * 3)), t * 0.25
  FROM (SELECT (:n / 60.0) * 536870913.0 - ((:n / 60.0) * 536870913.0 - (:n / 60.0)) AS t);

-- @excerpt TUNNEL
-- The pixels, in framebuffer order (CROSS JOIN pins the scan of tunnel_src
-- as the outer loop, and group_concat() keeps that order). Sin01(t) is
-- SinTab[int(t*8192) & 8191]; t*8192 is exact in float32.
WITH
-- u = depth + adv: scroll towards the viewer
t1 AS (
  SELECT (depth + adv) * 536870913.0 - ((depth + adv) * 536870913.0 - (depth + adv)) AS u,
         (angle * 12) * 536870913.0 - ((angle * 12) * 536870913.0 - (angle * 12)) AS v12,
         spin, k_ring, k_twist, k_check, k_fog, w_ring, w_spoke, dark
  FROM tunnel_k CROSS JOIN tunnel_t CROSS JOIN tunnel_src
  LIMIT -1
),
t2 AS (
  SELECT CAST(((u * k_ring) * 536870913.0 - ((u * k_ring) * 536870913.0 - (u * k_ring))) * 8192 AS INTEGER) & 8191 AS ri,
         (u * k_twist) * 536870913.0 - ((u * k_twist) * 536870913.0 - (u * k_twist)) AS tw,
         CAST((u * k_check) * 536870913.0 - ((u * k_check) * 536870913.0 - (u * k_check)) AS INTEGER) AS checker,
         (u * k_fog) * 536870913.0 - ((u * k_fog) * 536870913.0 - (u * k_fog)) AS fog,
         v12, spin, w_ring, w_spoke, dark
  FROM t1 LIMIT -1
),
-- rings along the depth axis; twist = v*12 + u*0.09 + spin; fog = 1/(1 + u*0.02)
t3 AS (
  SELECT (s * w_ring) * 536870913.0 - ((s * w_ring) * 536870913.0 - (s * w_ring)) AS ring,
         (v12 + tw) * 536870913.0 - ((v12 + tw) * 536870913.0 - (v12 + tw)) AS tw,
         (1 + fog) * 536870913.0 - ((1 + fog) * 536870913.0 - (1 + fog)) AS fog,
         checker, spin, w_spoke, dark
  FROM t2 JOIN sintab ON i = ri LIMIT -1
),
t4 AS (
  SELECT ring, (tw + spin) * 536870913.0 - ((tw + spin) * 536870913.0 - (tw + spin)) AS twist,
         (1 / fog) * 536870913.0 - ((1 / fog) * 536870913.0 - (1 / fog)) AS fog,
         checker, w_spoke, dark
  FROM t3 LIMIT -1
),
-- spokes that twist as they recede; the brick checker
t5 AS (
  SELECT ring, (s * w_spoke) * 536870913.0 - ((s * w_spoke) * 536870913.0 - (s * w_spoke)) AS spoke,
         (checker + CAST(twist AS INTEGER)) & 1 AS odd, fog, dark
  FROM t4 JOIN sintab ON i = CAST(twist * 8192 AS INTEGER) & 8191 LIMIT -1
),
t6 AS (
  SELECT (ring + spoke) * 536870913.0 - ((ring + spoke) * 536870913.0 - (ring + spoke)) AS val,
         odd, fog, dark
  FROM t5 LIMIT -1
),
-- the darker bricks: val = -val * 0.7; then lum = (val*0.5 + 0.5) * fog
-- (val*0.5 is exact: a power of two)
t7 AS (
  SELECT CASE odd WHEN 1 THEN (-val * dark) * 536870913.0 - ((-val * dark) * 536870913.0 - (-val * dark))
                  ELSE val END * 0.5 + 0.5 AS lum, fog
  FROM t6 LIMIT -1
),
t8 AS (SELECT (lum * 536870913.0 - (lum * 536870913.0 - lum)) * fog AS lum FROM t7 LIMIT -1),
t9 AS (SELECT (lum * 536870913.0 - (lum * 536870913.0 - lum)) * 300 AS lum FROM t8 LIMIT -1)
-- index = int(lum * 300), clamped; the ice ramp is palette 256-511
SELECT unhex(group_concat(hex, ''))
FROM t9 JOIN palette ON id = 256 + max(0, min(255,
  CAST(lum * 536870913.0 - (lum * 536870913.0 - lum) AS INTEGER)));
-- @end

-- @run rung
-- The default rung reads the stored geometry.
DROP VIEW IF EXISTS tunnel_src;
CREATE VIEW tunnel_src AS SELECT id, depth, angle FROM tunnel_px;

-- @run rung/1
-- Go's drawDirect, the square root, the division and the atan2 for every
-- pixel, every frame: the same query reads the view instead of the table.
DROP VIEW IF EXISTS tunnel_src;
CREATE VIEW tunnel_src AS SELECT id, depth, angle FROM tunnel_geometry;

-- @run frame/3
-- Not a rung of Go's ladder: the default rung in plain double, every f32()
-- removed (the stored geometry keeps Go's float32 values), to measure what
-- the rounding costs and what it buys.
-- `node tools/check.mjs --scene 1 --step 3 sql` compares it with Go.
DELETE FROM tunnel_t;
INSERT INTO tunnel_t SELECT t * 3, t * 0.25 FROM (SELECT :n / 60.0 AS t);
SELECT unhex(group_concat(hex, '')) FROM (
  SELECT CASE odd WHEN 1 THEN -val * 0.7 ELSE val END * 0.5 + 0.5 AS lum, fog FROM (
    SELECT ring * 0.55 + st.s * 0.45 AS val, (CAST(u * 0.32 AS INTEGER) + CAST(twist AS INTEGER)) & 1 AS odd,
           1 / (1 + u * 0.02) AS fog
    FROM (
      SELECT u, angle * 12 + u * 0.09 + spin AS twist, sr.s AS ring
      FROM (SELECT depth + adv AS u, angle, spin FROM tunnel_t CROSS JOIN tunnel_px LIMIT -1)
      JOIN sintab sr ON sr.i = CAST(u * 0.16 * 8192 AS INTEGER) & 8191
      LIMIT -1)
    JOIN sintab st ON st.i = CAST(twist * 8192 AS INTEGER) & 8191
    LIMIT -1)
  LIMIT -1)
JOIN palette ON id = 256 + max(0, min(255, CAST(lum * fog * 300 AS INTEGER)));
