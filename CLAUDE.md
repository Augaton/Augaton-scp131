# CLAUDE.md — Développement GLua (Garry's Mod) — orientation SCP-RP

## Contexte
Projet d'addons Garry's Mod en GLua (LuaJIT). Cible principale : serveurs SCP-RP bâtis sur DarkRP. Code destiné à du multijoueur persistant.
Le dépôt est une collection d'une centaine d'addons, en majorité tiers, qu'on durcit et corrige en place. Les modifications restent minimales et suivent la structure de l'addon d'origine.

## Règle absolue : vérifier l'API
- Ne jamais inventer une fonction. Vérifier sur le wiki officiel toute fonction de l'API GMod non triviale ou dont la signature/le realm est incertain : https://wiki.facepunch.com/gmod
- Les fonctions Lua standard (print, ipairs, string.*, math.*…) n'ont pas besoin d'être vérifiées.
- Si une fonction de l'API n'est pas confirmée sur le wiki, le signaler explicitement plutôt que de l'utiliser.
- Indiquer le realm de chaque fonction (Server / Client / Shared / Menu) tel que le wiki le précise.

## Les trois realms — toujours se poser la question "où tourne ce code ?"
- SERVER : logique de jeu, entités, dégâts, inventaire, persistance, requêtes SQL/Data. Jamais d'UI.
- CLIENT : HUD, derma/vgui, rendu, sons locaux, effets visuels. Jamais de logique de jeu autoritaire.
- SHARED : définitions communes (SWEP, SENT, jobs, enums, fonctions utilitaires partagées).
- Erreur classique à éviter : mettre de la logique sensible côté client. Le client ment toujours.

## Écosystème du dépôt — ne pas réinventer ce qui existe
Avant d'écrire un système, vérifier s'il existe déjà ici. La plupart des besoins (UI, mise à l'échelle, config, permissions, radio, mute) sont déjà couverts.

### AugLib (`augaton_lib/`) — bibliothèque maison, utilisée par une vingtaine d'addons
Toute UI nouvelle passe par elle plutôt que par du Derma brut.
- `AugLib.Scale( value )` : mise à l'échelle indexée sur la HAUTEUR d'écran (design 1080p). Ne pas utiliser `ScreenScale` : il part de `ScrW() / 640` et déborde en ultra-large.
- `AugLib.FrameSize( w, h, margin )` : taille de fenêtre mise à l'échelle puis bornée à l'écran.
- `AugLib.Fonts( prefix, spec, onRebuild )` : polices enregistrées sous `"Prefix.Nom"` et reconstruites automatiquement au redimensionnement. `scale = false` pour le 3D2D, dessiné en unités monde.
- `AugLib.OnResize( id, callback )` : un seul hook `OnScreenSizeChanged` pour toute la bibliothèque, avec ordre de rafraîchissement garanti. Ne pas poser son propre hook de redimensionnement.
- `AugLib.UI.*` (`Window`, `Header`, `Row`, `Field`, `Entry`, `Slider`, `Tabs`, `Stats`, `Scroll`, `FlatButton`, `Action`, `Danger`, `Empty`, `Note`, `Blur`, `Anim`, `Cut`) avec `AugLib.UI.Theme` et `AugLib.UI.Sizes` : c'est la charte du serveur, ne pas redéfinir des couleurs ou des marges en dur.
- `AugLib.Cursor.*` (`Begin`, `Hover`, `Pressed`, `Button`, `Reticle`, `End`) : curseur 3D2D pour les écrans posés dans le monde.
- `AugLib.TrackHead` / `SetHeadYaw` / `ResetHead` / `HoldSequence` : animation des NPC.
- `AugLib.Mute` et `AugLib.Voice` (Shared) : couper voix ou chat par job ou par blocker nommé, plutôt qu'un système parallèle.

### config_hub (`config_hub/`)
Registre central des addons configurables. Tout nouvel addon ayant une config se déclare dans `config_hub/lua/config_hub/sh_entries.lua` :
`ConfigHub.Register{ id, name, category, desc, detect, folder, actions, files }` — `detect` est un chemin relatif au search path LUA qui sert à savoir si l'addon est monté, `folder` et `files` sont des chemins FTP. Sans entrée, l'addon est invisible dans le hub.

### guthscp (`guthscp_*`, `hacking_device`)
Framework des modules SCP. Un module est un dossier `lua/guthscp/modules/<nom>/` contenant `main.lua` (métadonnées, `dependencies` versionnées, `requires` mappant chaque fichier vers `guthscp.REALMS.SHARED/SERVER/CLIENT`, et `MODULE.menu.config.form` qui génère la config) puis `shared.lua`, `server.lua`, `client.lua`.
- Les valeurs de config se lisent dans `guthscp.configs.<module>.<id>`. Jamais de constante en dur : ajouter une entrée au `form` de `main.lua`.
- Utilitaires disponibles : `guthscp.player_message( ply, msg )`, `guthscp.is_scp( ply )`, `guthscp.sound.play` / `stop`, `guthscp.players_filter`, `guthscp.helpers.format_message`.
- Une dépendance facultative se déclare `optional:<version>` dans `main.lua`, mais reste à tester à l'usage (`guthscp.modules.<autre> == nil`).

### Autres briques déjà en place
- **SAM** (`gmodadminsuite-*`) : permissions, logs, whitelist de jobs. Voir la section Permissions.
- **lyn** : administration principale. Les commandes vivent dans `lua/lyn/sh_modules/sh_lyn_*.lua` — y ajouter un module plutôt qu'une commande isolée.
- **realistic_radio** : routage de la voix et du `/r` par fréquence, écoutes accordées par origine (`RDOGrantTap`), fichiers de langue `sh_language_fr/en`. Toute nouvelle communication se branche dessus au lieu de monter son propre canal.
- **3d2d-vgui-lib**, **mlib** : à vérifier avant de recoder du 3D2D interactif.

### Ordre de chargement
Les addons sont chargés dans l'ordre alphabétique de leur dossier. Rien qui dépend d'un autre addon ne peut être résolu au moment de l'inclusion : tester la disponibilité (`istable`, `isfunction`) au moment de l'appel, ou attendre `InitPostEntity`.

## Réseau de fichiers et assets (erreur n°1 "marche en solo, pas sur serveur")
- Tout fichier client ou shared doit être envoyé au client via AddCSLuaFile( string file ) (Shared, appelée côté serveur), sinon il n'est jamais reçu. Un loader qui boucle sur file.Find + AddCSLuaFile compte comme conforme.
- Assets (matériaux, sons, modèles) : resource.AddFile( string path ) (Server) / resource.AddWorkshop( string workshopid ) (Server). Un son ou un modèle custom joué sans déclaration est muet ou en ERROR chez tout client qui n'a pas le contenu monté.

## Sécurité réseau (priorité en RP multijoueur)
- Tout message net doit être enregistré via util.AddNetworkString( string str ) (Server) avant usage. Une boucle sur une table de noms compte comme conforme.
- Toute donnée venant d'un client est hostile par défaut. Valider systématiquement côté serveur.
- net.Receive côté serveur : signature (len, ply). Vérifier IsValid(ply) et les permissions AVANT toute action.
- Ne jamais déduire l'identité du joueur depuis les données lues : toujours depuis le ply fourni par le moteur.
- L'ordre et le type des net.Read* doivent correspondre exactement aux net.Write* de l'émetteur.
- Ne jamais faire confiance à un net message pour décider d'une action privilégiée sans recheck serveur.
- Nettoyer/borner les valeurs (nombres, longueurs de chaînes) avant usage. Échapper via sql.SQLStr( string str, boolean bNoQuotes = false ) (Shared/Menu) si interaction SQL directe — elle entoure déjà la valeur de guillemets, ne pas en rajouter.
- Anti-flood : valider ne suffit pas, il faut aussi limiter la fréquence. Tout net.Receive serveur déclenchable par le joueur porte un cooldown par joueur — stocké sur le joueur (ply.MonAddon_NextX) plutôt qu'en table globale, sinon il faut le purger dans PlayerDisconnected. Un message parfaitement valide envoyé 500 fois par seconde reste un déni de service.
- Taille des messages net : 65 533 octets maximum par message. Ne jamais sérialiser une structure de taille non bornée (liste de joueurs, inventaire, historique) : borner explicitement le nombre d'éléments écrits, ou fragmenter. Préférer net.WriteUInt(n, bits) dimensionné au besoin plutôt que net.WriteTable, et n'envoyer que les deltas.
- Entités : ENT:Use(activator, caller, useType, value) (Server) se redéclenche tant que la touche est maintenue. Toujours `if not IsValid(activator) or not activator:IsPlayer() then return end`, puis un cooldown sur self, puis la vérification de job/permission.

Ordre canonique d'un `net.Receive` serveur — validité, fréquence, permission, lecture bornée, contenu :

```lua
net.Receive("MonAddon.Action", function(len, ply)
    if not IsValid(ply) then return end

    if (ply.MonAddon_NextAction or 0) > CurTime() then return end
    ply.MonAddon_NextAction = CurTime() + 1

    if not MonAddon.CanUse(ply) then return end

    local count = math.min(net.ReadUInt(8), 16)
    local id    = math.Clamp(net.ReadUInt(16), 1, #MonAddon.Items)
    local label = string.sub(net.ReadString(), 1, 64)

    ...
end)
```

## Lecture de données compressées / structurées (source des crash serveur les plus courants)
Ces trois patterns ont déjà été trouvés exploitables dans ce dépôt (MQS, MRS, MSD, MCS, zeros_masterchef, kit_system). Les traiter comme des interdits, pas comme des conseils.

- **util.Decompress( string compressedString, number maxSize = nil ) (Shared/Menu) sans maxSize sur une donnée réseau = bombe de décompression.** ~200 octets de LZMA suffisent pour réclamer plusieurs Go de RAM et tuer le serveur. Toujours passer un plafond dimensionné à la charge utile réelle (typiquement 1 Mo, quelques Ko sur un point d'entrée non authentifié). Elle renvoie nil en échec : le tester.
- **net.ReadData( number length ) (Shared) avec une longueur venant du client.** Le wiki ne documente aucun clamp. Toujours : la longueur est un nombre, ≥ 1, ≤ 65533 (taille max d'un message), et ≤ `net.BytesLeft()` (Shared) qui donne ce qui reste réellement à lire. Attention à `net.ReadInt(32)` qui peut être négatif — préférer `net.ReadUInt`.
- **net.ReadTable( boolean sequential = false ) (Shared) côté serveur sur un message client : à proscrire.** Elle lit un nombre d'éléments et une profondeur d'imbrication non bornés. Écrire le format à la main : `net.WriteUInt(count, 8)` puis N champs typés, et re-borner le compteur à la lecture (`math.min(net.ReadUInt(8), N)`).
- **Ce qui sort d'une désérialisation n'est pas une table.** `util.JSONToTable` (Shared/Menu) et `util.Decompress` renvoient nil en échec. Faire `if not istable(data) then return end` avant le premier `data.champ`, sinon un message malformé produit une erreur Lua à chaque envoi.
- **Vérifier la permission AVANT la lecture coûteuse.** Un `net.Receive` qui décompresse puis vérifie le job/grade est exploitable par n'importe qui. L'ordre correct : IsValid(ply) → cooldown → permission → lecture bornée → validation du contenu.
- **Valider le type de chaque champ après désérialisation**, pas seulement sa présence : un `data.time` non numérique passé à `timer.Create` ou un `data.pos` non-Vector passé à une fonction moteur plante le serveur. Noter qu'un Vector ne survit pas tel quel à un aller-retour JSON.

## Conventions de fichiers et nommage
- Préfixes : sv_ (serveur), cl_ (client), sh_ (shared).
- Structure addon :
  - lua/autorun/server/ , lua/autorun/client/ , lua/autorun/sh_*.lua
  - lua/entities/ , lua/weapons/ pour SENT/SWEP
  - addon.json uniquement si l'addon est packagé en .gma ou publié sur le workshop ; les addons montés en dossier dans addons/ n'en ont pas besoin (c'est le cas de la quasi-totalité de ce dépôt).
- Hooks : noms d'identifiant uniques et préfixés par le projet pour éviter les collisions ("MonProjet.OnPlayerSpawn").
- Secrets (webhooks Discord, tokens, clés d'API) : jamais en dur dans un fichier suivi par git. Les isoler dans un fichier de config dédié (`sv_config_secrets.lua`) référencé par le .gitignore, avec un repli neutre si le fichier est absent.

## Performance (serveurs RP = beaucoup de joueurs/entités)
- Éviter le travail lourd dans Think / HUDPaint / Draw (appelés chaque frame/tick).
- Mettre en cache les résultats coûteux (ex: LocalPlayer(), distances, calculs mathématiques complexes).
- Itérer avec player.Iterator() et ents.Iterator() (Shared) plutôt que player.GetAll() / ents.GetAll() : ces dernières sont des fonctions C++ et l'aller-retour Lua→C++ coûte plus que la boucle. Les Iterator servent une table mise en cache côté Lua. Différence sensible dans un hook appelé chaque frame.
- Comparer des distances au carré avec DistToSqr (Shared) contre une constante déjà élevée au carré, jamais Distance : la racine carrée ne sert à rien pour un test de seuil.
- Variables réseau : SetNW*/GetNW* renvoient la valeur à tous les clients toutes les 10 secondes même inchangée ; SetNW2* ne réseaute qu'au changement mais **ne doit pas être utilisé sur une entité Lua (SENT/SWEP)** — les valeurs peuvent s'y mélanger, être renvoyées plusieurs fois ou ne pas être appliquées. Dans les deux cas la mise à jour clientside n'a lieu que si l'entité est dans le PVS du client. Pour une valeur qui change souvent, ou qui ne concerne qu'un joueur, préférer un net message ciblé (net.Send).
- Préférer les timers ou les événements aux boucles répétitives dans les hooks fréquents.
- Nettoyer hooks et timers quand ils ne servent plus (hook.Remove, timer.Remove).
- Attention aux fuites : entités non supprimées (ent:Remove()), références gardées en table globale.

## Framework : DarkRP (SCP-RP)
- Suivre les conventions DarkRP plutôt que de réécrire du générique.
- Argent : ne jamais modifier les fonds à la main. Utiliser ply:addMoney(amount) (Server), ply:canAfford(amount) (Shared). Attention, DarkRP.payPlayer(sender, receiver, amount) (Server) ne valide RIEN — elle enchaîne deux addMoney. Sur tout chemin déclenchable par un joueur, vérifier soi-même IsValid des deux joueurs, isnumber(amount), amount > 0, amount == math.floor(amount), une borne haute, et sender:canAfford(amount).
- Jobs : déclarer via DarkRP.createJob / TEAM_* ; ne pas hardcoder des team IDs en dur. Emplacement canonique : `darkrpmodification/lua/darkrp_customthings/jobs.lua` (et les fichiers voisins pour les shipments, entités, agendas…). Un job qui appartient à un addon peut vivre dans le `lua/darkrp_customthings/` de cet addon, mais nulle part ailleurs.
- Changement de job : ply:changeTeam(team) (Server) renvoie un booléen. Le second argument `force` contourne l'arrestation, les jobbans, les démotions et la whitelist : ne l'utiliser que pour une sanction ou un nettoyage administratif, jamais sur un chemin déclenchable par le joueur.
- Entités/armes/shipments à vendre : DarkRP.createEntity, DarkRP.createShipment, DarkRP.createJob — tous Shared (gamemode/modules/base/sh_createitems.lua). Les déclarer dans un fichier shared envoyé par AddCSLuaFile, sinon le menu F4 est vide côté client. Les globales AddCustomShipment / AddEntity / AddExtraTeam sont de simples alias des mêmes fonctions : les éviter pour ne pas dépendre du scope global, pas parce que la signature diffère.
- Hooks DarkRP : vérifier le realm de chaque hook avant de choisir le fichier. playerGetSalary(ply, amount), canChangeJob(ply, args) et playerWalletChanged(ply, amount, oldAmount) sont Server ; canBuyPistol(ply, shipment) est Shared — appelé côté client par le menu F4 et côté serveur à l'achat, donc à déclarer en sh_, sinon soit l'affichage ment, soit la restriction n'est pas appliquée.
- Attention : la mort n'a pas de hook DarkRP — c'est GM:PlayerDeath(victim, inflictor, attacker) (Server), ou le champ PlayerDeath d'une table de job.
- Notifications : DarkRP.notify(ply, type, length, text) (Server) côté joueur concerné.
- Config : passer par les fichiers de config DarkRP existants quand ils couvrent le besoin, ne pas créer un système parallèle.
- Vérifier chaque fonction DarkRP sur sa doc : https://darkrp.miraheze.org puis recouper avec le wiki GMod pour l'API de base.

## Permissions et persistance
- Le serveur utilise SAM. Ne pas contrôler une action privilégiée avec ply:IsAdmin() / ply:IsSuperAdmin() : déclarer la permission une fois côté serveur, la tester avec ply:HasPermission, et garder l'appel derrière un test d'existence pour ne pas casser si SAM n'est pas monté. SAM n'est pas documenté sur le wiki : l'enregistrement passe par pcall.

```lua
local PERM, RANG = "monaddon_manage", "admin"

local function RegisterPermission()
    if not sam or not sam.permissions or not sam.permissions.add then return end

    pcall(sam.permissions.add, PERM, "Mon Addon", RANG)
end

-- Sur Initialize si le fichier est chargé au démarrage ; en appel direct suivi
-- d'un timer.Simple(0) si l'addon se charge lui-même dans un timer, auquel cas
-- Initialize est déjà passé et le hook ne serait jamais appelé.
hook.Add("Initialize", "MonAddon.SamPermission", RegisterPermission)

function MonAddon.CanUse(ply)
    if not IsValid(ply) then return true end -- console serveur
    if sam and ply.HasPermission then return ply:HasPermission(PERM) == true end

    return ply:IsSuperAdmin()
end
```

- sql.Query (Shared/Menu) renvoie une table de lignes, nil sur succès sans résultat, ou false sur erreur. Toujours distinguer false de nil — sinon une table absente passe pour une base vide. Journaliser sql.LastError() sur false.
- Choisir explicitement le support : sql.* pour les données par joueur qui doivent survivre au changement de map, file.Write dans data/ pour la config et les petits dumps, et les API DarkRP quand elles couvrent déjà le besoin.

## Style de code attendu
- Tout est en français : commentaires, notifications joueur, libellés d'interface, messages de commit (`[Fix]`, `[QOL]`, `[Add]`, `[Remove]`, `[MAJ]`, `[Rework]` suivis d'une phrase courte).
- Commenter le POURQUOI, jamais le comment. Les fichiers non triviaux portent un bandeau d'en-tête qui pose l'intention, les contraintes et les pièges (ordre de chargement, valeur qui ne survit pas au réseau, raison d'un cooldown, pourquoi on ne réimplémente pas un système voisin). Un commentaire qui paraphrase la ligne suivante est du bruit ; un commentaire qui explique pourquoi le code ne fait PAS la chose évidente est celui qu'on garde.
- Lisible et simple, pas de sur-ingénierie. Pas de couche d'abstraction pour un seul appelant.
- local par défaut pour les variables et les fonctions internes ; ne pas polluer le scope global.
- Suivre l'indentation du fichier édité : 4 espaces sur le code maison, tabulations sur l'upstream guthscp. Ne jamais reformater un fichier tiers en entier, le diff deviendrait illisible.

## Avant de livrer du code
- Realm correct ? Fichiers client AddCSLuaFile() ? net string enregistrée ? Assets custom déclarés en resource.* ?
- Validation serveur en place (IsValid + permissions) ? API vérifiée sur le wiki ?
- Chaque net.Receive serveur touché : cooldown par joueur ? permission testée avant la lecture ? toute longueur venant du client bornée ? util.Decompress avec maxSize ? résultat vérifié avec istable() avant indexation ?
- Rien de réinventé : AugLib pour l'UI et la mise à l'échelle, guthscp.configs pour un module SCP, realistic_radio pour une communication, SAM pour une permission ? Nouvel addon configurable déclaré dans config_hub ?
- Pas de hook/timer orphelin ? Pas de secret en dur ? Nommage cohérent avec le framework du projet ?
