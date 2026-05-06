# Handoff - Miroir enchante

## Resume rapide

- App iOS UIKit + ARKit/SceneKit: miroir maquillage local, sans backend.
- Features: looks complets, lipstick, Face > Blush/Glow/Contour, Eyes, bug report share sheet, AR auto-framing, demo Debug.
- Release: demo/hair/debug caches UI caches en release; demo actif seulement `#if DEBUG`.
- UI principale: `Looks / Levres / Teint / Yeux` en bas du panneau. Teint a sous-segment `Blush / Eclat / Sculpt`.
- Dernier build verifie: Debug iphonesimulator `BUILD SUCCEEDED` le 2026-05-05.
- Work non commit important: plusieurs fixes AR/demo maquillage + HANDOFF.

## Fichiers importants

- `Miroir enchanté/FaceMakeupViewController.swift`
  - Controleur principal. Flux: UIKit controls -> `MakeupSettingsState` -> `MakeupRendering`.
  - `makeupRenderers`: `[faceRenderer, demoHeadRenderer]` en Debug, `[faceRenderer]` en Release.
  - Bouton bug report en bas a droite du panneau.
  - Bouton AR auto-framing pres bord gauche, ancien icon `viewfinder` conserve + petit badge `A`.
  - Demo tilt: gain baisse a `0.95`, smoothing `0.90/0.10`.

- `Miroir enchanté/MakeupControlPanelView.swift`
  - Panneau UIKit. Onglets principaux en bas.
  - Face/Teint sub-tabs: Blush / Glow(Eclat) / Contour(Sculpt).
  - Miniatures looks dessinees en UIKit (`MakeupZoneFaceIconView`), pas de SVG actif.
  - Lipstick intensity slider min baisse a `0.1`.

- `Miroir enchanté/FaceRenderer.swift`
  - Rendu AR. Reuse geometry/nodes/materials.
  - `renderer(_:didUpdate:for:)`: update `ARSCNFaceGeometry`, overlay meshes, pending makeup, FPS debug.
  - Non commit: `.fullFace` update aussi `lipMesh`, `cheekMesh`, `eyeshadowMesh`; overlays lips/cheeks/eyes/glow/contour visibles si makeup enabled.

- `Miroir enchanté/DemoHeadRenderer.swift`
  - Rendu demo Debug. Charge assets OBJ: head, hair, lips, cheeks, eyelids, eyes.
  - Demo supporte lips/blush/eyes. Glow/Contour demo ne rendent rien pour l'instant.
  - Non commit: rotation max demo baisse `135 deg` -> `85 deg`.
  - Important: overlays demo Glow/Contour ajoutes puis retires car rectangles/plans visibles devant tete.

- `Miroir enchanté/MakeupSettingsState.swift`
  - Source de verite persistante UserDefaults.
  - Non commit: lipstick intensity clamp `0.1...1.0`; opacite/couleur lips demo plus sensibles; fini pilote `glossIntensity`.

- `Miroir enchanté/MakeupMaterialFactory.swift`
  - Materials SceneKit. Ne pas recreer dans boucle frame.
  - Non commit:
    - lipstick utilise `settings.glossIntensity` au lieu de `specularIntensity`.
    - AR eyeshadow booste, mais utilisateur trouve encore trop fort.
  - Pour baisser AR eyes: `configureAREyeshadowMaterial(...)`.

- `Miroir enchanté/AREyeshadowMeshGeometry.swift`
  - Mesh/mask AR eyeshadow.
  - Non commit: alpha/couleur AR eyes boostes. Si AR eyes trop forts, baisser aussi ici dans `updateMask(settings:)`.

- `Miroir enchanté/GlowRenderer.swift`, `ContourRenderer.swift`
  - AR overlay nodes crees une fois, update params seulement.
  - Non commit: opacity boostee pour rendre Eclat/Sculpt visibles en AR.

- `Miroir enchanté/MakeupTextureCache.swift`
  - Cache textures procedural: lip noise, blush/eye/glow/contour gradients.

- `Miroir enchanté/BugReportPresenter.swift`
  - Screenshot + `UIActivityViewController`, support email dans texte.

## Etat Git recent

Commits recents:

- `27720f1 Polish auto framing and look previews`
- `c438bcb Move makeup category tabs to bottom`
- `aeeae02 Add drawn makeup look previews`
- `58f45ac Polish bug report and look localization`
- `a1f9b23 Set bug report support email`
- `05f02cc Localize bug report share sheet`
- `e430862 Add anonymous bug report share sheet`
- `ea7bae8 Localize makeup category labels`

Dirty tree verifie le 2026-05-05:

- Modified:
  - `HANDOFF.md`
  - `Miroir enchanté.xcodeproj/project.pbxproj`
  - `Miroir enchanté.xcodeproj/xcuserdata/francois.xcuserdatad/xcschemes/xcschememanagement.plist`
  - `Miroir enchanté/AREyeshadowMeshGeometry.swift`
  - `Miroir enchanté/ContourRenderer.swift`
  - `Miroir enchanté/DemoHeadRenderer.swift`
  - `Miroir enchanté/FaceMakeupViewController.swift`
  - `Miroir enchanté/FaceRenderer.swift`
  - `Miroir enchanté/GlowRenderer.swift`
  - `Miroir enchanté/MakeupControlPanelView.swift`
  - `Miroir enchanté/MakeupMaterialFactory.swift`
  - `Miroir enchanté/MakeupSettingsState.swift`
- Untracked:
  - `.gitignore`
  - `Miroir enchanté.xcodeproj/xcshareddata/xcschemes/Miroir enchanté (release).xcscheme`

## Build/Test

Commande qui marche:

```sh
set -o pipefail; xcodebuild -project 'Miroir enchanté.xcodeproj' -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build 2>&1 | tee /tmp/miroir_debug.log | rg -n "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

Dernier resultat verifie le 2026-05-05: `BUILD SUCCEEDED`.

Warnings connus:

- `ONLY_ACTIVE_ARCH=YES requested with multiple ARCHS...`
- `Metadata extraction skipped. No AppIntents.framework dependency found.`

## Localisations

- Langues projet: `ar`, `de`, `en`, `es`, `fa`, `fr`, `ja`, `ko`, `pt`, `ru`, `zh-Hans`.
- Fichiers: `Miroir enchanté/<lang>.lproj/Localizable.strings` et `InfoPlist.strings`.
- Ne pas toucher localisations hors demande precise.

## UX/Comportement actuel

- Onglets bas: `Looks / Levres / Teint / Yeux`.
- Teint: sous-tabs `Blush / Eclat / Sculpt`.
- Looks: miniatures croquis UIKit + swatches.
- Bug report: bouton icone seul, en bas pour eviter doigt dans screenshot.
- Auto-framing: bouton gauche, icon viewfinder + petit `A`.
- `Avant / Apres`: bouton centre au-dessus panneau.
- Demo: pas Eclat/Sculpt pour l'instant; tentative overlays retiree car artefacts devant tete.

## Points d'attention

- Ne pas recreer geometry/nodes/textures/materials dans `renderer(_:didUpdate:for:)`.
- AR fullFace: garder overlays visibles; sinon lips/blush/eyes/glow/contour semblent ne rien changer.
- AR eyeshadow trop fort actuellement selon utilisateur. Reglage a faire dans:
  - `MakeupMaterialFactory.configureAREyeshadowMaterial`
  - `AREyeshadowMeshGeometry.updateMask(settings:)`
- Demo lipstick:
  - intensite maintenant min `0.1`
  - fini doit utiliser `glossIntensity`.
- Demo tilt: sensibilite reduite. Ajuster `amplifiedTilt` et `demoRotationLimit` si encore trop fort.
- `.svg`: aucun SVG dans `Assets.xcassets` selon derniere verification.
- Worktree contient fichiers Xcode/userdata non lies; ne pas stage par accident.
- Repo path avec accent: `/Volumes/XTRA/Dev/Miroir enchanté`.

## Prochaines pistes

1. Baisser AR eyeshadow car utilisateur dit encore trop fort.
2. Tester sur iPhone TrueDepth: fullFace lips/blush/eyes/glow/contour.
3. Tester demo: lips intensity, finish Mat/Satine/Brillant, tilt moins sensible.
4. Commit seulement fichiers utiles; eviter Xcode userdata sauf decision explicite.
