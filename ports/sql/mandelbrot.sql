-- MANDELBROT: the seahorse valley dive of go/internal/fx/mandelbrot.go.
--
-- All float64 in Go, so all REAL here, with no rounding tricks: SQLite's
-- double is Go's float64. The escape-time loop is a recursive CTE that
-- iterates every point of the frame at once: each row is one point after
-- i iterations, and a point stops producing rows when it escapes.

-- @run resize
DROP TABLE IF EXISTS mandel_rung;
CREATE TABLE mandel_rung (block INTEGER, cardioid INTEGER);
DROP TABLE IF EXISTS mandel_it;
CREATE TABLE mandel_it (b INTEGER PRIMARY KEY, it INTEGER);
DROP TABLE IF EXISTS mandel_view;
CREATE TABLE mandel_view (x0 REAL, y0 REAL, d REAL, max_iter INTEGER);

-- @run rung
-- The default rung: the closed-form test for the cardioid and the bulb, and
-- one point per block of 2x2 pixels (3x3 above 1600 pixels wide).
DELETE FROM mandel_rung;
INSERT INTO mandel_rung SELECT iif(w > 1600, 3, 2), 1 FROM size;

-- @run rung/1
-- @excerpt MANDELBROT/1
-- Every pixel is a point, and every point inside the set runs the whole
-- budget: the same query as the default rung, with mandel_rung saying so.
DELETE FROM mandel_rung;
INSERT INTO mandel_rung VALUES (1, 0);     -- block = 1 pixel, no cardioid test
-- @end

-- @run rung/2
-- @excerpt MANDELBROT/2
-- Every pixel, but the points the closed-form test puts in the cardioid or
-- the period-2 bulb never enter the recursive CTE (see `inside`).
DELETE FROM mandel_rung;
INSERT INTO mandel_rung VALUES (1, 1);     -- block = 1 pixel, cardioid test
-- @end

-- @run frame
-- The camera: it slides onto the target, then the exponential dive does the
-- work. t stops at 14 seconds; u = t/12.
DELETE FROM mandel_view;
INSERT INTO mandel_view
  WITH
  t AS (SELECT min(:n / 60.0, 14.0) / 12 AS u),
  cam AS (
    SELECT u, 1 - exp(-8 * u) AS k, 2.9 * exp(-u * u * 3.6) AS scale, 64 + CAST(128 * u AS INTEGER) AS max_iter
    FROM t
  ),
  c AS (
    SELECT scale, max_iter,
           -0.5 + (-0.743643887037151 + 0.5) * k AS cx,
           0.0 + 0.131825904205330 * k AS cy
    FROM cam
  )
  SELECT cx - scale * 0.5, cy - scale * 0.5 * (CAST(h AS REAL) / w), scale / w, max_iter
  FROM c, size;

-- @excerpt MANDELBROT
-- Escape time for every block at once. A row (b, i, zx, zy) is block b's
-- point after i iterations; the recursive step iterates the rows still
-- inside |z| <= 2. Go's loop body, in the same order of operations:
--   zy = 2*zx*zy + cy;  zx = zx*zx - zy*zy + cx
REPLACE INTO mandel_it
  WITH RECURSIVE
  blocks AS (
    SELECT (by.n / block) * ((w + block - 1) / block) + bx.n / block AS b,
           x0 + bx.n * d AS cx, y0 + by.n * d AS cy, max_iter, cardioid
    FROM size, mandel_view, mandel_rung, nums by, nums bx
    WHERE by.n < h AND by.n % block = 0 AND bx.n < w AND bx.n % block = 0
  ),
  -- the cardioid and the period-2 bulb never escape: no need to iterate them
  inside AS (
    SELECT b, cx, cy, max_iter,
           cardioid AND (((cx - 0.25) * (cx - 0.25) + cy * cy)
                          * (((cx - 0.25) * (cx - 0.25) + cy * cy) + (cx - 0.25)) <= 0.25 * (cy * cy)
                         OR (cx + 1) * (cx + 1) + cy * cy <= 0.0625) AS skip
    FROM blocks
  ),
  z(b, cx, cy, max_iter, i, zx, zy) AS (
    SELECT b, cx, cy, max_iter, 0, 0.0, 0.0 FROM inside WHERE NOT skip
    UNION ALL
    SELECT b, cx, cy, max_iter, i + 1, zx * zx - zy * zy + cx, 2 * zx * zy + cy
    FROM z
    WHERE zx * zx + zy * zy <= 4 AND i < max_iter
  )
  -- the last row of each point: escaped at iteration i - 1, or never
  SELECT b, i - (zx * zx + zy * zy > 4) FROM z
  WHERE zx * zx + zy * zy > 4 OR i >= max_iter
  UNION ALL
  SELECT b, max_iter FROM inside WHERE skip;

-- Every pixel takes its block's colour: the set is near-black, the rest
-- reads the ice ramp at sqrt(it/40), anchored to a fixed count, not to max.
SELECT unhex(group_concat(CASE
         WHEN it >= max_iter THEN '12080AFF'
         ELSE (SELECT hex FROM palette WHERE id = 256 + max(0, min(255,
                CAST((min(sqrt(it / 40.0), 1.0) * 0.92 + 0.04) * 255 AS INTEGER))))
       END, ''))
FROM size CROSS JOIN mandel_view CROSS JOIN mandel_rung CROSS JOIN nums y CROSS JOIN nums x
JOIN mandel_it ON mandel_it.b = (y.n / block) * ((w + block - 1) / block) + x.n / block
WHERE y.n < h AND x.n < w;
-- @end
