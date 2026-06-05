# Switch Audio Écran / Casque — guide rapide

Un script qui, en une touche : **change la sortie audio par défaut**, **déplace toutes les applis déjà ouvertes** vers le bon périphérique, puis affiche une **animation rouge façon AMD** en bas à gauche (remontée d'environ 20 % depuis le bas). L'action (la bascule) est faite **en priorité**, l'animation se lance **après**.

## 1. Installation (2 minutes)

1. Mets ces fichiers dans un dossier, par ex. `C:\Tools\AudioSwitch\` :
   - `audio-switch.ps1`
   - `Ecran.vbs`
   - `Casque.vbs`
2. Télécharge **SoundVolumeCommandLine (svcl.exe)** de NirSoft :
   https://www.nirsoft.net/utils/sound_volume_command_line.html
   Dézippe-le et place **`svcl.exe` dans le même dossier** que le script.

C'est tout. Pas besoin des droits administrateur.

## 2. Vérifier les noms de périphériques

Les noms sont déjà pré-réglés (`VG34VQL3A` pour l'écran, `BlackShark` pour le casque). Pour vérifier, ouvre un PowerShell dans le dossier et lance :

```powershell
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 list
```

Ça affiche tous les périphériques de sortie + les applis actives. Si un nom ne correspond pas, ouvre `audio-switch.ps1` et ajuste les deux lignes du bloc **CONFIG** en haut :

```powershell
$FragmentEcran  = 'VG34VQL3A'
$FragmentCasque = 'BlackShark'
```

Mets juste un bout de nom **unique** à chaque appareil (peu importe la casse).

## 3. Tester

```powershell
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 1   # -> Écran
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 2   # -> Casque
```

Le son bascule instantanément, les applis en cours suivent, puis l'animation apparaît. (Les arguments `--1` / `--2` marchent aussi.)

## 4. Brancher au Stream Deck

Ajoute deux boutons avec l'action **« Système » → « Ouvrir »** :

| Bouton | Fichier à ouvrir |
|--------|------------------|
| Écran  | `C:\Tools\AudioSwitch\Ecran.vbs` |
| Casque | `C:\Tools\AudioSwitch\Casque.vbs` |

Les `.vbs` lancent le script **sans aucune fenêtre noire qui clignote**. Tu peux appuyer aussi vite que tu veux.

> Variante `.cmd` si besoin :
> ```bat
> @echo off
> powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0audio-switch.ps1" 1
> ```
> (mets `2` pour le casque). Le `.vbs` reste plus propre car zéro flash.

## 5. L'animation (ce qu'elle fait)

Séquence, en bas à gauche, remontée de ~20 % :

1. Le panneau gris foncé AMD **glisse depuis la gauche**.
2. Une **barre fine rouge** balaie de gauche à droite et **« écrit »** l'icône + le texte (`SORTIE ÉCRAN` / `SORTIE CASQUE` + le nom du périphérique).
3. **Pause ~1,25 s** avec une légère ombre portée.
4. **3 barres rouges** de teintes différentes balaient de droite à gauche, décalées d'environ 20 % chacune (la dernière recouvre toute la zone)…
5. …mais avant que la dernière n'atteigne la moitié, **tout disparaît de gauche à droite**.

## 6. Personnalisation

Tout en haut du script (`audio-switch.ps1`), bloc **CONFIG** :

- `$FragmentEcran` / `$FragmentCasque` — bouts de nom pour reconnaître chaque appareil.
- `$GapLeftPx` — marge depuis le bord gauche de l'écran (défaut `28` px).
- `$BottomPercent` — hauteur depuis le bas (défaut `0.20` = 20 %). Mets `0` pour coller en bas, `0.4` pour plus haut.
- `$CloseMs` — délai avant fermeture de la fenêtre (défaut `2550` ms). À garder ≥ à la durée de l'anim.

Dans la fonction `Show-Toast` (bloc XAML) si tu veux toucher au look :

- **Couleurs** (codes `#AARRGGBB`) : panneau gris `#FF202024`→`#FF141418` ; rouges AMD `#FFFF564D` (clair), `#FFED1C24` (AMD), `#FFA10E13` (foncé) ; barre qui écrit `#FFFF4D45`→`#FFED1C24`.
- **Icônes** : variables `$IconMonitor` et `$IconHeadset` (chemins SVG 24×24).
- **Vitesse / durées** : les `BeginTime` / `Duration` du `<Storyboard>`. La pause de 1,25 s correspond à l'écart entre la fin de l'écriture (~0,52 s) et le départ des barres de sortie (~1,77 s).

## Dépannage

- **Rien ne se passe** : ouvre `audio-switch.log` (créé à côté du script) — il note la cible trouvée, les applis déplacées, et les erreurs.
- **« svcl.exe introuvable »** : `svcl.exe` doit être dans le même dossier que `audio-switch.ps1`.
- **« aucun périphérique ne correspond »** : relance `... list` et corrige les fragments.
- **Une appli têtue ne suit pas** : certaines applis (jeux en mode exclusif, apps qui n'ouvrent le flux audio qu'une fois) ne se laissent re-router qu'au prochain son. Bascule avant de lancer le son, ou coupe/relance le son dans l'appli.

---

### Comment ça marche (vite fait)

`svcl.exe /SetDefault` change la sortie par défaut. Mais Windows ne déplace **pas** les applis déjà ouvertes — c'est pour ça qu'avec EarTrumpet elles restaient collées sur l'ancienne sortie. Le script règle ça : il énumère tous les flux audio actifs (un seul appel `/scomma`), fait `/SetDefault`, puis `/SetAppDefault` par PID sur chaque appli pas déjà sur la bonne sortie. Tout bascule d'un coup, et seulement ensuite l'overlay WPF se charge — comme ça la bascule reste prioritaire et instantanée.
