# Switch Audio Écran / Casque — guide rapide

Un script qui, en une touche : **change la sortie par défaut**, **déplace toutes les applis déjà ouvertes** vers le bon périphérique, et affiche une **animation bleue** en bas à droite (style NVIDIA).

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

Les noms sont déjà pré-réglés d'après ta capture (`VG34VQL3A` pour l'écran, `BlackShark` pour le casque). Pour vérifier, ouvre un PowerShell dans le dossier et lance :

```powershell
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 list
```

Ça affiche tous les périphériques de sortie. Si un nom ne correspond pas, ouvre `audio-switch.ps1` et ajuste les deux lignes du bloc **CONFIG** en haut :

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

Le son bascule instantanément, les applis en cours suivent, et l'animation apparaît.

## 4. Brancher au Stream Deck

Ajoute deux boutons avec l'action **« Système » → « Ouvrir »** :

| Bouton | Fichier à ouvrir |
|--------|------------------|
| Écran  | `C:\Tools\AudioSwitch\Ecran.vbs` |
| Casque | `C:\Tools\AudioSwitch\Casque.vbs` |

Les `.vbs` lancent le script **sans aucune fenêtre noire qui clignote**. Tu peux appuyer aussi vite que tu veux.

> Si tu préfères du `.cmd` (par ex. pour un autre logiciel), un fichier `.cmd` équivalent ressemble à ça :
> ```bat
> @echo off
> powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0audio-switch.ps1" 1
> ```
> (mets `2` pour le casque). Le `.vbs` reste plus propre car zéro flash.

## 5. Personnalisation

Tout est en haut du script (`audio-switch.ps1`) :

- `$ToastDurationMs` — durée de l'animation (défaut 2700 ms).
- Couleurs / icônes de l'animation : dans le bloc XAML de la fonction `Show-Toast` (les codes `#AARRGGBB` ; `48D6FF` = cyan, `2A6CF7` = bleu). Les icônes monitor / casque sont les variables `$IconMonitor` et `$IconHeadset`.

## Dépannage

- **Rien ne se passe** : ouvre `audio-switch.log` (créé à côté du script) — il note la cible trouvée, les applis déplacées, et les erreurs.
- **« svcl.exe introuvable »** : `svcl.exe` doit être dans le même dossier que `audio-switch.ps1`.
- **« aucun périphérique ne correspond »** : relance `... list` et corrige les fragments.
- **Une appli têtue ne suit pas** : certaines applis (jeux en mode exclusif, apps qui ouvrent le flux audio une seule fois) ne se laissent re-router qu'au prochain son. Bascule avant de lancer le son, ou coupe/relance le son dans l'appli.

---

### Comment ça marche (vite fait)

`svcl.exe /SetDefault` change la sortie par défaut. Mais Windows ne déplace **pas** les applis déjà ouvertes — c'est pour ça qu'avec EarTrumpet elles restaient collées sur l'ancienne sortie. Le script règle ça en énumérant tous les flux audio actifs et en faisant `svcl.exe /SetAppDefault` (par PID) sur chacun, donc tout bascule d'un coup.
