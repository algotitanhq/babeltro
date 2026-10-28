-- METABALLS: six radial fields summed, as in go/internal/fx/metaballs.go.
--
-- All float32 in Go, so every operation is rounded with
-- f32(v) = v*S - (v*S - v), S = 2^29+1 (see tables.sql), one subquery
-- computing and the next rounding; `LIMIT -1` keeps them apart.

-- @run resize
DROP TABLE IF EXISTS meta_ball;
CREATE TABLE meta_ball (i INTEGER PRIMARY KEY, bx REAL, by REAL, rad2 REAL);
DROP TABLE IF EXISTS meta_k;
CREATE TABLE meta_k (r0 REAL, r1 REAL, r2 REAL, r3 REAL, r4 REAL, r5 REAL);
-- per column and per row, the squared distance to each ball along that axis
DROP TABLE IF EXISTS meta_col;
CREATE TABLE meta_col (x INTEGER PRIMARY KEY, d0 REAL, d1 REAL, d2 REAL, d3 REAL, d4 REAL, d5 REAL);
DROP TABLE IF EXISTS meta_row;
CREATE TABLE meta_row (y INTEGER PRIMARY KEY, d0 REAL, d1 REAL, d2 REAL, d3 REAL, d4 REAL, d5 REAL);

-- @run frame
-- Each ball orbits on its own ellipse and breathes (fi = float32(i)):
--   a     = t*(0.35 + fi*0.07) + fi*2.1
--   x     = 0.5 + 0.20*Cos(a)*(1 + 0.3*Sin(t*0.5 + fi))
--   y     = 0.5 + 0.20*Sin(a*1.3 + fi)*(1 + 0.3*Cos(t*0.4 + fi*2))
--   r     = 0.105 + 0.025*Sin(t*1.1 + fi*1.7)
-- Sin(a) is SinTab[int(a*TabSize/2π) & 8191], Cos(a) the same in CosTab.
DELETE FROM meta_ball;
INSERT INTO meta_ball
  WITH
  k AS (SELECT F32(:n / 60.0) AS t, F32(8192 / (2 * pi())) AS inv),
  b AS (
    SELECT n AS i, n AS fi, t, inv,
           F32(F32(t * F32(F32(0.35) + F32(n * F32(0.07)))) + F32(n * F32(2.1))) AS a
    FROM k, nums WHERE n < 6
  ),
  -- the five sine and cosine arguments, as table indices
  g AS (
    SELECT i,
           CAST(F32(a * inv) AS INTEGER) & 8191 AS ia,
           CAST(F32(F32(F32(t * F32(0.5)) + fi) * inv) AS INTEGER) & 8191 AS ib,
           CAST(F32(F32(F32(a * F32(1.3)) + fi) * inv) AS INTEGER) & 8191 AS ic,
           CAST(F32(F32(F32(t * F32(0.4)) + F32(fi * 2)) * inv) AS INTEGER) & 8191 AS id,
           CAST(F32(F32(F32(t * F32(1.1)) + F32(fi * F32(1.7))) * inv) AS INTEGER) & 8191 AS ie
    FROM b LIMIT -1
  ),
  v AS (
    SELECT g.i, ta.c AS ca, tb.s AS sb, tc.s AS sc, td.c AS cd, te.s AS se
    FROM g JOIN sintab ta ON ta.i = ia JOIN sintab tb ON tb.i = ib JOIN sintab tc ON tc.i = ic
           JOIN sintab td ON td.i = id JOIN sintab te ON te.i = ie
  ),
  p AS (
    SELECT i,
           F32(0.5 + F32(F32(F32(0.20) * ca) * F32(1 + F32(F32(0.3) * sb)))) AS bx,
           F32(0.5 + F32(F32(F32(0.20) * sc) * F32(1 + F32(F32(0.3) * cd)))) AS by,
           F32(F32(0.105) + F32(F32(0.025) * se)) AS r
    FROM v LIMIT -1
  )
  SELECT i, bx, by, F32(r * r) FROM p;

DELETE FROM meta_k;
INSERT INTO meta_k
  SELECT sum(rad2 * (i = 0)), sum(rad2 * (i = 1)), sum(rad2 * (i = 2)),
         sum(rad2 * (i = 3)), sum(rad2 * (i = 4)), sum(rad2 * (i = 5))
  FROM meta_ball;

-- x is scaled by asp = w/h so the balls stay round:
--   fx = (float32(x)/float32(w) - 0.5) * asp,  dx = fx - (ball.x - 0.5)*asp
REPLACE INTO meta_col
  WITH
  a AS (SELECT F32(CAST(w AS REAL) / h) AS asp, w FROM size),
  f AS (SELECT n AS x, F32(F32(F32(n / CAST(w AS REAL)) - 0.5) * asp) AS fx, asp FROM a, nums WHERE n < w),
  d AS (
    SELECT x, i, F32(fx - F32(F32(bx - 0.5) * asp)) AS d FROM f CROSS JOIN meta_ball LIMIT -1
  ),
  dd AS (SELECT x, i, F32(d * d) AS d FROM d LIMIT -1)
  SELECT x, sum(d * (i = 0)), sum(d * (i = 1)), sum(d * (i = 2)), sum(d * (i = 3)), sum(d * (i = 4)), sum(d * (i = 5))
  FROM dd GROUP BY x;

--   fy = float32(y)/float32(h) - 0.5,  dy = fy - (ball.y - 0.5)
REPLACE INTO meta_row
  WITH
  f AS (SELECT n AS y, F32(F32(n / CAST(h AS REAL)) - 0.5) AS fy FROM size, nums WHERE n < h),
  d AS (SELECT y, i, F32(fy - F32(by - 0.5)) AS d FROM f CROSS JOIN meta_ball LIMIT -1),
  dd AS (SELECT y, i, F32(d * d) AS d FROM d LIMIT -1)
  SELECT y, sum(d * (i = 0)), sum(d * (i = 1)), sum(d * (i = 2)), sum(d * (i = 3)), sum(d * (i = 4)), sum(d * (i = 5))
  FROM dd GROUP BY y;

-- @excerpt METABALLS
-- field = sum over the balls of r^2 / (dx^2 + dy^2 + 1e-5), in float32, in
-- ball order. Rows outer, columns inner (CROSS JOIN keeps that order).
WITH
m1 AS (
  SELECT F32(c.d0 + r.d0) AS s0, F32(c.d1 + r.d1) AS s1, F32(c.d2 + r.d2) AS s2,
         F32(c.d3 + r.d3) AS s3, F32(c.d4 + r.d4) AS s4, F32(c.d5 + r.d5) AS s5,
         r0, r1, r2, r3, r4, r5, F32(1e-5) AS e
  FROM meta_k CROSS JOIN meta_row r CROSS JOIN meta_col c
  LIMIT -1
),
m2 AS (
  SELECT F32(s0 + e) AS s0, F32(s1 + e) AS s1, F32(s2 + e) AS s2,
         F32(s3 + e) AS s3, F32(s4 + e) AS s4, F32(s5 + e) AS s5, r0, r1, r2, r3, r4, r5
  FROM m1 LIMIT -1
),
m3 AS (
  SELECT F32(r0 / s0) AS q0, F32(r1 / s1) AS q1, F32(r2 / s2) AS q2,
         F32(r3 / s3) AS q3, F32(r4 / s4) AS q4, F32(r5 / s5) AS q5
  FROM m2 LIMIT -1
),
m4 AS (SELECT F32(q0 + q1) AS f, q2, q3, q4, q5 FROM m3 LIMIT -1),
m5 AS (SELECT F32(f + q2) AS f, q3, q4, q5 FROM m4 LIMIT -1),
m6 AS (SELECT F32(f + q3) AS f, q4, q5 FROM m5 LIMIT -1),
m7 AS (SELECT F32(f + q4) AS f, q5 FROM m6 LIMIT -1),
m8 AS (SELECT F32(f + q5) AS f FROM m7 LIMIT -1),
-- v = field/(1.6 + field): about 1 on a ball's surface, compressed to 0..1
m9 AS (SELECT f, F32(F32(1.6) + f) AS den FROM m8 LIMIT -1),
m10 AS (SELECT f, F32(f / den) AS v FROM m9 LIMIT -1)
-- index = int(v*255), and the rim where the balls meet flares white
SELECT unhex(group_concat(hex, ''))
FROM m10 JOIN palette ON id = CASE
  WHEN f > 1.0 AND f < F32(1.09) THEN 255
  ELSE min(255, CAST(F32(v * 255) AS INTEGER)) END;
-- @end
