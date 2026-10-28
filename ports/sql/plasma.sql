-- PLASMA: four summed sine fields, as in go/internal/fx/plasma.go.
--
-- Go computes in float32. Here every float32 operation is a double
-- operation followed by the rounding of tables.sql:
--
--     f32(v) = v * 536870913.0 - (v * 536870913.0 - v)      -- S = 2^29 + 1
--
-- It needs v three times and SQL has no local variables, so a value is
-- computed in one subquery and rounded in the next. `LIMIT -1` means "no
-- limit": it only stops SQLite from inlining a subquery into the next one,
-- which would evaluate each column once per use, three times per rounding,
-- compounding at every level. Each subquery runs as a co-routine: one row
-- in flight, nothing stored.

-- @run resize
-- Built once per size, like Go's Resize: the pixels, with x + y and the
-- distance from the centre, rad = float32(sqrt(dx*dx + dy*dy)) * k. dx and
-- dy are multiples of 0.5, so their squares and the sum are exact in
-- float32 for any frame under 2896 pixels a side: only the square root and
-- the product are rounded.
DROP TABLE IF EXISTS plasma_px;
CREATE TABLE plasma_px (id INTEGER PRIMARY KEY, x INTEGER, y INTEGER, d INTEGER, rad REAL);
INSERT INTO plasma_px
  WITH
  c AS (SELECT w, h, w * 0.5 AS cx, h * 0.5 AS cy, 44.0 / (w + h) AS k FROM size),
  d AS (
    SELECT y.n * w + x.n AS id, x.n AS x, y.n AS y, k * 536870913.0 - (k * 536870913.0 - k) AS k,
           sqrt((x.n - cx) * (x.n - cx) + (y.n - cy) * (y.n - cy)) AS r
    FROM c CROSS JOIN nums y CROSS JOIN nums x
    WHERE y.n < h AND x.n < w
    LIMIT -1
  ),
  r AS (SELECT id, x, y, (r * 536870913.0 - (r * 536870913.0 - r)) * k AS r FROM d LIMIT -1)
  SELECT id, x, y, x + y, r * 536870913.0 - (r * 536870913.0 - r) FROM r;

-- The constants, rounded to float32 as Go's untyped constants are when they
-- meet a float32: kx = 26/float32(w), 1.3, TabSize/(2π)…
DROP TABLE IF EXISTS plasma_k;
CREATE TABLE plasma_k AS
  WITH c AS (
    SELECT 26.0 / w AS kx, 26.0 / h AS ky, 44.0 / (w + h) AS kr, w * 0.5 AS cx, h * 0.5 AS cy,
           1.3 AS c13, 1.35 AS c135, 1.1 AS c11, 0.85 AS c085, 0.8 AS c08, 2.6 AS c26,
           8192 / (2 * pi()) AS inv
    FROM size
  )
  SELECT cx, cy,
    kx   * 536870913.0 - (kx   * 536870913.0 - kx)   AS kx,
    ky   * 536870913.0 - (ky   * 536870913.0 - ky)   AS ky,
    kr   * 536870913.0 - (kr   * 536870913.0 - kr)   AS kr,
    c13  * 536870913.0 - (c13  * 536870913.0 - c13)  AS c13,
    c135 * 536870913.0 - (c135 * 536870913.0 - c135) AS c135,
    c11  * 536870913.0 - (c11  * 536870913.0 - c11)  AS c11,
    c085 * 536870913.0 - (c085 * 536870913.0 - c085) AS c085,
    c08  * 536870913.0 - (c08  * 536870913.0 - c08)  AS c08,
    c26  * 536870913.0 - (c26  * 536870913.0 - c26)  AS c26,
    inv  * 536870913.0 - (inv  * 536870913.0 - inv)  AS inv
  FROM c;

-- the frame's time terms, and the three 1D sine tables, rewritten each frame
DROP TABLE IF EXISTS plasma_t;
CREATE TABLE plasma_t (t REAL, tx REAL, ty REAL, td REAL, phase REAL);
DROP TABLE IF EXISTS plasma_sx;
CREATE TABLE plasma_sx (x INTEGER PRIMARY KEY, s REAL);
DROP TABLE IF EXISTS plasma_sy;
CREATE TABLE plasma_sy (y INTEGER PRIMARY KEY, s REAL);
DROP TABLE IF EXISTS plasma_sxy;
CREATE TABLE plasma_sxy (d INTEGER PRIMARY KEY, s REAL);

-- @run frame
-- The default rung: Go's Prepare fills three 1D tables (per column, per row,
-- per diagonal), then each pixel adds three lookups and one radial sine.

-- t = float32(Beat), Beat = n/60; then t*1.3, t*1.1, t*0.8 and the phase t*2.6
DELETE FROM plasma_t;
INSERT INTO plasma_t
  WITH
  b AS (SELECT :n / 60.0 AS b),
  t AS (SELECT b * 536870913.0 - (b * 536870913.0 - b) AS t FROM b),
  p AS (SELECT t, t * c13 AS tx, t * c11 AS ty, t * c08 AS td, t * c26 AS ph FROM t, plasma_k)
  SELECT t,
    tx * 536870913.0 - (tx * 536870913.0 - tx),
    ty * 536870913.0 - (ty * 536870913.0 - ty),
    td * 536870913.0 - (td * 536870913.0 - td),
    ph * 536870913.0 - (ph * 536870913.0 - ph)
  FROM p;

-- sx[x] = Sin(float32(x)*kx + t*1.3). Sin(a) is SinTab[int(a*inv) & 8191].
REPLACE INTO plasma_sx
  WITH
  a AS (SELECT n AS x, n * kx AS a, tx, inv FROM plasma_k, plasma_t, nums WHERE n < (SELECT w FROM size)),
  b AS (SELECT x, (a * 536870913.0 - (a * 536870913.0 - a)) + tx AS a, inv FROM a LIMIT -1),
  c AS (SELECT x, (a * 536870913.0 - (a * 536870913.0 - a)) * inv AS a FROM b LIMIT -1)
  SELECT x, s FROM c
  JOIN sintab ON i = CAST(a * 536870913.0 - (a * 536870913.0 - a) AS INTEGER) & 8191;

-- sy[y] = Sin(float32(y)*ky*1.35 - t*1.1)
REPLACE INTO plasma_sy
  WITH
  a AS (SELECT n AS y, n * ky AS a, c135, ty, inv FROM plasma_k, plasma_t, nums WHERE n < (SELECT h FROM size)),
  b AS (SELECT y, (a * 536870913.0 - (a * 536870913.0 - a)) * c135 AS a, ty, inv FROM a LIMIT -1),
  c AS (SELECT y, (a * 536870913.0 - (a * 536870913.0 - a)) - ty AS a, inv FROM b LIMIT -1),
  d AS (SELECT y, (a * 536870913.0 - (a * 536870913.0 - a)) * inv AS a FROM c LIMIT -1)
  SELECT y, s FROM d
  JOIN sintab ON i = CAST(a * 536870913.0 - (a * 536870913.0 - a) AS INTEGER) & 8191;

-- sxy[d] = Sin(float32(d)*kx*0.85 + t*0.8), d = x + y
REPLACE INTO plasma_sxy
  WITH
  a AS (SELECT n AS d, n * kx AS a, c085, td, inv FROM plasma_k, plasma_t, nums WHERE n < (SELECT w + h FROM size)),
  b AS (SELECT d, (a * 536870913.0 - (a * 536870913.0 - a)) * c085 AS a, td, inv FROM a LIMIT -1),
  c AS (SELECT d, (a * 536870913.0 - (a * 536870913.0 - a)) + td AS a, inv FROM b LIMIT -1),
  e AS (SELECT d, (a * 536870913.0 - (a * 536870913.0 - a)) * inv AS a FROM c LIMIT -1)
  SELECT d, s FROM e
  JOIN sintab ON i = CAST(a * 536870913.0 - (a * 536870913.0 - a) AS INTEGER) & 8191;

-- @excerpt PLASMA
-- The pixels, in one SELECT, computed in double: the fast path. The float32
-- result can only differ where the double lands within a rounding error of
-- an integer, and there (a few pixels in ten thousand) the CASE takes the
-- exact float32 path instead. That is Ziv's strategy for correctly rounded
-- maths libraries, applied to a framebuffer.
--
-- plasma_px is scanned in rowid order, which is framebuffer order; CROSS
-- JOIN pins it as the outer loop (SQLite never reorders a CROSS JOIN), so
-- group_concat() sees the pixels in that order.
WITH
p AS (
  SELECT sx.s AS sx, sy.s AS sy, sxy.s AS sxy, rad, phase, inv,
         (rad + phase) * inv AS a                       -- the radial term's table index
  FROM plasma_k CROSS JOIN plasma_t CROSS JOIN plasma_px p
  JOIN plasma_sx sx ON sx.x = p.x
  JOIN plasma_sy sy ON sy.y = p.y
  JOIN plasma_sxy sxy ON sxy.d = p.d
  LIMIT -1
),
-- Sin(rad + phase): Go rounds rad + phase and the product to float32, which
-- moves the index by at most a * 2^-23; nearer than that to an integer, do
-- the two roundings
q AS (
  SELECT sx, sy, sxy, st.s AS s4, (sx + sy + sxy + st.s) * 36 + 127.5 AS v
  FROM p JOIN sintab st ON st.i = CASE
    WHEN abs(a - round(a)) > a * 2.4e-7 THEN CAST(a AS INTEGER)
    ELSE (SELECT CAST(b * 536870913.0 - (b * 536870913.0 - b) AS INTEGER)
          FROM (SELECT (r * 536870913.0 - (r * 536870913.0 - r)) * inv AS b
                FROM (SELECT rad + phase AS r)))
  END & 8191
  LIMIT -1
)
-- i := int(v*36 + 127.5). The four sines are float32, so their sum is exact
-- in double; Go's five float32 roundings move v by less than 3.4e-5. Nearer
-- than 1e-4 to an integer, replay them.
SELECT unhex(group_concat(hex, ''))
FROM q JOIN palette ON id = max(0, min(255, CASE
  WHEN abs(v - round(v)) > 1e-4 THEN CAST(v AS INTEGER)
  ELSE (SELECT CAST(v * 536870913.0 - (v * 536870913.0 - v) AS INTEGER)
        FROM (SELECT (v * 536870913.0 - (v * 536870913.0 - v)) + 127.5 AS v
        FROM (SELECT (v * 536870913.0 - (v * 536870913.0 - v)) * 36 AS v
        FROM (SELECT (v * 536870913.0 - (v * 536870913.0 - v)) + s4 AS v
        FROM (SELECT (v * 536870913.0 - (v * 536870913.0 - v)) + sxy AS v
        FROM (SELECT sx + sy AS v LIMIT -1) LIMIT -1) LIMIT -1) LIMIT -1) LIMIT -1))
  END));
-- @end

-- @run frame/1
-- The plasma as you would first write it: four sin() calls per pixel, every
-- argument computed per pixel, every operation rounded to float32. sin() is
-- the C one compiled into sql.js, rounded like Go's sin32.
-- t = float32(Beat), Beat = n/60; then t*1.3, t*1.1, t*0.8 and the phase t*2.6
DELETE FROM plasma_t;
INSERT INTO plasma_t
  WITH
  b AS (SELECT :n / 60.0 AS b),
  t AS (SELECT b * 536870913.0 - (b * 536870913.0 - b) AS t FROM b),
  p AS (SELECT t, t * c13 AS tx, t * c11 AS ty, t * c08 AS td, t * c26 AS ph FROM t, plasma_k)
  SELECT t,
    tx * 536870913.0 - (tx * 536870913.0 - tx),
    ty * 536870913.0 - (ty * 536870913.0 - ty),
    td * 536870913.0 - (td * 536870913.0 - td),
    ph * 536870913.0 - (ph * 536870913.0 - ph)
  FROM p;


-- @excerpt PLASMA/1
WITH
-- float32(x)*kx, float32(y)*ky, float32(x+y)*kx and the distance, per pixel
q1 AS (
  SELECT (x * kx) * 536870913.0 - ((x * kx) * 536870913.0 - (x * kx)) AS ax, (y * ky) * 536870913.0 - ((y * ky) * 536870913.0 - (y * ky)) AS ay, (d * kx) * 536870913.0 - ((d * kx) * 536870913.0 - (d * kx)) AS ad,
         (sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))) * 536870913.0 - ((sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))) * 536870913.0 - (sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)))) AS ar,
         kr, c135, c085, inv, tx, ty, td, phase
  FROM plasma_k CROSS JOIN plasma_t CROSS JOIN plasma_px
  LIMIT -1
),
-- … + t*1.3, … * 1.35, … * 0.85, rad = … * kr
q2 AS (
  SELECT (ax + tx) * 536870913.0 - ((ax + tx) * 536870913.0 - (ax + tx)) AS ax, (ay * c135) * 536870913.0 - ((ay * c135) * 536870913.0 - (ay * c135)) AS ay, (ad * c085) * 536870913.0 - ((ad * c085) * 536870913.0 - (ad * c085)) AS ad, (ar * kr) * 536870913.0 - ((ar * kr) * 536870913.0 - (ar * kr)) AS ar,
         inv, ty, td, phase
  FROM q1 LIMIT -1
),
-- … - t*1.1, … + t*0.8, rad + phase: the four sine arguments
q3 AS (
  SELECT ax, (ay - ty) * 536870913.0 - ((ay - ty) * 536870913.0 - (ay - ty)) AS ay, (ad + td) * 536870913.0 - ((ad + td) * 536870913.0 - (ad + td)) AS ad, (ar + phase) * 536870913.0 - ((ar + phase) * 536870913.0 - (ar + phase)) AS ar, inv
  FROM q2 LIMIT -1
),
-- sin32(a) = float32(math.Sin(a)): SQLite's sin(), from sql.js's libm
q4 AS (SELECT sin(ax) AS a, sin(ay) AS b, sin(ad) AS c, sin(ar) AS e FROM q3 LIMIT -1),
s AS (SELECT a * 536870913.0 - (a * 536870913.0 - a) AS a, b * 536870913.0 - (b * 536870913.0 - b) AS b, c * 536870913.0 - (c * 536870913.0 - c) AS c, e * 536870913.0 - (e * 536870913.0 - e) AS e FROM q4 LIMIT -1),
-- v = the four sines, summed in float32; i := int(v*36 + 127.5)
v1 AS (SELECT (a + b) * 536870913.0 - ((a + b) * 536870913.0 - (a + b)) AS v, c, e FROM s LIMIT -1),
v2 AS (SELECT (v + c) * 536870913.0 - ((v + c) * 536870913.0 - (v + c)) AS v, e FROM v1 LIMIT -1),
v3 AS (SELECT (v + e) * 536870913.0 - ((v + e) * 536870913.0 - (v + e)) AS v FROM v2 LIMIT -1),
v4 AS (SELECT (v * 36) * 536870913.0 - ((v * 36) * 536870913.0 - (v * 36)) AS v FROM v3 LIMIT -1)
SELECT unhex(group_concat(hex, ''))
FROM v4 JOIN palette ON id = max(0, min(255, CAST((v + 127.5) * 536870913.0 - ((v + 127.5) * 536870913.0 - (v + 127.5)) AS INTEGER)));
-- @end

-- @run frame/2
-- The same per-pixel structure, but four lookups in the sine table instead
-- of four sin() calls: a join is cheaper than a sine, even here.
-- t = float32(Beat), Beat = n/60; then t*1.3, t*1.1, t*0.8 and the phase t*2.6
DELETE FROM plasma_t;
INSERT INTO plasma_t
  WITH
  b AS (SELECT :n / 60.0 AS b),
  t AS (SELECT b * 536870913.0 - (b * 536870913.0 - b) AS t FROM b),
  p AS (SELECT t, t * c13 AS tx, t * c11 AS ty, t * c08 AS td, t * c26 AS ph FROM t, plasma_k)
  SELECT t,
    tx * 536870913.0 - (tx * 536870913.0 - tx),
    ty * 536870913.0 - (ty * 536870913.0 - ty),
    td * 536870913.0 - (td * 536870913.0 - td),
    ph * 536870913.0 - (ph * 536870913.0 - ph)
  FROM p;


-- @excerpt PLASMA/2
WITH
-- float32(x)*kx, float32(y)*ky, float32(x+y)*kx and the distance, per pixel
q1 AS (
  SELECT (x * kx) * 536870913.0 - ((x * kx) * 536870913.0 - (x * kx)) AS ax, (y * ky) * 536870913.0 - ((y * ky) * 536870913.0 - (y * ky)) AS ay, (d * kx) * 536870913.0 - ((d * kx) * 536870913.0 - (d * kx)) AS ad,
         (sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))) * 536870913.0 - ((sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))) * 536870913.0 - (sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)))) AS ar,
         kr, c135, c085, inv, tx, ty, td, phase
  FROM plasma_k CROSS JOIN plasma_t CROSS JOIN plasma_px
  LIMIT -1
),
-- … + t*1.3, … * 1.35, … * 0.85, rad = … * kr
q2 AS (
  SELECT (ax + tx) * 536870913.0 - ((ax + tx) * 536870913.0 - (ax + tx)) AS ax, (ay * c135) * 536870913.0 - ((ay * c135) * 536870913.0 - (ay * c135)) AS ay, (ad * c085) * 536870913.0 - ((ad * c085) * 536870913.0 - (ad * c085)) AS ad, (ar * kr) * 536870913.0 - ((ar * kr) * 536870913.0 - (ar * kr)) AS ar,
         inv, ty, td, phase
  FROM q1 LIMIT -1
),
-- … - t*1.1, … + t*0.8, rad + phase: the four sine arguments
q3 AS (
  SELECT ax, (ay - ty) * 536870913.0 - ((ay - ty) * 536870913.0 - (ay - ty)) AS ay, (ad + td) * 536870913.0 - ((ad + td) * 536870913.0 - (ad + td)) AS ad, (ar + phase) * 536870913.0 - ((ar + phase) * 536870913.0 - (ar + phase)) AS ar, inv
  FROM q2 LIMIT -1
),
-- Sin(a) = SinTab[int(float32(a*inv)) & 8191], four lookups per pixel
q4 AS (
  SELECT (ax * inv) * 536870913.0 - ((ax * inv) * 536870913.0 - (ax * inv)) AS ax, (ay * inv) * 536870913.0 - ((ay * inv) * 536870913.0 - (ay * inv)) AS ay, (ad * inv) * 536870913.0 - ((ad * inv) * 536870913.0 - (ad * inv)) AS ad, (ar * inv) * 536870913.0 - ((ar * inv) * 536870913.0 - (ar * inv)) AS ar
  FROM q3 LIMIT -1
),
s AS (
  SELECT s1.s AS a, s2.s AS b, s3.s AS c, s4.s AS e
  FROM q4
  JOIN sintab s1 ON s1.i = CAST(ax AS INTEGER) & 8191
  JOIN sintab s2 ON s2.i = CAST(ay AS INTEGER) & 8191
  JOIN sintab s3 ON s3.i = CAST(ad AS INTEGER) & 8191
  JOIN sintab s4 ON s4.i = CAST(ar AS INTEGER) & 8191
  LIMIT -1
),
-- v = the four sines, summed in float32; i := int(v*36 + 127.5)
v1 AS (SELECT (a + b) * 536870913.0 - ((a + b) * 536870913.0 - (a + b)) AS v, c, e FROM s LIMIT -1),
v2 AS (SELECT (v + c) * 536870913.0 - ((v + c) * 536870913.0 - (v + c)) AS v, e FROM v1 LIMIT -1),
v3 AS (SELECT (v + e) * 536870913.0 - ((v + e) * 536870913.0 - (v + e)) AS v FROM v2 LIMIT -1),
v4 AS (SELECT (v * 36) * 536870913.0 - ((v * 36) * 536870913.0 - (v * 36)) AS v FROM v3 LIMIT -1)
SELECT unhex(group_concat(hex, ''))
FROM v4 JOIN palette ON id = max(0, min(255, CAST((v + 127.5) * 536870913.0 - ((v + 127.5) * 536870913.0 - (v + 127.5)) AS INTEGER)));
-- @end

-- @run frame/4
-- Not a rung of Go's ladder: the default rung in plain double, without a
-- single f32(), to measure what the rounding is worth. Only the tables built
-- at resize (rad, the sine table) still hold Go's float32 values.
-- `node tools/check.mjs --scene 2 --step 4 sql` compares it with Go.
DELETE FROM plasma_t;
INSERT INTO plasma_t SELECT t, t * 1.3, t * 1.1, t * 0.8, t * 2.6 FROM (SELECT :n / 60.0 AS t);
REPLACE INTO plasma_sx
  SELECT n, s FROM size, plasma_t, nums
  JOIN sintab ON i = CAST((n * (26.0 / w) + tx) * (8192 / (2 * pi())) AS INTEGER) & 8191
  WHERE n < w;
REPLACE INTO plasma_sy
  SELECT n, s FROM size, plasma_t, nums
  JOIN sintab ON i = CAST((n * (26.0 / h) * 1.35 - ty) * (8192 / (2 * pi())) AS INTEGER) & 8191
  WHERE n < h;
REPLACE INTO plasma_sxy
  SELECT n, s FROM size, plasma_t, nums
  JOIN sintab ON i = CAST((n * (26.0 / w) * 0.85 + td) * (8192 / (2 * pi())) AS INTEGER) & 8191
  WHERE n < w + h;
SELECT unhex(group_concat(hex, ''))
FROM plasma_t CROSS JOIN plasma_px p
JOIN plasma_sx sx ON sx.x = p.x
JOIN plasma_sy sy ON sy.y = p.y
JOIN plasma_sxy sxy ON sxy.d = p.d
JOIN sintab st ON st.i = CAST((rad + phase) * (8192 / (2 * pi())) AS INTEGER) & 8191
JOIN palette ON palette.id = max(0, min(255, CAST((sx.s + sy.s + sxy.s + st.s) * 36 + 127.5 AS INTEGER)));
