# Banc d'essai Goose — le plasma

Un seul effet porté de `go/internal/fx/plasma.go` en Goose, pour savoir si
l'outillage tient la route avant d'engager un portage complet. Le portage est
fidèle : sur un même instant, les deux rendus diffèrent de **2 pixels sur
921 600** (écart maximal 5/255, dû à l'arrondi f32/f64 dans la table de sinus).
La comparaison porte donc bien sur le même travail.

Machine : M1, 8 cœurs, macOS 27. Goose compilé par le compilateur officiel
(`goose build`), Go 1.27.2. 1280×720, 240 images mesurées après 20 de chauffe.

## Les chiffres

| | médiane | Mpx/s |
| --- | ---: | ---: |
| Go, 1 worker | 1,53 ms | 600 |
| **Goose, 1 thread** | **1,48 ms** | **623** |
| Go, 8 workers (le `bandPool` de la démo) | **0,46 ms** | **1 995** |
| **Goose, 8 threads** | **0,75 ms** | **1 230** |

À 2560×1440, la conclusion ne bouge pas : Goose série 5,88 ms contre Go
série 6,09 ms.

## Ce que ça dit

**En série, Goose est à la hauteur de Go, voire devant.** 1,48 ms contre
1,53 ms, avec un écart stable run après run. Ce n'était pas acquis : une
première version, écrite avec des tableaux dynamiques (`u32[>..]`), tournait
en 2,02 ms — 36 % plus lent — parce que chaque index coûtait un contrôle de
bornes et chaque conversion flottante un appel `GS_F2I`. Le passage aux
tableaux fixes fait élider 62 contrôles sur 79 et supprime les appels.

**En parallèle, Goose perd 63 %.** Et la cause n'est pas la vitesse du code
généré, c'est le modèle de mémoire. Goose interdit toute mémoire partagée
entre threads (spec §11.2) : un worker est une instance de programme avec sa
propre copie de chaque globale, et seules les valeurs *plates* — sans
référence ni slice — franchissent une frontière de thread. Conséquences
concrètes :

- `Draw(fb, y0, y1)` écrivant sa bande du framebuffer partagé n'existe pas.
  Une bande doit être calculée dans `u32[1280][90]`, renvoyée par la queue,
  puis recopiée par `main`. Mesuré : **0,136 ms/frame** de copie pure.
- Une queue typée (`qget<T>`) est une **file de travail partagée**, pas une
  boîte aux lettres par worker. Huit jobs postés, le premier worker arrivé en
  prend trois, un autre aucun. Il faut donc que le job nomme sa bande et que
  `main` réassemble par ce champ. C'est ce qui a produit les 85 000 pixels
  faux du premier essai, corrigés en réassemblant par `y0`.
- Chaque worker garde sa copie du champ de distance : **8 × 3,7 Mo**.

## Le contrôle qui compte

Pour vérifier que l'écart parallèle est bien une conséquence du modèle et non
de mon code, j'ai réécrit le même plasma **en Go**, mais contraint au modèle
de Goose : workers persistants, tables privées, bande calculée dans un
tampon et renvoyée par canal, `main` qui recopie.

| | médiane |
| --- | ---: |
| Go natif (le `bandPool` actuel) | 0,46 ms |
| Go contraint au modèle Goose | **0,64 ms** |
| Goose, sous le même modèle | **0,75 ms** |

Sous le même modèle, Goose ne paie plus que **17 %** de ralentissement, et ce
qui restait est la boucle elle-même. Le surcoût dominante — 0,46 → 0,64 ms —
est le prix du modèle, pas celui du langage.

## Verdict

L'outillage tient : compilateur qui se construit, erreurs claires, FFI, C
généré lisible, `bytes_of`/`write_file`, aucun plantage en 240 images.
Le langage tient sa promesse de vitesse en série.

Ce qu'il ne permet pas, c'est d'écrire la démo telle qu'elle est écrite
aujourd'hui. Le `bandPool` — N goroutines, un framebuffer partagé, zéro
copie — est le cœur de l'argument parallèle de la démo, et Goose l'interdit
par construction. Un portage complet serait possible, mais il faudrait soit
accepter les copies par queue (et la démo afficherait un chiffre moins
flatteur), soit réécrire chaque effet pour produire des bandes autonomes.

## Construire et lancer

```sh
goose build plasma.goose -o plasma
./plasma
```

Affiche les deux régimes, vérifie que les deux rendus sont identiques
octet pour octet, et écrit `plasma_goose.ppm` pour comparaison avec le rendu
Go.
