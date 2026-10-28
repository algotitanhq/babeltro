-- GRID: the synthwave floor under a banded sun, as in go/internal/fx/grid.go.
--
-- Go mixes float32 and float64 here more than anywhere: Clamp01 works in
-- float64, the colours are float32. Every float32 operation is rounded with
-- f32(v) = v*S - (v*S - v), S = 2^29+1 (see tables.sql); float64 ones are
-- plain REAL arithmetic.

-- @run resize
DROP TABLE IF EXISTS grid_row;
CREATE TABLE grid_row (
  y INTEGER PRIMARY KEY, kind INTEGER,          -- 0 sky, 1 sky with the sun's disk, 2 floor
  sky TEXT, skyr REAL, skyg REAL, skyb REAL,
  -- the sun on this row
  dyc2 REAL, sg REAL, sb REAL,
  -- the floor on this row
  dz REAL, kx REAL, fadex REAL, wb REAL, linez REAL,
  floorr REAL, floorg REAL, floorb REAL, zr REAL, zg REAL, zb REAL
);
DROP TABLE IF EXISTS grid_k;
CREATE TABLE grid_k (cx REAL, sunr REAL, sunk REAL);

-- @run frame
-- Everything that depends only on the row, as Go hoists it: the sky ramp,
-- the sun's band, and on the floor the perspective, the depth lines (lineZ)
-- and the fog. One row of grid_row per screen row.
DELETE FROM grid_k;
INSERT INTO grid_k
  SELECT w * 0.5, F32(h * F32(0.16)), F32(F32(h * F32(0.16)) * F32(0.025)) FROM size;
REPLACE INTO grid_row
  WITH
  k AS MATERIALIZED (
    SELECT w, h, F32(:n / 60.0) AS t, F32(h * F32(0.52)) AS horizon, F32(CAST(h AS REAL) / w) AS asp,
           F32(h * F32(0.16)) AS sunr
    FROM size
  ),
  k2 AS MATERIALIZED (SELECT *, F32(horizon - F32(h * F32(0.13))) AS suny FROM k),
  r0 AS MATERIALIZED (
    SELECT n AS y, k2.*, n > horizon AS floor, F32(n - horizon) AS dz, F32(n - suny) AS dyc,
           max(0.0, min(1.0, F32(n / horizon))) AS sky
    FROM k2, nums WHERE n < h
  ),
  -- the perspective: z = (h*0.55)/dz, world depth wz, world x per pixel kx
  r1 AS MATERIALIZED (
    SELECT *, F32(F32(h * F32(0.55)) / dz) AS z,
           F32(0.03 + 0.18 * sky * sky) AS skyr, F32(0.01 + 0.05 * sky) AS skyg, F32(0.08 + 0.22 * sky) AS skyb
    FROM r0
  ),
  r2 AS MATERIALIZED (
    SELECT *,
      F32(F32(z * F32(2.5)) + F32(t * F32(5.5))) AS wz,
      F32(F32(F32(z / F32(w * 0.5)) * asp) * 2) AS kx,
      F32(F32(dz * dz) / F32(1.375 * h)) AS period,      -- pixels per unit of wz
      F32(F32(0.014) + F32(F32(0.024) / z)) AS lwz,
      max(0.0, min(1.0, F32(1.0 / F32(1 + F32(F32(z * z) * F32(0.004)))))) AS fog,
      max(0.0, min(1.0, F32(dz / F32(h * F32(0.12))))) AS haze
    FROM r1
  ),
  -- mathMod2(wz) = wz - float32(int(wz)), +1 if negative (exact in float32)
  r3 AS MATERIALIZED (
    SELECT *,
      max(0.0, min(1.0, F32(F32(F32(1 / kx) - 1.5) / 2))) AS fadex,
      F32(0.5 / period) AS minw,
      iif(wz - CAST(wz AS INTEGER) < 0, F32(wz - CAST(wz AS INTEGER) + 1), wz - CAST(wz AS INTEGER)) AS m,
      max(0.0, min(1.0, F32(F32(period - 1.5) / 2))) AS pfade
    FROM r2
  ),
  -- a line narrower than a pixel is widened to one and dimmed to match
  r4 AS MATERIALIZED (
    SELECT *, iif(lwz < minw, F32(lwz / minw), 1.0) AS ampz, max(lwz, minw) AS lw,
           iif(m > 0.5, 1 - m, m) AS d
    FROM r3
  ),
  -- lineZ = lineGlow(m, lw) * ampZ, then faded by the period and the fog
  r5 AS MATERIALIZED (
    SELECT *, F32(iif(d < lw, F32(1 - F32(d / lw)), 0.0) * ampz) AS lz FROM r4
  ),
  r6 AS MATERIALIZED (SELECT *, F32(F32(lz * pfade) * fog) AS linez FROM r5),
  -- the sun: rows within its radius, cut by stripes on the lower part
  r7 AS MATERIALIZED (
    SELECT *,
      dyc > -sunr AND dyc < sunr AND y < F32(horizon + 2) AS sunrow,
      y > F32(suny - F32(sunr * F32(0.45))) AND y % 9 < 4 AS stripe,
      max(0.0, min(1.0, F32(F32(y - F32(suny - sunr)) / F32(2 * sunr)))) AS u
    FROM r6
  )
  SELECT y,
    CASE WHEN floor THEN 2 WHEN sunrow AND NOT stripe THEN 1 ELSE 0 END,
    printf('%02X%02X%02XFF',
      iif(skyr <= 0, 0, iif(skyr >= 1, 255, CAST(skyr * 255 + 0.5 AS INTEGER))),
      iif(skyg <= 0, 0, iif(skyg >= 1, 255, CAST(skyg * 255 + 0.5 AS INTEGER))),
      iif(skyb <= 0, 0, iif(skyb >= 1, 255, CAST(skyb * 255 + 0.5 AS INTEGER)))),
    skyr, skyg, skyb,
    F32(dyc * dyc), F32(0.95 - 0.7 * u), F32(0.25 + 0.55 * u),
    dz, kx, fadex, F32(F32(2 * F32(0.022)) / kx), linez,
    -- floor colour: base, + the haze near the horizon, + the depth line
    F32(F32(F32(0.02) + F32(0.25 * (1 - haze))) + F32(F32(0.55) * linez)),
    F32(F32(F32(0.01) + F32(0.05 * (1 - haze))) + F32(F32(0.35) * linez)),
    F32(F32(F32(0.06) + F32(0.35 * (1 - haze))) + F32(F32(0.75) * linez)),
    F32(F32(0.55) * linez), F32(F32(0.35) * linez), F32(F32(0.75) * linez)
  FROM r7;

-- @excerpt GRID
-- Per pixel, only what depends on x: the sun's disk (a square root, only
-- inside its box) and, on the floor, the lines across: lineX, widened to the
-- distance the ray slides between rows, dimmed by the same ratio.
WITH
p1 AS (
  SELECT g.*, x.n - cx AS dx, sunr, sunk,
         -- the floor: the slide, wPx, and the fractional world x
         iif(kind = 2, max(1.0, max(F32(abs(x.n - cx) / dz), wb)), NULL) AS wpx,
         iif(kind = 2, F32(F32((x.n - cx) * kx) + F32(0.37)), NULL) AS a,
         -- the sun: distance to its centre
         iif(kind = 1 AND x.n - cx > -sunr AND x.n - cx < sunr,
             F32(sqrt(F32(F32((x.n - cx) * (x.n - cx)) + dyc2))), NULL) AS d
  FROM grid_k CROSS JOIN grid_row g CROSS JOIN size CROSS JOIN nums x
  WHERE x.n < w
  LIMIT -1
),
p2 AS (
  SELECT *,
    iif(a - CAST(a AS INTEGER) < 0, F32(a - CAST(a AS INTEGER) + 1), a - CAST(a AS INTEGER)) AS m,
    F32(wpx * kx) * 0.5 AS lw, F32(wb / wpx) AS amp,
    iif(d < sunr, max(0.0, min(1.0, F32(F32(sunr - d) / sunk))), NULL) AS edge
  FROM p1 LIMIT -1
),
p3 AS (
  SELECT *, iif(m > 0.5, 1 - m, m) AS dm FROM p2 LIMIT -1
),
-- line = max(lineX, lineZ); the colour is floor - 0.55*lineZ + 0.55*line;
-- on the sun, mix(sky, sun, edge)
p4 AS (
  SELECT kind, sky, skyr, skyg, skyb, sg, sb, edge, floorr, floorg, floorb, zr, zg, zb,
         max(F32(F32(iif(dm < lw, F32(1 - F32(dm / lw)), 0.0) * amp) * fadex), linez) AS line
  FROM p3 LIMIT -1
),
p5 AS (
  SELECT kind, sky,
    CASE WHEN kind = 2 THEN F32(F32(floorr - zr) + F32(F32(0.55) * line))
         ELSE F32(skyr + F32(F32(1 - skyr) * edge)) END AS r,
    CASE WHEN kind = 2 THEN F32(F32(floorg - zg) + F32(F32(0.35) * line))
         ELSE F32(skyg + F32(F32(sg - skyg) * edge)) END AS g,
    CASE WHEN kind = 2 THEN F32(F32(floorb - zb) + F32(F32(0.75) * line))
         ELSE F32(skyb + F32(F32(sb - skyb) * edge)) END AS b,
    kind = 2 OR edge IS NOT NULL AS own
  FROM p4 LIMIT -1
)
SELECT unhex(group_concat(iif(own, printf('%02X%02X%02XFF',
    iif(r <= 0, 0, iif(r >= 1, 255, CAST(r * 255 + 0.5 AS INTEGER))),
    iif(g <= 0, 0, iif(g >= 1, 255, CAST(g * 255 + 0.5 AS INTEGER))),
    iif(b <= 0, 0, iif(b >= 1, 255, CAST(b * 255 + 0.5 AS INTEGER)))), sky), ''))
FROM p5;
-- @end
