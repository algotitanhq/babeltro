# babeltro — portage Go (référence)

Une démo demoscene entièrement calculée par le CPU, écrite en Go.

Chaque pixel de chaque scène sort d'une boucle Go. La carte graphique ne sert
qu'à une chose : afficher l'image finie en un seul quad texturé. Pas de shader,
pas de moteur de jeu, aucune dépendance Go externe — juste la bibliothèque
standard, deux liaisons cgo écrites à la main (GLFW et OpenGL 2.1), et un
framebuffer `[]uint32`.

L'instrumentation affichée en permanence n'est pas décorative : c'est la thèse
de la démo. Elle mesure, image par image, le temps CPU réel comparé au budget
de 16,67 ms d'un écran 60 Hz.

## Lancer

```sh
go build -o babeltro ./cmd/babeltro
./babeltro                # 1280x720, 8 goroutines
./babeltro -fs            # plein écran
./babeltro -w 1920 -h 1080
```

`go run ./cmd/babeltro` marche aussi, mais un binaire compilé démarre plus vite.

| Touche | Effet |
| --- | --- |
| `Échap` | quitter |
| `H` | masquer/afficher l'instrumentation |
| `S` | scène suivante |
| `→` / `←` | scène suivante / précédente |
| `F` | plein écran |
| `F1` | (re)démarrer au début |

Autres modes :

```sh
./babeltro -list                        # les scènes et leurs durées
./babeltro -bench -w 1280 -h 720        # coût mesuré de chaque effet
./babeltro -dump /tmp/shots -at 5       # rendu PNG sans fenêtre (itération visuelle)
./babeltro -scene 4                     # démarrer à une scène donnée
./babeltro -stats                       # mesures en direct sur stdout, une par seconde
./babeltro -stats -dur 30               # idem, et quitte au bout de 30 s
```

Sur un écran Retina, la fenêtre de 1280×720 couvre 2560×1440 pixels physiques :
c'est cette résolution-là que la démo calcule.

## Les scènes

| # | Scène | Ce que fait le CPU |
| --- | --- | --- |
| 1 | STARFIELD | 2400 étoiles projetées en perspective, traînées en Bresenham additif |
| 2 | TUNNEL | coordonnées polaires tabulées, texture procédurale, brouillard |
| 3 | PLASMA | quatre champs sinusoïdaux en tables, un sinus tabulé par pixel |
| 4 | ROTOZOOM | une texture 512×512 générée au démarrage, échantillonnée en rotation |
| 5 | METABALLS | six champs `r²/d²` par pixel, iso-surface et liseré |
| 6 | GRID | sol synthwave en division perspective, soleil à bandes |
| 7 | FIRE | automate de propagation, tampon `uint8`, palette |
| 8 | MANDELBROT | plongée dans la vallée du cheval, blocs 2×2, itérations adaptatives |
| 9 | FINALE | logo en dégradé, reflet, texte — tout en pixels |

## Pourquoi c'est rapide

Quelques principes, tous visibles dans le code :

**Tabuler plutôt que calculer.** `internal/fmath` contient une table de sinus
de 8192 entrées ; les effets y accèdent au lieu d'appeler `math.Sin`. Le tunnel
précalcule `1/r` et `atan2` une fois par taille d'écran, pas une fois par pixel.

**Précalculer ce qui ne bouge pas.** Le fond du starfield est peint une seule
fois dans un tampon, puis recopié par `copy` à chaque image : 0,15 ms au lieu
de 2,8 ms. Les palettes sont des rampes de 256 couleurs construites au
chargement, indexées par un `int` ensuite.

**Sortir les invariants des boucles.** Dans la grille, tout ce qui ne dépend que
de la ligne (division perspective, brouillard, période des lignes) est calculé
une fois par ligne ; la boucle des pixels ne garde qu'une multiplication et deux
recherches.

**Paralléliser sans allouer.** `internal/engine/pool.go` démarre N goroutines
persistantes qui se partagent l'image en bandes horizontales. Pas de goroutine
ni de closure créée par image : le pool est construit au démarrage et réutilisé.

**Zéro allocation par image.** Le HUD formate ses nombres dans un tableau
`[512]byte` réutilisé. Les effets possèdent leurs tampons et les redimensionnent
seulement quand la fenêtre change. L'instrumentation affiche le résultat :
`0 B/FRAME`.

**Accepter le compromis honnête.** Le Mandelbrot est rendu sur une grille de
2×2 pixels étirée, et son budget d'itérations suit le zoom : 64 quand la vue
est large, 192 quand il faut tenir la frontière. En mouvement, personne ne voit
la grille, et le coût reste dans le budget. La démo ne triche pas sur ce qu'elle
mesure : elle choisit ce qu'elle calcule.

## Les chiffres

Mesurés par `./babeltro -bench` (240 images par effet, les 24 premières écartées),
sur un M1 8 cœurs :

**1280×720 (0,92 Mpx)**

| Scène | médiane | meilleur | Mpx/s |
| --- | ---: | ---: | ---: |
| STARFIELD | 0,19 ms | 0,15 ms | 4 742 |
| TUNNEL | 0,86 ms | 0,82 ms | 1 076 |
| PLASMA | 0,46 ms | 0,41 ms | 1 987 |
| ROTOZOOM | 0,35 ms | 0,31 ms | 2 612 |
| METABALLS | 1,63 ms | 1,57 ms | 565 |
| GRID | 1,85 ms | 1,53 ms | 500 |
| FIRE | 2,79 ms | 2,67 ms | 330 |
| MANDELBROT | 1,65 ms | 1,38 ms | 560 |
| FINALE | 1,22 ms | 1,21 ms | 757 |

Le budget 60 Hz est de 16,67 ms. L'effet le plus lourd en consomme 2,8 : six
fois moins que le budget, pour 0,92 million de pixels calculés à la main.

**2560×1440 (3,69 Mpx, la taille réelle de la fenêtre sur Retina)**

| Scène | médiane | meilleur | Mpx/s |
| --- | ---: | ---: | ---: |
| STARFIELD | 0,62 ms | 0,52 ms | 5 939 |
| TUNNEL | 3,16 ms | 3,05 ms | 1 168 |
| PLASMA | 1,52 ms | 1,45 ms | 2 433 |
| ROTOZOOM | 1,13 ms | 1,08 ms | 3 260 |
| METABALLS | 6,26 ms | 6,16 ms | 589 |
| GRID | 7,08 ms | 6,01 ms | 521 |
| FIRE | 7,82 ms | 7,65 ms | 471 |
| MANDELBROT | 3,21 ms | 2,61 ms | 1 150 |
| FINALE | 4,76 ms | 4,72 ms | 775 |

Quatre fois plus de pixels : l'effet le plus lourd passe de 2,8 à 7,8 ms et
tient encore ses 60 Hz en pleine résolution Retina, sans GPU, en calculant
chaque pixel dans une goroutine.

## Organisation

```
cmd/babeltro/       main : fenêtre, boucle, drapeaux, mode -dump, mode -bench
internal/glfwc/     liaison GLFW + activation de l'app (Objective-C)
internal/glc/       liaison OpenGL 2.1 : un seul quad texturé
internal/canvas/    framebuffer, primitives, police bitmap 5×7
internal/palette/   rampes de 256 couleurs
internal/fmath/     tables trigonométriques et polaires
internal/fx/        les neuf effets, une interface commune
internal/engine/    horloge, timeline, pool de bandes, mesure
internal/hud/       l'instrumentation dessinée à la main
```

Un effet implémente quatre méthodes : `Name`, `Resize`, `Prepare` (une fois par
image, monothread, construit les tables de l'image) et `Draw(fb, y0, y1)`
(une bande, appelée en parallèle). C'est tout le contrat.

## Ce que ça démontre

Que le Go de tous les jours — sans SIMD explicite, sans `unsafe` dans les
boucles chaudes, sans astuce de compilation — tient un million de pixels par
image à 60 Hz en le écrivant comme on écrit du Go : clair, tabulé, parallèle
là où ça compte, et mesuré honnêtement.
