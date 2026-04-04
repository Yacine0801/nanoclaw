# Guide de depannage NanoClaw

> Derniere mise a jour : mars 2026

Ce guide couvre les problemes les plus frequents rencontres en production.
Pour chaque probleme : symptome, cause, diagnostic et solution etape par etape.

---

## Table des matieres

1. [Docker n'est pas lance](#1-docker-nest-pas-lance)
2. [Agent ne repond pas sur WhatsApp](#2-agent-ne-repond-pas-sur-whatsapp)
3. ["Prompt is too long"](#3-prompt-is-too-long)
4. [Token OAuth Gmail expire](#4-token-oauth-gmail-expire)
5. [Agent ne recoit pas les emails](#5-agent-ne-recoit-pas-les-emails)
6. [Newsletters declenchent l'agent](#6-newsletters-declenchent-lagent)
7. [Google Chat — bot ne repond pas](#7-google-chat--bot-ne-repond-pas)
8. [Google Chat — "unknown email"](#8-google-chat--unknown-email)
9. [Container crash (exit code 137)](#9-container-crash-exit-code-137)
10. [Container crash (exit code 1)](#10-container-crash-exit-code-1)
11. [Port deja utilise (EADDRINUSE)](#11-port-deja-utilise-eaddrinuse)
12. [Credit balance too low](#12-credit-balance-too-low)
13. [Circuit breaker ouvert](#13-circuit-breaker-ouvert)
14. [Botti Voice — pas de son](#14-botti-voice--pas-de-son)
15. [Botti Voice — ne peut pas lire les emails](#15-botti-voice--ne-peut-pas-lire-les-emails)
16. [Dashboard ne s'affiche pas](#16-dashboard-ne-saffiche-pas)
17. [Impossible de push sur GitHub](#17-impossible-de-push-sur-github)
18. [Comment redemarrer un agent](#18-comment-redemarrer-un-agent)
19. [Comment voir les logs](#19-comment-voir-les-logs)
20. [Comment creer un nouvel agent](#20-comment-creer-un-nouvel-agent)

---

## Commandes de reference rapide

```bash
# Etat des services
launchctl list | grep nanoclaw

# Logs d'un agent (dernieres 20 lignes, formate)
tail -20 ~/nanoclaw/logs/nanoclaw.log | jq .

# Health check
curl http://localhost:3001/health

# Metriques
curl http://localhost:3001/metrics

# Containers actifs
docker ps --filter name=nanoclaw

# Redemarrer un agent
launchctl kickstart -k gui/$(id -u)/com.nanoclaw

# Full reload (apres changement de plist)
launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist

# Depense quotidienne
cat ~/nanoclaw/store/daily-spend.json | jq .

# Verifier l'image Docker
docker images nanoclaw-agent
```

---

## 1. Docker n'est pas lance

**Symptome** : NanoClaw crashe au demarrage en boucle. Le log affiche :

```
FATAL: Container runtime failed to start
```

Le processus quitte avec une erreur `Container runtime is required but failed to start`.

**Cause** : NanoClaw execute `docker info` au demarrage (dans `src/container-runtime.ts`).
Si Docker Desktop n'est pas lance ou si le daemon Docker n'est pas accessible, le processus
refuse de demarrer car les agents ne peuvent pas tourner sans conteneurs.

**Diagnostic** :

```bash
# Verifier que Docker repond
docker info

# Verifier que le daemon tourne
docker ps

# Sur macOS, verifier Docker Desktop
open -a Docker
```

**Solution** :

1. Lancer Docker Desktop (macOS) ou demarrer le daemon Docker (Linux) :
   ```bash
   # macOS
   open -a Docker
   # Attendre ~10 secondes que le daemon soit pret

   # Linux
   sudo systemctl start docker
   ```
2. Verifier que `docker info` retourne sans erreur.
3. Redemarrer NanoClaw :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

**Note** : Sur macOS, Docker Desktop doit etre lance *avant* NanoClaw. Ajouter Docker
Desktop aux applications de demarrage dans Preferences Systeme > Ouverture.

---

## 2. Agent ne repond pas sur WhatsApp

**Symptome** : Les messages envoyes sur WhatsApp restent sans reponse. Aucun conteneur
n'est cree (`docker ps` ne montre rien).

**Cause** : Plusieurs causes possibles :
- Session WhatsApp expiree (deconnexion du telephone)
- Prompt trop long (voir probleme #3)
- Solde Anthropic insuffisant (voir probleme #12)
- WhatsApp non installe comme channel (migration vers le fork)

**Diagnostic** :

```bash
# Verifier les logs pour des erreurs de session
tail -100 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("whatsapp|session|auth"; "i"))'

# Verifier que le channel est enregistre
curl -s http://localhost:3001/health | jq .channels

# Verifier les conteneurs
docker ps --filter name=nanoclaw

# Verifier la depense quotidienne
cat ~/nanoclaw/store/daily-spend.json | jq .
```

**Solution** :

1. **Session expiree** : Re-scanner le QR code ou re-jumeler le telephone :
   ```bash
   # Regarder les logs pour l'URL de jumelage
   tail -f ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("qr|pair"; "i"))'
   ```
   Redemarrer l'agent et suivre les instructions de jumelage dans les logs.

2. **WhatsApp non installe (apres mise a jour)** : WhatsApp est desormais un fork
   separe. L'installer :
   ```bash
   git remote add whatsapp https://github.com/qwibitai/nanoclaw-whatsapp.git
   git fetch whatsapp main
   git merge whatsapp/main || {
     git checkout --theirs package-lock.json
     git add package-lock.json
     git merge --continue
   }
   npm run build
   ```

3. **Solde insuffisant** : Voir [probleme #12](#12-credit-balance-too-low).

---

## 3. "Prompt is too long"

**Symptome** : L'agent repond avec une erreur `Prompt is too long` ou
`prompt_too_long` dans les logs. Les conteneurs demarrent mais echouent immediatement.

**Cause** : La session Claude (historique de conversation) est devenue trop volumineuse.
Chaque groupe maintient un dossier de session dans `data/sessions/`. Au fil du temps,
l'historique accumule trop de tokens.

**Diagnostic** :

```bash
# Taille des sessions par groupe
du -sh ~/nanoclaw/data/sessions/*/

# Verifier le dossier de session le plus gros
du -sh ~/nanoclaw/data/sessions/*/.claude/ 2>/dev/null | sort -hr | head -5
```

**Solution** :

1. **Purger la session d'un groupe** :
   ```bash
   # Identifier le groupe problematique
   GROUP="whatsapp_main"

   # Sauvegarder avant suppression
   cp -r ~/nanoclaw/data/sessions/${GROUP}/.claude \
         ~/nanoclaw/data/sessions/${GROUP}/.claude.bak.$(date +%Y%m%d)

   # Supprimer les fichiers de session (pas le CLAUDE.md)
   rm -rf ~/nanoclaw/data/sessions/${GROUP}/.claude/projects/
   ```

2. **Compacter via la commande /compact** :
   Envoyer `/compact` a l'agent sur le canal concerne. Cela declenche une
   compaction du contexte sans perdre la memoire persistante.

3. **Preventif** : La memoire persistante est dans `groups/{name}/CLAUDE.md` et
   n'est pas affectee par la purge de session. Seul l'historique de conversation
   est supprime.

---

## 4. Token OAuth Gmail expire

**Symptome** : Les logs affichent `invalid_grant` ou `Token has been expired or revoked`.
L'agent ne peut plus lire ni envoyer d'emails.

**Cause** : Le token de rafraichissement (refresh token) OAuth2 de Gmail a expire
ou a ete revoque. Cela arrive si :
- Le token n'a pas ete utilise pendant 6 mois
- L'application est en mode "test" sur GCP (expiration a 7 jours)
- L'utilisateur a revoque l'acces dans les parametres Google

**Diagnostic** :

```bash
# Verifier les erreurs OAuth dans les logs
tail -200 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("invalid_grant|oauth|token"; "i"))'

# Verifier que le fichier de credentials existe
ls -la ~/.gmail-mcp/credentials/
```

**Solution** :

1. Re-authentifier le compte Gmail :
   ```bash
   # Supprimer les tokens existants
   rm ~/.gmail-mcp/credentials/*.json

   # Relancer le flux d'authentification OAuth
   # (le processus guidera vers le navigateur pour re-autoriser)
   cd ~/nanoclaw && npm run build && node dist/index.js
   ```

2. **Si l'app GCP est en mode "test"** : Passer l'application en mode "production"
   dans la console GCP > APIs & Services > OAuth consent screen.
   Les tokens en mode test expirent apres 7 jours.

3. Verifier les scopes requis :
   ```
   https://mail.google.com/
   https://www.googleapis.com/auth/calendar
   https://www.googleapis.com/auth/drive.readonly
   ```

4. Redemarrer l'agent apres re-authentification :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

---

## 5. Agent ne recoit pas les emails

**Symptome** : L'agent ne reagit pas aux emails entrants. Les emails apparaissent
dans Gmail mais l'agent ne les traite pas.

**Cause** : Deux modes existent pour la reception d'emails :

| Mode | Variable | Delai | Methode |
|------|----------|-------|---------|
| Polling | `GMAIL_WEBHOOK_ENABLED=false` | 60 secondes | Interrogation periodique de l'API Gmail |
| Webhook | `GMAIL_WEBHOOK_ENABLED=true` | ~5 secondes | Signal Firestore + fallback polling (5 min) |

Le mode webhook necessite un index Firestore correctement configure.

**Diagnostic** :

```bash
# Verifier le mode actif
grep GMAIL_WEBHOOK ~/nanoclaw/.env

# Verifier les logs Gmail
tail -100 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("gmail|email"; "i"))'

# Verifier la configuration Firestore
cat ~/nanoclaw/.env | grep GOOGLE_APPLICATION_CREDENTIALS

# Tester l'acces a l'API Gmail
curl -s http://localhost:3001/health | jq '.channels[] | select(.name == "gmail")'
```

**Solution** :

1. **Mode polling** (par defaut) :
   - Verifier que le compte est configure dans les credentials Gmail :
     ```bash
     ls ~/.gmail-mcp/credentials/
     ```
   - Le delai normal est de 60 secondes. Patienter.

2. **Mode webhook** :
   - Verifier que `GMAIL_WEBHOOK_ENABLED=true` dans `.env`
   - Verifier que `GOOGLE_APPLICATION_CREDENTIALS` pointe vers un fichier de service account valide
   - Creer l'index Firestore necessaire :
     ```
     Collection: gmail-signals
     Champs indexes: agentName (Ascending), processedAt (Ascending)
     ```
   - Verifier que le Cloud Function qui ecrit les signaux Firestore est deployee
   - En mode webhook, le fallback polling tourne toutes les 5 minutes
     (`GMAIL_WEBHOOK_FALLBACK_POLL_MS = 300_000`)

3. **Verifier que l'email n'est pas filtre** : Voir [probleme #6](#6-newsletters-declenchent-lagent)
   — le filtre automatique bloque les newsletters et noreply.

---

## 6. Newsletters declenchent l'agent

**Symptome** : L'agent repond aux emails de newsletters, marketing ou notifications
automatiques, ce qui consomme du credit API inutilement.

**Cause** : L'email expediteur n'est pas reconnu par le filtre automatique.
Le filtre dans `src/channels/gmail.ts` verifie :

1. Prefixes noreply (`noreply@`, `no-reply@`, `notifications@`, etc.)
2. Domaines marketing connus (`mail.beehiiv.com`, `sendgrid.net`, `mailgun.org`, etc.)
3. Header `List-Unsubscribe` (signal fort de newsletter)
4. Header `Precedence: bulk` ou `Precedence: list`
5. Header `Auto-Submitted` (bounces, auto-replies)
6. Headers `X-Campaign-Id` ou `X-Mailchimp-Id`

**Diagnostic** :

```bash
# Chercher les emails traites qui auraient du etre filtres
tail -500 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("gmail.*process|email.*inbound"; "i"))'
```

**Solution** :

Pour ajouter un nouveau domaine au filtre marketing, modifier le tableau
`MARKETING_DOMAINS` dans `src/channels/gmail.ts` :

```typescript
// Ligne ~670 dans src/channels/gmail.ts
private static MARKETING_DOMAINS = [
  'mail.beehiiv.com',
  'email.mailchimp.com',
  'sendgrid.net',
  // ... domaines existants ...
  'nouveau-domaine.com',  // <-- ajouter ici
];
```

Puis recompiler et redemarrer :

```bash
cd ~/nanoclaw && npm run build
launchctl kickstart -k gui/$(id -u)/com.nanoclaw
```

**Alternative** : Si l'email utilise le header `List-Unsubscribe` (la majorite des
newsletters), il sera filtre automatiquement sans modification du code.

---

## 7. Google Chat — bot ne repond pas

**Symptome** : Les messages envoyes dans un espace Google Chat restent sans reponse.
Aucun conteneur agent ne demarre.

**Cause** :
- Le gateway Google Chat (Firestore polling) est down
- `GOOGLE_CHAT_ENABLED` n'est pas `true` dans `.env`
- Le service account Firestore est invalide ou le fichier manquant
- La configuration Chat App dans la console GCP est incomplete

**Diagnostic** :

```bash
# Verifier que le channel est actif
grep GOOGLE_CHAT_ENABLED ~/nanoclaw/.env

# Verifier les logs Google Chat
tail -100 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("google.chat|gchat"; "i"))'

# Verifier le service account Firestore
ls -la $(grep GOOGLE_APPLICATION_CREDENTIALS ~/nanoclaw/.env | cut -d= -f2)

# Verifier le service account Chat Bot
ls -la $(grep GOOGLE_CHAT_BOT_SA ~/nanoclaw/.env | cut -d= -f2)

# Health check
curl -s http://localhost:3001/health | jq '.channels[] | select(.name == "google-chat")'
```

**Solution** :

1. Verifier les variables d'environnement dans `.env` :
   ```env
   GOOGLE_CHAT_ENABLED=true
   GOOGLE_CHAT_AGENT_NAME=nanoclaw
   GOOGLE_APPLICATION_CREDENTIALS=/chemin/vers/firebase-service-account.json
   GOOGLE_CHAT_BOT_SA=/chemin/vers/chat-bot-service-account.json
   ```

2. Verifier que les fichiers de service account existent et sont valides :
   ```bash
   cat $GOOGLE_APPLICATION_CREDENTIALS | jq .project_id
   cat $GOOGLE_CHAT_BOT_SA | jq .client_email
   ```

3. Verifier la configuration Chat App dans la console GCP :
   - Le bot doit etre configure en mode "App" avec les evenements actives
   - Le service account du bot doit avoir le role `Chat Bots`

4. Redemarrer :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

---

## 8. Google Chat — "unknown email"

**Symptome** : Les logs affichent un message de type "unknown email" ou l'agent
ignore les messages d'un compte specifique dans Google Chat.

**Cause** : Le compte email qui envoie le message dans Google Chat n'est pas
enregistre dans la configuration de l'agent. Le `GOOGLE_CHAT_AGENT_NAME` dans `.env`
doit correspondre a la valeur attendue par le systeme de routage Firestore.

**Diagnostic** :

```bash
# Verifier le nom de l'agent configure
grep GOOGLE_CHAT_AGENT_NAME ~/nanoclaw/.env

# Verifier les messages ignores dans les logs
tail -200 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("unknown|unregistered|ignore"; "i"))'
```

**Solution** :

1. Verifier que `GOOGLE_CHAT_AGENT_NAME` correspond exactement au nom utilise
   dans les documents Firestore de routage :
   ```env
   GOOGLE_CHAT_AGENT_NAME=nanoclaw
   ```

2. Si plusieurs agents existent (nanoclaw, alan, etc.), chaque agent doit avoir
   un nom unique qui correspond a sa configuration Firestore.

3. Verifier dans Firestore que le document de l'espace Chat reference le bon agent.

4. Recompiler et redemarrer apres modification :
   ```bash
   cd ~/nanoclaw && npm run build
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

---

## 9. Container crash (exit code 137)

**Symptome** : Le conteneur se termine avec le code de sortie 137. Les logs montrent
que le conteneur a ete tue en cours d'execution.

**Cause** : Le code 137 signifie que le processus a recu `SIGKILL`. Deux causes
principales :
- **OOM Kill** : Le conteneur a depasse la limite de memoire Docker
- **Timeout** : NanoClaw tue le conteneur apres `CONTAINER_TIMEOUT` (defaut : 30 min)

**Diagnostic** :

```bash
# Verifier les evenements Docker recents
docker events --since 1h --filter event=oom --filter event=kill

# Verifier le timeout configure
grep CONTAINER_TIMEOUT ~/nanoclaw/.env

# Verifier la memoire disponible
docker stats --no-stream

# Logs du conteneur avant le crash
docker logs $(docker ps -a --filter name=nanoclaw -q --latest) 2>&1 | tail -30
```

**Solution** :

1. **OOM Kill** — Augmenter la limite memoire Docker :
   - Docker Desktop > Settings > Resources > Memory
   - Recommandation : minimum 4 GB pour les agents Claude

2. **Timeout** — Augmenter le timeout si necessaire :
   ```env
   # Dans .env (valeur en millisecondes, defaut: 1800000 = 30 min)
   CONTAINER_TIMEOUT=3600000  # 1 heure
   ```

3. **Preventif** : Reduire la taille des sessions (voir [probleme #3](#3-prompt-is-too-long))
   et limiter les taches longues.

---

## 10. Container crash (exit code 1)

**Symptome** : Le conteneur se termine avec le code de sortie 1. Erreur generique.

**Cause** : Le code 1 indique une erreur applicative a l'interieur du conteneur.
Causes frequentes :
- Session Claude introuvable ou corrompue
- Erreur API Anthropic (cle invalide, modele indisponible)
- Fichier de configuration manquant dans les montages

**Diagnostic** :

```bash
# Logs du dernier conteneur crashe
docker logs $(docker ps -a --filter name=nanoclaw --filter status=exited -q --latest) 2>&1

# Verifier l'image du conteneur
docker images nanoclaw-agent

# Verifier les montages
docker inspect $(docker ps -a --filter name=nanoclaw -q --latest) | jq '.[0].Mounts'
```

**Solution** :

1. **Session corrompue** : Purger la session du groupe concerne
   (voir [probleme #3](#3-prompt-is-too-long)).

2. **Erreur API** : Verifier que la cle API est valide :
   ```bash
   # Le credential proxy injecte la cle — verifier qu'elle est dans .env
   grep ANTHROPIC_API_KEY ~/nanoclaw/.env | head -c 20
   # Doit afficher "ANTHROPIC_API_KEY=sk" (ne jamais afficher la cle complete)
   ```

3. **Image obsolete** : Reconstruire l'image :
   ```bash
   cd ~/nanoclaw && ./container/build.sh
   ```
   Si le cache pose probleme :
   ```bash
   docker builder prune -f
   ./container/build.sh
   ```

4. Redemarrer apres correction :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

---

## 11. Port deja utilise (EADDRINUSE)

**Symptome** : L'agent ne demarre pas. Les logs affichent :

```
Error: listen EADDRINUSE: address already in use :::3001
```

**Cause** : Une autre instance de NanoClaw (ou un autre processus) utilise deja
le port du credential proxy. Par defaut, le port est `3001`.

**Diagnostic** :

```bash
# Identifier le processus qui utilise le port
lsof -i :3001

# Verifier les instances NanoClaw en cours
launchctl list | grep nanoclaw
ps aux | grep nanoclaw
```

**Solution** :

1. **Tuer le processus orphelin** :
   ```bash
   # Trouver le PID
   lsof -t -i :3001
   # Le tuer
   kill $(lsof -t -i :3001)
   ```

2. **Si plusieurs agents tournent** : Chaque instance doit avoir un port unique.
   Modifier `CREDENTIAL_PROXY_PORT` dans `.env` :
   ```env
   # Agent principal
   CREDENTIAL_PROXY_PORT=3001
   # Agent secondaire (dans son propre .env)
   CREDENTIAL_PROXY_PORT=3002
   ```

3. Redemarrer :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

---

## 12. Credit balance too low

**Symptome** : Les agents refusent de repondre. Les logs ou les metriques montrent
`limit_hit: true`. Le credential proxy retourne des erreurs 429.

**Cause** : Le systeme de controle des couts dans le credential proxy (`src/credential-proxy.ts`)
suit la depense quotidienne. Quand la depense estimee atteint `DAILY_API_LIMIT_USD`
(defaut : $20), toutes les requetes API sont bloquees jusqu'au lendemain (reset a minuit UTC).

L'etat est persiste dans `store/daily-spend.json`.

**Diagnostic** :

```bash
# Verifier la depense du jour
cat ~/nanoclaw/store/daily-spend.json | jq .

# Verifier la limite configuree
grep DAILY_API_LIMIT_USD ~/nanoclaw/.env

# Verifier les metriques
curl -s http://localhost:3001/metrics | grep daily
```

**Solution** :

1. **Augmenter la limite quotidienne** (temporaire ou permanent) :
   ```env
   # Dans .env
   DAILY_API_LIMIT_USD=50
   ```

2. **Remettre a zero le compteur du jour** :
   ```bash
   # Supprimer le fichier de suivi (sera recree a la prochaine requete)
   rm ~/nanoclaw/store/daily-spend.json
   ```

3. **Verifier le solde Anthropic** : Se connecter sur https://console.anthropic.com/
   et verifier que le compte a un solde suffisant ou que la carte de paiement
   est valide.

4. Redemarrer apres modification :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

---

## 13. Circuit breaker ouvert

**Symptome** : Toutes les requetes API retournent 503. Les logs affichent
`Circuit breaker opened` ou `circuit_breaker` dans les metriques.

**Cause** : Le circuit breaker du credential proxy s'ouvre apres 5 erreurs
consecutives 5xx de l'API Anthropic (`CIRCUIT_BREAKER_THRESHOLD = 5`).
Une fois ouvert, il bloque toutes les requetes pendant 60 secondes
(`CIRCUIT_BREAKER_RESET_MS = 60_000`), puis passe en mode "half-open" pour
tester avec une seule requete.

Les trois etats possibles :
- **closed** : fonctionnement normal
- **open** : toutes les requetes bloquees (503)
- **half-open** : une requete de test autorisee, les autres bloquees

**Diagnostic** :

```bash
# Verifier l'etat du circuit breaker via les metriques
curl -s http://localhost:3001/metrics | grep circuit_breaker

# Verifier les erreurs 5xx recentes
tail -200 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("5[0-9]{2}|circuit|upstream"; "i"))'

# Verifier le statut de l'API Anthropic
curl -s https://status.anthropic.com/api/v2/status.json | jq .status
```

**Solution** :

1. **Attendre le reset automatique** : Le circuit breaker se remet automatiquement
   en mode "half-open" apres 60 secondes, puis "closed" si la requete de test reussit.

2. **Si l'API Anthropic est down** : Attendre que le service soit retabli.
   Verifier https://status.anthropic.com/.

3. **Forcer un reset** : Redemarrer l'agent remet le circuit breaker a "closed" :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.nanoclaw
   ```

4. **Surveiller** :
   ```bash
   # Suivre l'etat en temps reel
   watch -n5 'curl -s http://localhost:3001/metrics | grep circuit_breaker'
   ```

---

## 14. Botti Voice — pas de son

**Symptome** : Botti Voice ne produit pas de sortie audio ou le son est corrompu.

**Cause** :
- Le modele Gemini utilise pour la synthese vocale n'est pas correctement configure
- Le format audio de sortie n'est pas supporte par le client
- Le token API Google est invalide ou a depasse son quota

**Diagnostic** :

```bash
# Verifier les logs de Botti Voice
tail -100 ~/botti-voice/logs/*.log | grep -i "audio\|voice\|gemini\|error"

# Verifier que le service tourne
ps aux | grep botti-voice
```

**Solution** :

1. Verifier la configuration du modele Gemini dans les parametres de Botti Voice.

2. S'assurer que le format audio est compatible (PCM 16-bit, WAV, ou OGG selon la config).

3. Verifier le quota API Google :
   ```bash
   # Tester l'acces a l'API Gemini
   curl -s "https://generativelanguage.googleapis.com/v1/models?key=$GEMINI_API_KEY" | jq .
   ```

4. Redemarrer Botti Voice :
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.botti-voice
   ```

---

## 15. Botti Voice — ne peut pas lire les emails

**Symptome** : Botti Voice ne peut pas acceder aux emails lorsqu'on lui demande
de les lire. Erreur d'authentification ou de permission.

**Cause** :
- Token OAuth Gmail expire (meme cause que [probleme #4](#4-token-oauth-gmail-expire))
- Les scopes OAuth ne couvrent pas la lecture des emails
- Le mauvais compte est configure

**Diagnostic** :

```bash
# Verifier les erreurs d'authentification
tail -100 ~/botti-voice/logs/*.log | grep -i "oauth\|token\|gmail\|auth"

# Verifier les scopes du token
cat ~/.gmail-mcp/credentials/*.json | jq .scope 2>/dev/null
```

**Solution** :

1. Re-authentifier avec les scopes corrects. Le scope `https://mail.google.com/`
   est obligatoire pour la lecture des emails :
   ```bash
   # Supprimer les anciens tokens
   rm ~/.gmail-mcp/credentials/*.json

   # Re-lancer l'authentification
   # (le processus ouvrira le navigateur)
   ```

2. Verifier que le compte email configure est le bon :
   ```bash
   grep GMAIL ~/.env
   ```

3. Redemarrer Botti Voice apres re-authentification.

---

## 16. Dashboard ne s'affiche pas

**Symptome** : L'URL `http://localhost:3100` (ou le port configure) ne repond pas.
Le navigateur affiche "Connection refused".

**Cause** :
- Le service NanoClaw n'est pas lance
- Le credential proxy (qui sert aussi le health/metrics) ecoute sur un autre port
- Un pare-feu bloque la connexion

**Diagnostic** :

```bash
# Verifier que le service tourne
launchctl list | grep nanoclaw

# Verifier le port effectif
grep CREDENTIAL_PROXY_PORT ~/nanoclaw/.env
# Defaut: 3001

# Tester le health check
curl -v http://localhost:3001/health

# Verifier tous les ports ouverts par NanoClaw
lsof -i -P | grep node | grep LISTEN
```

**Solution** :

1. Le endpoint principal est sur le port du credential proxy (defaut `3001`),
   pas `3100`. Verifier le bon port :
   ```bash
   curl http://localhost:3001/health
   curl http://localhost:3001/metrics
   ```

2. Si le service est down, le demarrer :
   ```bash
   launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist
   ```

3. Verifier les logs pour comprendre pourquoi le service ne demarre pas :
   ```bash
   tail -50 ~/nanoclaw/logs/nanoclaw.log | jq .
   ```

---

## 17. Impossible de push sur GitHub

**Symptome** : `git push` echoue avec une erreur de permission ou de ruleset.

```
remote: error: GH013: Repository rule violations found
```

**Cause** : Le fork principal a des rulesets qui interdisent le push direct sur
la branche `main`. Cela protege contre les modifications accidentelles.

**Diagnostic** :

```bash
# Verifier les remotes
git remote -v

# Verifier la branche courante
git branch --show-current

# Verifier les rulesets
gh api repos/OWNER/REPO/rulesets | jq '.[].name'
```

**Solution** :

1. **Utiliser le repo prive** : Pusher vers `nanoclaw-private` au lieu du fork public :
   ```bash
   git remote add private https://github.com/OWNER/nanoclaw-private.git
   git push private main
   ```

2. **Creer une branche** : Si les rulesets interdisent le push sur `main`,
   creer une branche et ouvrir une PR :
   ```bash
   git checkout -b fix/ma-correction
   git push origin fix/ma-correction
   gh pr create --title "Ma correction" --body "Description"
   ```

3. **Pour les customisations locales** : Committer localement sans pusher.
   Les personnalisations restent sur la machine.

---

## 18. Comment redemarrer un agent

**Symptome** : Besoin de redemarrer un agent apres une modification de configuration
ou un probleme.

### macOS (launchd)

```bash
# Redemarrage rapide (recommande)
launchctl kickstart -k gui/$(id -u)/com.nanoclaw

# Reload complet (apres modification du plist)
launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist

# Verifier l'etat
launchctl list | grep nanoclaw
# Le deuxieme champ est le code de sortie (0 = OK, - = en cours)
```

### Agents supplementaires

Chaque agent a son propre plist. Remplacer `com.nanoclaw` par le nom de l'agent :

```bash
# Agent Alan
launchctl kickstart -k gui/$(id -u)/com.nanoclaw-alan

# Agent Sam
launchctl kickstart -k gui/$(id -u)/com.nanoclaw-sam
```

### Linux (systemd)

```bash
systemctl --user restart nanoclaw
systemctl --user status nanoclaw
```

### Arreter proprement

```bash
# macOS
launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist

# Tuer les conteneurs orphelins
docker ps --filter name=nanoclaw -q | xargs -r docker stop
```

---

## 19. Comment voir les logs

**Symptome** : Besoin de lire les logs pour diagnostiquer un probleme.

### Emplacement des logs

```bash
# Log principal
~/nanoclaw/logs/nanoclaw.log

# Agents supplementaires (si configures separement)
~/nanoclaw-alan/logs/nanoclaw.log
~/nanoclaw-sam/logs/nanoclaw.log
```

### Commandes utiles

Les logs sont au format JSON (pino). Utiliser `jq` pour les formater :

```bash
# Dernieres 20 lignes, formate
tail -20 ~/nanoclaw/logs/nanoclaw.log | jq .

# Suivre en temps reel
tail -f ~/nanoclaw/logs/nanoclaw.log | jq .

# Filtrer par niveau (error, warn, info)
tail -200 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.level >= 50)'
# Niveaux pino: 10=trace, 20=debug, 30=info, 40=warn, 50=error, 60=fatal

# Filtrer par message
tail -500 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.msg | test("gmail"; "i"))'

# Filtrer par periode (derniere heure)
tail -1000 ~/nanoclaw/logs/nanoclaw.log | jq 'select(.time > (now - 3600) * 1000)'

# Compter les erreurs par type
tail -1000 ~/nanoclaw/logs/nanoclaw.log | jq -r 'select(.level >= 50) | .msg' | sort | uniq -c | sort -rn

# Logs d'un conteneur specifique
docker logs nanoclaw-whatsapp_main 2>&1 | tail -50
```

### Metriques en temps reel

```bash
# Health check complet
curl -s http://localhost:3001/health | jq .

# Metriques Prometheus
curl -s http://localhost:3001/metrics

# Depense du jour
cat ~/nanoclaw/store/daily-spend.json | jq .
```

### Changer le niveau de log

```env
# Dans .env
LOG_LEVEL=debug  # trace, debug, info, warn, error, fatal
```

Puis redemarrer l'agent.

---

## 20. Comment creer un nouvel agent

**Symptome** : Besoin de deployer une nouvelle instance NanoClaw pour un
utilisateur ou un cas d'usage different.

### Utiliser le script create-agent.sh

```bash
# Syntaxe
./create-agent.sh <nom> <email> [--port PORT] [--model MODEL]

# Exemples
./create-agent.sh alan alan@example.com --port 3004
./create-agent.sh marie marie@example.com  # port auto-detecte
```

Le script effectue automatiquement :
1. Copie de la configuration de base
2. Attribution d'un port unique (range 3001-3010)
3. Configuration du service account Firebase
4. Creation du plist launchd
5. Configuration des scopes OAuth (Gmail, Calendar, Drive)

### Etapes manuelles (si le script ne suffit pas)

1. **Creer le repertoire** :
   ```bash
   cp -r ~/nanoclaw ~/nanoclaw-nouveau
   cd ~/nanoclaw-nouveau
   ```

2. **Configurer l'environnement** :
   ```bash
   cp .env.example .env
   # Modifier .env avec les bonnes valeurs :
   # - ASSISTANT_NAME (nom unique)
   # - CREDENTIAL_PROXY_PORT (port unique)
   # - CONTAINER_PREFIX (prefixe unique pour Docker)
   # - ANTHROPIC_API_KEY
   ```

3. **Installer les dependances** :
   ```bash
   npm install
   npm run build
   ```

4. **Creer le plist launchd** :
   ```bash
   # Copier et adapter le plist existant
   cp ~/Library/LaunchAgents/com.nanoclaw.plist \
      ~/Library/LaunchAgents/com.nanoclaw-nouveau.plist
   # Modifier le chemin de travail, le label et le port
   ```

5. **Demarrer l'agent** :
   ```bash
   launchctl load ~/Library/LaunchAgents/com.nanoclaw-nouveau.plist
   ```

6. **Verifier** :
   ```bash
   launchctl list | grep nanoclaw-nouveau
   curl http://localhost:PORT/health
   ```

### Points importants

- Chaque agent doit avoir un `CONTAINER_PREFIX` unique pour eviter les conflits Docker
- Chaque agent doit avoir un `CREDENTIAL_PROXY_PORT` unique
- Les groupes sont isoles : chaque agent a son propre `groups/` et `data/sessions/`
- Le fichier `store/daily-spend.json` est par instance (chaque agent a son propre budget)

---

## Aide supplementaire

Si un probleme persiste apres avoir suivi ce guide :

1. Activer les logs en mode `debug` :
   ```env
   LOG_LEVEL=debug
   ```

2. Utiliser le skill `/debug` dans une conversation avec l'agent pour un
   diagnostic interactif.

3. Verifier les metriques pour des anomalies :
   ```bash
   curl -s http://localhost:3001/metrics
   ```

4. Consulter la documentation technique dans `docs/ARCHITECTURE.md` et
   `docs/REQUIREMENTS.md` pour comprendre le fonctionnement interne.
