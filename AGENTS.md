# App Flutter Dart Rivals

Lire [le contexte commun](../AGENTS.md) et [les repères actuels](../docs/ai-context/CURRENT.md). Ce fichier permet de retrouver la mémoire même lorsque Codex démarre directement dans le dépôt mobile.

## Architecture et conventions

- Flutter/Dart, `provider` pour l’état et `http` pour les requêtes. Réutiliser les services de `lib/services/`, providers, widgets et traductions existants.
- L’URL partagée HTTP/WebSocket se trouve dans `lib/utils/api_config.dart`.
- Vidéo et voix : P2P WebRTC. Ne pas réintroduire Agora sur la foi des anciennes notes.
- Réutiliser `AppTheme` et `lib/widgets/design_system.dart`. La police actuelle est Manrope ; les anciennes maquettes ne sont pas une raison de revenir à un autre système visuel.
- Privilégier les modifications ciblées ; ne pas ajouter de package sans accord, sauf si la demande ou un accord de session couvre déjà cet ajout. Éviter les refontes annexes.

## Invariants produit du scoring

- Lire [les règles produit IA](../docs/ai-context/notes/mobile/ai-scoring-product-rules.md) avant de modifier scoring, caméra ou performances. Ne pas proposer de désactiver/dégrader l’IA pour résoudre la chauffe ; le motion gating a été rejeté.
- Préserver les portes de démarrage des modes qui exigent caméra et IA. Cela n’interdit pas les entraînements sans caméra prévus par le produit.
- La correction manuelle reste accessible : grille de nombres, choix simple/double/triple, raté et bulls ; un appui soumet et ferme. Ne pas remplacer cette correction par une cible interactive avec bouton Valider ou par un effacement/re-lancer.
- Préserver l’émission unique des fléchettes, la déduplication et l’acquittement serveur. Lire les notes concernées avant de simplifier un compteur ou un reset.
- Le modèle, son layout et son délégué se choisissent ensemble dans `ModelSelector`. Vérifier le code courant : les notes t223/t225/v7/v10 décrivent des étapes antérieures.

## Vérification

- Après une modification du code Dart, lancer `flutter analyze` et résoudre les nouveaux warnings/errors ; distinguer les infos ou problèmes préexistants. Exécuter les tests pertinents pour le changement.
- Pour les widget tests, attendre le chargement asynchrone des traductions et vérifier que le widget testé existe vraiment ; la police Ahem n’est pas une mesure fidèle du rendu sur téléphone. Voir [les pièges des widget tests](../docs/ai-context/notes/root/flutter-widget-test-gotchas.md).
- Lucas préfère effectuer lui-même les tests interactifs du web/PWA : fournir les étapes et résultats attendus ; compilation, analyse et tests automatisés hors navigateur restent possibles. Une demande explicite de la session peut remplacer cette préférence.
- Distinguer vérification statique, test automatisé et essai sur appareil. Ne pas annoncer une validation iPhone/Android sans l’avoir réalisée.

## Points sensibles

Consulter selon le sujet : [dispose différé](../docs/ai-context/notes/root/deferred-dispose-gotcha.md), [audio WebRTC et sons](../docs/ai-context/notes/root/match-audio-routing-speakerphone.md), [confirmation avec anneau entier](../docs/ai-context/notes/root/auto-confirm-whole-ring-gate.md), [livraison des fléchettes](../docs/ai-context/notes/root/dart-delivery-protocol.md). Le reste est dans [l’index](../docs/ai-context/INDEX.md).
