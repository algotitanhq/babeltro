# babeltro

Une intro demoscene calculée pixel par pixel sur le CPU, puis réécrite dans
plusieurs langages. Babel pour les langues, « tro » pour l'intro : chaque
langage refait la même prod.

Le but n'est pas de savoir quel langage gagne. C'est de voir ce que chaque
langage oblige à écrire différemment pour produire **la même image** :
modèle de mémoire, parallélisme, arithmétique flottante, contrôles de bornes,
liaisons avec le système.

## Règle du jeu

Chaque portage doit rendre, au même instant, la même image que la référence
Go, à l'octet près. La seule différence voulue : le nom du langage, que la
démo affiche dans son logo, son texte défilant et son HUD
(`go/internal/brand`). Les autres écarts sont mesurés et expliqués, jamais
ignorés.

## Portages

| Dossier | Langage | État |
| --- | --- | --- |
| `go/` | Go | référence : neuf scènes, fenêtre, HUD, `-bench`, `-dump` |
| `goose/` | Goose | banc d'essai : la scène PLASMA seule (voir `goose/RESULTS.md`) |
