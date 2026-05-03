# Handoff - Miroir enchante

## Resume rapide

- Projet iOS UIKit + ARKit/SceneKit: prototype miroir maquillage.
- Deux modes:
  - AR: `ARSCNView`, `ARFaceTrackingConfiguration`, rendu via `FaceRenderer`.
  - Demo: `SCNView`, tete/cheveux/yeux/levres depuis assets locaux, rendu via `DemoHeadRenderer`.
- Etat courant: refactor UI/state/rendering en cours mais compile. `FaceMakeupViewController` ne construit plus le panneau controle ligne par ligne.
- Decisions recentes: reglages maquillage centralises dans `MakeupSettingsState`; panneau UI extrait dans `MakeupControlPanelView`; contrat rendu commun ajoute via `MakeupRendering`; geometries AR sorties de `FaceRenderer`.

## Fichiers importants

- `Miroir enchanté/SceneDelegate.swift`
  - Point entree UI. Installe `FaceMakeupViewController`.
- `Miroir enchanté/FaceMakeupViewController.swift`
  - Controleur principal. Gere cycle AR/demo, boutons flottants, actions UI, persistence via `MakeupSettingsState`, appels renderers.
- `Miroir enchanté/MakeupControlPanelView.swift`
  - Nouveau panneau controle: tabs lipstick/blush/hair/debug, sliders, switches, presets blush, collection lipstick.
  - Contient `MakeupLipstickSnapFlowLayout`, `MakeupLipstickPresetCell`, `MakeupLipstickIconView`.
- `Miroir enchanté/MakeupSettingsState.swift`
  - Nouveau state central: load/persist `UserDefaults`, indices presets, lipstick finish, blush, hair placement/color, switches head/hair, AR auto framing.
- `Miroir enchanté/CosmeticTheme.swift`
  - Nouveau theme couleur commun.
- `Miroir enchanté/MakeupUIExtensions.swift`
  - Nouveau helper couleur pour icone lipstick (`withBrightnessMultiplier`).
- `Miroir enchanté/MakeupRendering.swift`
  - Nouveau protocole commun AR/Demo: lipstick, blush, makeup enabled.
- `Miroir enchanté/FaceRenderer.swift`
  - Rendu AR face makeup. Orchestre ARKit + SceneKit; geometries AR extraites.
- `Miroir enchanté/ARLipMeshGeometry.swift`
  - Geometrie AR des levres + debug points.
- `Miroir enchanté/ARCheekMeshGeometry.swift`
  - Geometrie AR joues + masque blush vertex colors.
- `Miroir enchanté/DemoHeadRenderer.swift`
  - Rendu demo SceneKit, cheveux, yeux, tete, inclinaison, couleurs cheveux.
- `Miroir enchanté/MakeupMaterialFactory.swift`
  - Materiaux SceneKit communs maquillage.
- `Miroir enchanté/ModelAssets/`
  - Assets bundle OBJ/MTL/textures utilises par app.
- `Miroir enchanté/*.lproj/Localizable.strings`
  - Localisation UI.

## Etat Git recent

Derniers commits verifies:

- `eaf223c Refactor demo asset loading`
- `eff4132 Persist makeup settings`
- `a3ad15e Add AR auto framing toggle and refine blush mask`
- `0ecce34 Add blush controls and refine makeup UI`
- `96f2a14 Add app icon assets`
- `fc54e57 Add lipstick preset carousel`
- `eeeb90a Stabilize demo hair rendering`
- `e743332 Refactor makeup controls`

Dirty tree actuel, non commit:

- Modifies:
  - `Miroir enchanté/DemoHeadRenderer.swift`
  - `Miroir enchanté/FaceMakeupViewController.swift`
  - `Miroir enchanté/FaceRenderer.swift`
  - `Miroir enchanté/ModelAssets/Lower Lip.mtl`
  - `Miroir enchanté/ModelAssets/Lower Lip.obj`
- Non suivis:
  - `Miroir enchanté/ARCheekMeshGeometry.swift`
  - `Miroir enchanté/ARLipMeshGeometry.swift`
  - `Miroir enchanté/MakeupRendering.swift`
  - `assets/complet.blend`
  - `assets/complet.blend1`

Attention: `Lower Lip.*` et `assets/complet.blend*` existaient comme changements avant ce handoff. Ne pas revert sans demande explicite.

## Architecture actuelle

- `FaceMakeupViewController`:
  - Possede `sceneView`, `demoSceneView`, `faceRenderer`, `demoHeadRenderer`, boutons flottants et `controlPanel`.
  - Charge `settingsState = MakeupSettingsState.load()`.
  - Expose computed properties vers `settingsState` pour limiter changement comportemental.
  - Configure `MakeupControlPanelView`, branche targets UIKit, reste `UICollectionViewDataSource/Delegate` pour lipstick presets.
- `MakeupControlPanelView`:
  - Construit UI panneau et gere visibilite tabs selon mode demo/AR.
  - En AR: tabs visibles `lipstick`, `blush`.
  - En demo: tabs visibles `lipstick`, `blush`, `hair`, `debug`.
- `MakeupSettingsState`:
  - Source de verite persistante.
  - `rebuildLipstickSettings()` applique preset + intensite + finish.
  - `rebuildBlushSettings()` applique preset + sliders blush.
- `MakeupRendering`:
  - `FaceRenderer` et `DemoHeadRenderer` conformes.
  - `FaceMakeupViewController` propage lipstick/blush/makeup-enabled via `makeupRenderers`.
- `FaceRenderer`:
  - Ne contient plus `LipMeshGeometry` / `CheekMeshGeometry`.
  - Reste centre sur callbacks ARKit, nodes, modes rendu, orchestration materiaux.
- `DemoHeadRenderer`:
  - A un helper local `clampedCGFloat` car les extensions `CGFloat.clamped` existantes sont `private` dans autres fichiers.

## Build/Test

Commande verifiee apres refactor:

```sh
xcodebuild -project 'Miroir enchanté.xcodeproj' -scheme 'Miroir enchanté' -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Dernier resultat: `BUILD SUCCEEDED`.

Commande avec `-destination 'generic/platform=iOS Simulator'` a rencontre problemes CoreSimulator locaux (`simdiskimaged`), puis build OK avec `-sdk iphonesimulator`.

## Points d'attention

- Ne pas ajouter une extension globale `CGFloat.clamped(to:)`: deja presente comme `private extension` dans `ARCheekMeshGeometry.swift` et `MakeupMaterialFactory.swift`; redeclaration casse build.
- Les nouveaux fichiers Swift sont deja inclus par projet Xcode via groupe synchronized/file-system sync; build les compile.
- UI refactor vise comportement identique. A verifier sur device/sim:
  - persistance sliders/presets;
  - tabs AR vs demo;
  - selection lipstick carousel;
  - switches hide head/hair en demo;
  - bouton Avant / Apres;
  - auto framing AR.
- Path repo contient accent: `/Volumes/XTRA/Dev/Miroir enchanté`.
- Pas de tests unitaires connus. Validation actuelle = build Xcode.

## Prochaines pistes

1. Tester app visuellement sur simulateur/device: panneau, tabs, sliders, presets.
2. Decouper `DemoHeadRenderer` par responsabilite (`Hair`, `Eyes`, `Lips`, `Blush`, `Fallback`) avec prudence: beaucoup de membres sont `private`.
3. Si OK, considerer supprimer computed-property bridge dans `FaceMakeupViewController` et parler directement a `settingsState` plus explicitement.
4. Ajouter petits tests purs pour `MakeupSettingsState` si target tests creee plus tard.
5. Nettoyer/clarifier changements assets `Lower Lip.*` seulement apres confirmation utilisateur.
