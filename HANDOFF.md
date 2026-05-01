# Handoff - Miroir enchante

## Resume rapide

- Projet iOS UIKit + ARKit/SceneKit pour un prototype de miroir maquillage.
- Deux modes principaux:
  - AR: `ARSCNView` + `ARFaceTrackingConfiguration`.
  - Demo: scene SceneKit locale avec tete OBJ, levres OBJ, cheveux OBJ, yeux OBJ.
- Objectif actuel: reparer le rendu Demo des cheveux et des yeux avec textures locales.
- Dernier etat visuel rapporte par l'utilisateur:
  - Cheveux: rendu casse / parfois invisibles / parfois en fallback gris-noir, transparence et orientation ont ete instables.
  - Yeux: restent blancs; `eyeColor.jpg`, `eyeSpecular.jpg`, `eyeBump.jpg` ne semblent pas produire un iris visible.
  - L'utilisateur veut revenir a l'utilisation des textures PNG/JPG pour cheveux et yeux, y compris normal/bump.

## Fichiers importants

- `Miroir enchante/DemoHeadRenderer.swift`
  - Charge et configure la scene Demo.
  - Charge les assets OBJ directs: tete, levres, cheveux, yeux.
  - Contient les materiaux cheveux/yeux et les controles de couleur cheveux.
- `Miroir enchante/FaceMakeupViewController.swift`
  - UI UIKit, sliders rouge/opacity/brillance/couleur.
  - Ajoute les sliders cheveux `Teinte` / `Force`.
  - Ajoute le switch `Yeux seuls`.
  - Lie l'inclinometre/CoreMotion a la rotation Demo.
- `Miroir enchante/MakeupMaterialFactory.swift`
  - Materiaux partages maquillage / peau / cheveux basiques.
- `Miroir enchante/ModelAssets/`
  - `Female head.obj` + `.mtl`
  - `Female hair.obj` + `.mtl`
  - `left eyes.obj` + `left eyes.mtl` (cornee `aiStandard3` + iris `Eyes`)
  - `right eyes.obj` + `right eyes.mtl` (cornee `aiStandard3.001` + iris `Eyes.001`)
  - `Upper Lip.obj`, `Lower Lip.obj`
  - `textures hair/hair_d7.png`
  - `textures hair/hair_n.png`
  - `textures hair/flatspec.tga.png`
  - `textures eyes/eyeColor.jpg`
  - `textures eyes/eyeSpecular.jpg`
  - `textures eyes/eyeBump.jpg`

## Etat Git recent

Derniers commits:

- `7544131 Add demo hair assets and color controls`
- `38faf26 Add localized demo makeup hair mode`
- `0b06fc3 Add ARKit makeup prototype`
- `5f1990f Initial Commit`

Etat de travail actuel, non commite:

- Modifies:
  - `Miroir enchante/DemoHeadRenderer.swift`
  - `Miroir enchante/FaceMakeupViewController.swift`
  - `Miroir enchante/ModelAssets/Female hair.obj`
  - `Miroir enchante/ModelAssets/Female hair.mtl`
  - `Miroir enchante/ModelAssets/Female head.obj`
  - `Miroir enchante/ModelAssets/eyes.obj`
  - `Miroir enchante/ModelAssets/eyes.mtl`
  - fichiers `Localizable.strings` dans plusieurs langues
- Non suivi:
  - `assets/` avec anciens essais FBX/GLB/OBJ/Blender.

Ne pas revert les OBJ/MTL sans demander: l'utilisateur les modifie depuis Blender.

## Build/Test

Commande de build qui a reussi apres les derniers changements Swift:

```sh
xcodebuild -project "Miroir enchanté.xcodeproj" -scheme "Miroir enchanté" -destination "generic/platform=iOS" -derivedDataPath /private/tmp/MiroirEnchanteBuild CODE_SIGNING_ALLOWED=NO build
```

Dernier resultat connu: `BUILD SUCCEEDED`.

## Architecture Demo actuelle

- `DemoHeadRenderer` contient:
  - `modelContainerNode`: racine qui tourne avec CoreMotion.
  - `eyeRootNode`: yeux charges depuis `eyes.obj`.
  - `hairRootNode`: cheveux charges depuis `Female hair.obj`.
  - `fallbackLipRootNode`: levres compagnon.
- `DemoHairStyle` a actuellement `.none` et `.femaleHair`.
- Les cheveux et yeux sont charges via un parseur OBJ maison `loadOBJNodes(...)`, pas via SceneKit directement, pour filtrer les sous-meshes par materiau.
- Logs attendus sur device:
  - `Loaded companion lip asset: Upper Lip.obj`
  - `Loaded companion lip asset: Lower Lip.obj`
  - `Loaded demo eye OBJ directly: eyes.obj`
  - `Loaded demo hair OBJ directly: Female hair.obj`
  - `Demo eye material ... eyeColor.jpg loaded, eyeSpecular.jpg loaded, eyeBump/eyesBump.jpg loaded`

## Assets / noms de materiaux constates

`Female hair.obj` actuel:

- `mtllib Female hair.mtl`
- `o Generic_Item_new_mesh`
- `usemtl hair.001`

`eyes.obj` actuel:

- `mtllib eyes.mtl`
- `o Eye_1_R` / `usemtl aiStandard3`
- `o Eye_2_R` / `usemtl Eyes`
- `o Eye_2_R.001` / `usemtl Eyes.001`
- `o Eye_1_R.001` / `usemtl aiStandard3.001`

`Female hair.mtl` ne reference pas les textures par `map_Kd`/`map_Bump`; le code les applique manuellement.

`eyes.mtl` ne reference pas non plus les JPG; le code les applique manuellement.

## Points sensibles dans le code

- Cheveux:
  - `DemoHeadRenderer.preparedHairMaterial(...)`, autour de la zone qui charge `hair_d7.png` et `hair_n.png`.
  - Mise a jour 2026-05-01: la transparence n'utilise plus `.rgbZero`. Les pixels fonces sont conserves, l'alpha vient de `hair_d7.png` via `transparent.contents`, en `transparencyMode = .aOne`.
  - `applyHairColor(...)` garde `diffuse.intensity = 1.0` et n'applique plus qu'un `multiply` faible, pour eviter de noircir totalement la texture des cheveux.
  - Un log debut applique liste presence/absence des trois textures: `Demo hair material ...`.
  - Si les cheveux apparaissent encore trop sombres avec `Force` au max, baisser le facteur `0.10 + strength * 0.55` dans `applyHairColor`. Si les cheveux apparaissent comme un calque opaque (perte de l'alpha des pointes), verifier que `hair_d7.png` a bien un canal alpha; sinon retomber sur le 1ere passe `.rgbZero` mais avec un blend doux.
- Yeux:
  - `makeTexturedEyeMaterial(named:)` est passe en `lightingModel = .blinn` (auparavant `.physicallyBased`). Le PBR avec spec blanche donnait une boule blanche de face: c'etait le symptome rapporte.
  - Specular intensity reduit a 0.12, normal intensity reduit a 0.15, shininess a 0.25.
  - Logs detailles a `loadEyeOBJNode(...)`: pour chaque mesh charge directement, on imprime `material`, `tris`, `verts`, `uv`, `diffuseImage`. Si `uv` est 0 ou si `diffuseImage` est `false`, c'est la premiere chose a regarder.
  - Le loader direct continue de filtrer `Eyes` / `Eyes.001` et d'ignorer `aiStandard3*` (cornee). Les iris sont bien dans `Eyes`/`Eyes.001` d'apres le fichier OBJ.
- Rotation:
  - `updateInspectionTilt(horizontal:)` utilise `demoRotationLimit = 135 deg`.
  - `FaceMakeupViewController` amplifie `motion.gravity.x * 1.75`.
  - L'utilisateur voulait pouvoir voir derriere avec l'inclinometre.
- Visibilite tete/cheveux:
  - L'ancien switch `control.eyes_only` est remplace par deux switches independants `control.hide_head` et `control.hide_hair`.
  - Cote renderer: `setHeadHidden(_:)` et `setHairHidden(_:)`. `applyHeadAndHairVisibility` lit `isHeadHidden` et `isHairHidden` separement.
  - Les yeux et les levres restent visibles meme quand la tete est masquee.

## Symptomes actuels a reprendre

- Cheveux:
  - Avant, le fallback/faux materiau donnait des plaques grises/noires.
  - Avec les textures, l'utilisateur a vu les cheveux trop transparents, puis blancs, puis plus de cheveux.
  - Il faut prioriser l'alpha et la texture `hair_d7.png`, puis seulement ensuite la teinte.
  - 2026-05-01: changement applique pour utiliser `transparent.contents = hair_d7.png` + `.aOne` au lieu de `.rgbZero`. A confirmer sur device.
- Yeux:
  - Les yeux sont blancs.
  - L'utilisateur soupconne que la texture des yeux n'est pas utilisee ou que les UV ne pointent pas au bon endroit.
  - Les fichiers attendus sont bien sous `ModelAssets/textures eyes/`.
  - 2026-05-01: passage en `lightingModel = .blinn` pour eyeux et baisse spec/normal. Logs detailles (tris/verts/uv/diffuseImage) ajoutes au loader direct. A confirmer sur device.

## Prochaines pistes concretes

1. Ajouter des logs plus explicites a l'application des materiaux:
   - pour chaque materiau cheveux: nom, presence diffuse/normal/specular, mode transparence.
   - pour chaque materiau yeux: nom, nombre de vertices/triangles, presence UV, presence diffuse/specular/normal.
2. Reparer cheveux en premier:
   - retirer `.rgbZero`;
   - utiliser l'alpha de `hair_d7.png` via `transparent.contents`;
   - ne pas multiplier trop fort au depart (`multiply.intensity` faible, ex. 0.25);
   - tester sans `hair_n.png` puis le remettre, car une normal map trop forte peut noircir ou casser le rendu.
3. Reparer yeux:
   - verifier que le parseur OBJ lit bien les `vt` et les assigne aux triangles des meshes `Eyes` / `Eyes.001`;
   - tester temporairement `material.diffuse.contents = eyeColor` avec `lightingModel = .constant` pour separer probleme UV/probleme lighting;
   - si blanc persiste, inspecter `eyeColor.jpg`: les UV des yeux peuvent viser une zone blanche hors iris.
4. Garder le switch `Yeux seuls`; il est utile pour diagnostiquer le placement des yeux sans tete/cheveux.
5. Ne pas s'occuper de localisation maintenant, l'utilisateur a dit que ce serait plus tard.

## Notes pratiques

- Le projet est local uniquement, pas de reseau/API.
- Attention aux chemins avec accent: le repo est `/Volumes/XTRA/Dev/Miroir enchanté`.
- Les assets dans `assets/` sont des essais/source et ne sont pas forcement dans le bundle.
- Les assets reellement utilises par l'app sont sous `Miroir enchante/ModelAssets/`.
- SceneKit sur iOS charge mal FBX/GLB dans ce projet; preferer OBJ/USDZ.
