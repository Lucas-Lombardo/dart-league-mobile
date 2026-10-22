# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Deux publics à parts égales, confirmés par Lucas (2026-10-13) :

- **Le joueur amateur à la maison.** Francophone, cible acier chez lui, téléphone posé sur un trépied face à la cible. Il veut de vrais adversaires et une progression mesurable sans club ni bar.
- **Le joueur de club / ligue.** Licencié ou habitué des compétitions, il s'entraîne entre deux séances et veut un suivi de niveau sérieux (moyennes, doubles, checkouts, historique).

Situation d'usage commune : debout, à distance de lancer, le téléphone hors de portée pendant la volée. Le joueur regarde l'écran entre deux volées, souvent de loin ; il ne peut corriger qu'en un geste rapide avant de revenir à la ligne. Les matchs durent de 10 à 30 minutes, parfois en soirée dans une pièce peu éclairée.

Autres rôles existants : spectateur (regarde les matchs classés et de tournoi en direct), organisateur communautaire (crée un tournoi amical), admin Dart Rivals (back-office séparé dans `backend/`, hors périmètre de l'app).

## Product Purpose

Dart Rivals permet de jouer de vrais matchs de fléchettes à distance, sur une vraie cible, contre de vrais adversaires, avec comptage automatique par la caméra du téléphone et vidéo en direct. Autour de ce cœur, l'app porte une échelle compétitive complète (placement, ELO, rangs, saisons, tournois, trophées) et un module d'entraînement.

Succès (confirmé 2026-10-13) : **la rétention** (des joueurs qui reviennent chaque semaine pour les saisons et les tournois récurrents) et **la conversion Premium**. La croissance brute du nombre d'inscrits et la perception du scoring ne sont pas les indicateurs retenus, même si la fiabilité de l'IA reste une condition de la rétention.

## Positioning

La différence revendiquée est **la compétition** : ELO, saisons avec récompense, tournois (gratuits, payants, communautaires), trophée physique imprimé envoyé au vainqueur. Un voisin qui compte les fléchettes (DartsMind, Scolia, DartConnect) ne propose pas cette échelle vivante avec de vrais enjeux et de vrais adversaires à distance.

Le scoring IA par la caméra du téléphone, sans matériel dédié, est le moyen qui rend cette compétition possible : il est une fonctionnalité principale, jamais une option dégradable. Il n'est pas, à lui seul, la promesse.

## Operating Context

- **Matériel du joueur** : cible acier à la maison, téléphone iOS ou Android sur trépied, face à la cible. Pas de capteur ni de caméra dédiée. Le parc Android est hétérogène ; l'app mesure la capacité du téléphone pour choisir le modèle IA (voir `lib/services/model_selector.dart`).
- **Réseau** : match en P2P WebRTC (signalisation via le socket, TURN Cloudflare) avec vidéo live de l'adversaire et audio. Reconnexions et reprise après arrière-plan sont des cas normaux, pas des exceptions.
- **Déroulé d'un match classé** : réglage caméra (porte de démarrage : modèle chargé + cible détectée), matchmaking, 501 en BO3, scoring IA volée par volée avec confirmation, correction manuelle en un appui, fin de leg / fin de match, confirmation de victoire négociée par les deux apps, variation d'ELO, possibilité de signaler une volée.
- **Preuves** : clips vidéo des volées enregistrés localement et envoyés au serveur ; servent aux litiges traités par l'admin. Offre gratuite : 5 clips stockés.
- **Rythme communautaire** : tournois récurrents (ex. Tournoi du Mercredi), saisons numérotées avec champion, classement, spectateurs en direct. Promotion via publicités Meta et TikTok (@Dodo180).
- **Environnement sonore** : annonceur vocal (caller) et sons de jeu coexistent avec l'audio de l'appel ; voir `lib/utils/app_audio_context.dart`.
- **Backend** : API NestJS/PostgreSQL/Redis/Socket.IO dans `backend/`, dépôt Git séparé ; l'app ne doit pas rompre les contrats existants.

## Capabilities and Constraints

Fonctionnalités en place (relevé du code, 2026-10-13) :

- **Compte** : inscription, connexion, mot de passe oublié, profil, parrainage (code → jours de Premium offerts).
- **Classé** : placement contre bots par rang (bronze → master), matchmaking, ELO avec plancher à 1 après placement, rangs (unranked, bronze, silver, gold, plat, diamond, master), saisons, classement, historique et détail de match, face-à-face, statistiques détaillées (niveau, impacts, doubles, comparaison).
- **Tournois** : officiels gratuits ou payants (Stripe pour le droit d'entrée, remise Premium de 50 %), prix en cash ou trophée physique, tournois communautaires amicaux (ouverts à tous, sans ELO, 48 h d'avance, 8 joueurs minimum), bracket, écran de préparation, résultat, contestation.
- **Amis** : liste d'amis, chat, invitations à des séries amicales (501 ou Cricket, BO1/3/5/7, sans ELO ; Premium requis des deux côtés).
- **Local** : match à deux sur un même téléphone avec IA (501 ou Cricket), mode arbitre 501 sans IA (saisie manuelle par volée).
- **Entraînement** : Around the Clock (simple, double, triple), Bob's 27, High Score, Checkout 50/81/121, entraînement contre bot, JDC Challenge, Important Doubles, Quick Count (calcul mental), Checkout Vision.
- **Spectateur** : hub des matchs en direct (classé et tournois), vue spectateur.
- **Replays** : bibliothèque de clips, lecteur.
- **Premium** : 4,99 €/mois ou annuel, via achats intégrés Apple/Google. Déverrouille matchs classés illimités (quota quotidien côté serveur en gratuit), tournois illimités (quota mensuel en gratuit), matchs amicaux, clips illimités, badge Premium.
- **Langues** : français et anglais, chaîne par chaîne (`lib/l10n/`). Le français est la langue de référence.

Contraintes durables :

- **Scoring IA** : jamais désactivé ni dégradé comme remède (chauffe, batterie). Aucun match classé ne démarre sans IA fonctionnelle. Une fléchette comptée par l'IA n'est jamais modifiée ni retirée par l'IA ensuite (émission unique). Le motion gating est refusé. Voir `../docs/ai-context/notes/mobile/ai-scoring-product-rules.md`.
- **Correction manuelle** : la modale grille de nombres (simple/double/triple, manqué, bulls), un appui soumet et ferme. Ne jamais la remplacer par une cible interactive avec bouton Valider ni par un effacement/re-lancer.
- **Format classé** : 501 en BO3 uniquement, décision acceptée ; pas d'opt-in.
- **Transport vidéo** : P2P WebRTC uniquement ; Agora a été retiré et ne doit pas revenir.
- **Texte système agrandi** : borné à 1,1× dans l'app (décision produit, les mises en page cassent au-delà).
- **Pas de package ajouté sans accord** ; `flutter analyze` sans nouveau warning après chaque modification.
- **Plateformes** : iOS 15+ (iPhone et iPad, famille 1,2) et Android ; une seule langue visuelle partagée. Le build web/PWA de mai 2026 est **abandonné** (confirmé 2026-10-13) : les notes et le dossier `web/` sont historiques, aucun nouvel écran ne doit le prendre en compte.

Décisions ouvertes, à ne pas inventer :

- Le classé est 501 uniquement aujourd'hui (aucun Cricket dans le matchmaking) ; l'ajout du Cricket en classé n'est pas décidé. Il existe en local, contre bot et en série amicale.
- Les descriptions des fiches App Store / Play Store sont obsolètes (pas de mention du scoring IA, des tournois, de l'entraînement) et restent à réécrire.

## Brand Commitments

- **Nom** : Dart Rivals. Les chaînes `appName = 'Dart Legends'` et le vocabulaire « Légende » (« Bon retour, Légende ») sont des reliquats à ne plus propager (confirmé 2026-10-13).
- **Voix** : tutoiement partout, ton direct et sobre, sans grandiloquence. Les chaînes au vouvoiement (« Débloquez… ») sont à aligner au fil des retouches. Les libellés en capitales hérités sont passés en casse de phrase par le système actuel.
- **Identité en place** : logo dans `assets/logo/` (avec et sans lettres), badges de rangs dans `assets/ranks/`, trophée 3D (`/trophy`) comme objet réel de la compétition. Police actuelle Manrope (OFL) ; le système visuel 2026-09 vit dans `lib/utils/app_theme.dart` et `lib/widgets/design_system.dart`. Ces faits décrivent l'existant ; ils ne fixent pas la direction visuelle future.
- **Contenu créateur** : vidéos TikTok @Dodo180 produites dans `/montage`, qui rejouent les écrans de l'app en React pour les inserts.

## Evidence on Hand

- **Données réelles** : production Postgres accessible en lecture seule via `backend/scripts/prodsql` (effectifs, matchs, tournois). Toujours relever un chiffre avant de l'affirmer.
- **Tournois et saisons réels** : Tournoi du Mercredi, saisons avec champion et trophée expédié par Mondial Relay.
- **Matériel de capture** : `make store-screenshots` rend les captures App Store / Play Store sans simulateur (scènes dans `test/preview/`).
- **Image de cible** : `test/preview/store/board_frame.jpg` ; frames de match réelles pour le banc IA (non embarquées).
- **Absences** : pas de témoignages, d'avis presse, de benchmark public ni de chiffres de précision IA publiables. Ne pas en inventer.

## Product Principles

1. **La compétition est le produit.** Chaque écran sert à entrer en match, à y rester ou à mesurer sa progression ; une fonctionnalité qui n'alimente pas l'échelle (ELO, saisons, tournois) est secondaire.
2. **La fiabilité du comptage se protège avant tout.** Aucune optimisation (chauffe, batterie, perf) ne touche la cadence ni la précision de l'IA en situation normale ; la correction reste à un appui.
3. **Lisible de loin, pilotable d'un geste.** Le joueur est à la ligne de lancer, souvent sans les mains libres : scores et état du match se lisent à distance, chaque action critique tient en un appui.
4. **Les deux joueurs sont servis au même niveau.** Amateur à domicile et joueur de club partagent les mêmes outils ; la profondeur (stats, doubles, checkouts) ne doit pas alourdir le parcours simple.
5. **Premium élargit, il n'enferme pas.** Les limites gratuites (matchs, tournois, clips) sont explicites et le passage à Premium est proposé au moment utile, sans bloquer la pratique de base ni la compétition communautaire.

## Accessibility & Inclusion

- Agrandissement du texte système borné à 1,1× ; toute nouvelle mise en page doit tenir jusqu'à cette borne et à 320 × 568 px en portrait et en paysage.
- Lecture à distance : contraste et taille des scores en match priment sur la densité d'information.
- Pas d'autre exigence ou norme établie à ce jour.
