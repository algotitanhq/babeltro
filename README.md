# rosette

Une même démo demoscene, calculée pixel par pixel sur le CPU, écrite dans
plusieurs langages. Comme la pierre de Rosette : un seul texte, plusieurs
écritures.

Le but n'est pas de savoir quel langage gagne. C'est de voir ce que chaque
langage oblige à écrire différemment pour produire **exactement la même
image** : modèle de mémoire, parallélisme, arithmétique flottante, contrôles
de bornes, liaisons avec le système.

## Règle du jeu

Chaque portage doit rendre, au même instant, la même image que la référence
Go, à l'octet près. Les écarts tolérés sont mesurés et expliqués, jamais
ignorés.

## Portages

| Dossier | Langage | État |
| --- | --- | --- |
| `go/` | Go | référence : neuf scènes, fenêtre, HUD, `-bench`, `-dump` |
| `goose/` | Goose | banc d'essai : la scène PLASMA seule (voir `goose/RESULTS.md`) |
