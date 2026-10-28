-- FIRE: the Doom fire of go/internal/fx/fire.go.
--
-- The one scene SQL cannot think about as a set. Each row of heat is made
-- from the row below it, just written, and each pixel draws a random number
-- only if the pixel under it is still burning: the number a pixel gets
-- depends on every pixel computed before it. So the frame is a loop over
-- rows, and the loop is a trigger: inserting the numbers h-1 … 1 into
-- fire_job fires one row update each, in that order.
--
-- Within a row it is a set again: the k-th burning pixel of the row takes
-- the k-th random number, and "k-th" is a window function.

-- @run resize
DROP TABLE IF EXISTS fire_buf;
CREATE TABLE fire_buf (id INTEGER PRIMARY KEY, v INTEGER);   -- id = y*w + x, v = heat 0-255
INSERT INTO fire_buf
  WITH RECURSIVE c(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM c, size WHERE n + 1 < w * h)
  SELECT n, 0 FROM c;

-- the frame's random numbers: k-th call of f.rand() this frame, and how
-- many calls the frame has used so far
DROP TABLE IF EXISTS fire_rand;
CREATE TABLE fire_rand (k INTEGER PRIMARY KEY, r INTEGER);
DROP TABLE IF EXISTS fire_state;
CREATE TABLE fire_state (rng INTEGER, used INTEGER);

-- The seed row's wave, per column: float32(x)/float32(w) times 11 and 23,
-- with the float32 roundings of tables.sql.
DROP TABLE IF EXISTS fire_wave;
CREATE TABLE fire_wave (x INTEGER PRIMARY KEY, a11 REAL, a23 REAL);
INSERT INTO fire_wave
  WITH
  f AS (SELECT n AS x, CAST(n AS REAL) / w AS fx FROM nums, size WHERE n < w),
  g AS (SELECT x, (fx * 536870913.0 - (fx * 536870913.0 - fx)) AS fx FROM f LIMIT -1)
  SELECT x,
         (fx * 11) * 536870913.0 - ((fx * 11) * 536870913.0 - (fx * 11)),
         (fx * 23) * 536870913.0 - ((fx * 23) * 536870913.0 - (fx * 23))
  FROM g;

-- @excerpt FIRE
-- One row: dst row y-1 from src row y. A dead src pixel (0) stays dead and
-- draws no number. A live one draws r: it reads the src pixel at x-1, x or
-- x+1 (r % 3) and cools by 0 or 1 (bit 16 of r).
DROP TABLE IF EXISTS fire_job;
CREATE TABLE fire_job (y INTEGER);
CREATE TRIGGER fire_row AFTER INSERT ON fire_job
BEGIN
  REPLACE INTO fire_buf (id, v)
    WITH src AS (
      SELECT id - NEW.y * w AS x, v,
             used + sum(v > 0) OVER (ORDER BY id) AS k      -- this pixel's call of rand()
      FROM fire_buf, size, fire_state
      WHERE id BETWEEN NEW.y * w AND NEW.y * w + w - 1
    )
    SELECT (NEW.y - 1) * w + x,
           CASE WHEN src.v = 0 THEN 0
                ELSE max(0, (SELECT v FROM fire_buf
                             WHERE id = NEW.y * w + max(0, min(w - 1, x + r % 3 - 1)))
                            - ((r >> 16) & 1))
           END
    FROM src CROSS JOIN size LEFT JOIN fire_rand ON fire_rand.k = src.k;
  UPDATE fire_state SET used = used + (
    SELECT count(*) FROM fire_buf, size
    WHERE id BETWEEN NEW.y * w AND NEW.y * w + w - 1 AND v > 0);
END;
-- @end

-- @run start
-- a fresh fire: the generator's seed
DELETE FROM fire_state;
INSERT INTO fire_state VALUES (2654435769, 0);           -- 0x9E3779B9

-- @run frame
-- The generator, xorshift32, run ahead for the whole frame: at most one call
-- per pixel. SQLite has no XOR, but a ^ b = (a | b) - (a & b); and no uint32,
-- so the left shifts are masked to 32 bits.
DELETE FROM fire_rand;
INSERT INTO fire_rand
  WITH RECURSIVE g(k, x) AS (
    SELECT 0, rng FROM fire_state
    UNION ALL
    SELECT k + 1, (SELECT (b | ((b << 5) & 4294967295)) - (b & ((b << 5) & 4294967295))
                   FROM (SELECT (a | (a >> 17)) - (a & (a >> 17)) AS b
                   FROM (SELECT (g.x | ((g.x << 13) & 4294967295)) - (g.x & ((g.x << 13) & 4294967295)) AS a
                         LIMIT -1) LIMIT -1))
    FROM g WHERE k < (SELECT w * h FROM size)
  )
  SELECT k, x FROM g WHERE k > 0;

-- The hottest row: a slow wave for the uneven base, a random term so the
-- tongues do not look periodic, in float32 like Go:
--   wv = 0.5 + 0.5*Sin(fx*11 + t)*0.6 + 0.5*Sin(fx*23 - t*1.7)*0.4
--   v  = 150 + wv*90 + float32(rand() & 31) - 16, clamped to 90…255
REPLACE INTO fire_buf (id, v)
  WITH
  k AS (
    SELECT 0.05 * 536870913.0 - (0.05 * 536870913.0 - 0.05) AS c005,
           1.7  * 536870913.0 - (1.7  * 536870913.0 - 1.7)  AS c17,
           0.6  * 536870913.0 - (0.6  * 536870913.0 - 0.6)  AS c06,
           0.4  * 536870913.0 - (0.4  * 536870913.0 - 0.4)  AS c04,
           (8192 / (2 * pi())) * 536870913.0 - ((8192 / (2 * pi())) * 536870913.0 - 8192 / (2 * pi())) AS inv
  ),
  t0 AS (SELECT *, :n * c005 AS t FROM k),
  t1 AS (SELECT *, t * 536870913.0 - (t * 536870913.0 - t) AS t FROM t0 LIMIT -1),
  t2 AS (SELECT *, (t * c17) * 536870913.0 - ((t * c17) * 536870913.0 - (t * c17)) AS t17 FROM t1 LIMIT -1),
  -- the two sine arguments, then their table indices
  a AS (
    SELECT x, inv, c06, c04,
           (a11 + t) * 536870913.0 - ((a11 + t) * 536870913.0 - (a11 + t)) AS p,
           (a23 - t17) * 536870913.0 - ((a23 - t17) * 536870913.0 - (a23 - t17)) AS q
    FROM t2 CROSS JOIN fire_wave LIMIT -1
  ),
  b AS (
    SELECT x, c06, c04, (p * inv) AS p, (q * inv) AS q FROM a LIMIT -1
  ),
  s AS (
    SELECT x, c06, c04, 0.5 * s1.s AS s1, 0.5 * s2.s AS s2           -- 0.5*s is exact
    FROM b
    JOIN sintab s1 ON s1.i = CAST(p * 536870913.0 - (p * 536870913.0 - p) AS INTEGER) & 8191
    JOIN sintab s2 ON s2.i = CAST(q * 536870913.0 - (q * 536870913.0 - q) AS INTEGER) & 8191
    LIMIT -1
  ),
  w1 AS (
    SELECT x, (s1 * c06) * 536870913.0 - ((s1 * c06) * 536870913.0 - (s1 * c06)) AS s1,
              (s2 * c04) * 536870913.0 - ((s2 * c04) * 536870913.0 - (s2 * c04)) AS s2
    FROM s LIMIT -1
  ),
  w2 AS (SELECT x, (0.5 + s1) * 536870913.0 - ((0.5 + s1) * 536870913.0 - (0.5 + s1)) AS wv, s2 FROM w1 LIMIT -1),
  w3 AS (SELECT x, (wv + s2) * 536870913.0 - ((wv + s2) * 536870913.0 - (wv + s2)) AS wv FROM w2 LIMIT -1),
  v1 AS (SELECT x, (wv * 90) * 536870913.0 - ((wv * 90) * 536870913.0 - (wv * 90)) + 150 AS v FROM w3 LIMIT -1),
  v2 AS (
    SELECT x, (v * 536870913.0 - (v * 536870913.0 - v)) + (r & 31) AS v
    FROM v1 JOIN fire_rand ON k = x + 1 LIMIT -1
  ),
  v3 AS (SELECT x, (v * 536870913.0 - (v * 536870913.0 - v)) - 16 AS v FROM v2 LIMIT -1)
  SELECT (h - 1) * w + x,
         CAST(max(90.0, min(255.0, v * 536870913.0 - (v * 536870913.0 - v))) AS INTEGER)
  FROM v3, size;
UPDATE fire_state SET used = (SELECT w FROM size);

-- Then every row, bottom to top, one trigger call each.
DELETE FROM fire_job;
INSERT INTO fire_job SELECT n FROM nums, size WHERE n BETWEEN 1 AND h - 1 ORDER BY n DESC;

-- The generator moves on by the calls the frame used.
UPDATE fire_state SET rng = (SELECT r FROM fire_rand WHERE k = used), used = 0;

-- And the heat, through the ember ramp (palette 512-767).
SELECT unhex(group_concat(hex, '')) FROM fire_buf CROSS JOIN palette ON palette.id = 512 + v;
