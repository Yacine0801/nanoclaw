# NanoClaw -- Vue technique complete

**Document a destination d'Ahmed Amdouni, CTO de Botler 360 / Best of Tours**

Version : 1.0.0
Date : 31 mars 2026
Auteur : Yacine Bakouche + Claude Code

---

# Table des matieres

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture globale](#2-architecture-globale)
3. [Les agents](#3-les-agents)
4. [Les channels (canaux de communication)](#4-les-channels-canaux-de-communication)
5. [Containers et isolation](#5-containers-et-isolation)
6. [Memoire et persistance](#6-memoire-et-persistance)
7. [Securite](#7-securite)
8. [Infrastructure](#8-infrastructure)
9. [Deploiement et operations](#9-deploiement-et-operations)
10. [Stack technique detaillee](#10-stack-technique-detaillee)
11. [Decisions architecturales et trade-offs](#11-decisions-architecturales-et-trade-offs)
12. [Roadmap et prochaines etapes](#12-roadmap-et-prochaines-etapes)
13. [Comment creer un nouvel agent](#13-comment-creer-un-nouvel-agent)
14. [Annexes](#14-annexes)

---

# 1. Vue d'ensemble

## 1.1 Qu'est-ce que NanoClaw

NanoClaw est un systeme d'agents IA personnels qui tournent sur un Mac Mini local. Chaque agent est une instance autonome de Claude (via le Claude Agent SDK / Claude Code) qui peut :

- Recevoir et repondre a des messages via WhatsApp, Gmail, Google Chat
- Envoyer et lire des emails
- Naviguer sur le web
- Executer du code dans un sandbox Docker isole
- Planifier des taches recurrentes
- Maintenir une memoire persistante entre les sessions
- Acceder a Google Calendar, Drive, Sheets, Docs

Le systeme fait tourner **4 agents simultanement** sur une seule machine :

| Agent | Role | Email | Channels |
|-------|------|-------|----------|
| **Botti** | Assistant personnel de Yacine | yacine@bestoftours.co.uk | WhatsApp, Gmail, Google Chat, Voice |
| **Sam** | Assistant operationnel | sam@bestoftours.co.uk | Gmail, Google Chat |
| **Thais** | Assistante de direction | thais@bestoftours.co.uk | Gmail, Google Chat |
| **Alan** | Assistant operationnel | ala@bestoftours.co.uk | Gmail, Google Chat |

## 1.2 Pourquoi on l'a construit

NanoClaw est ne d'une frustration avec OpenClaw (anciennement ClawBot), un projet open-source similaire qui etait devenu ingerable :

- ~500 000 lignes de code
- 53 fichiers de configuration
- 70+ dependances
- 4-5 processus differents
- Securite applicative (allowlists, pairing codes) plutot qu'isolation reelle
- Impossible de comprendre le code en entier

NanoClaw prend l'approche inverse :

- **Un seul processus Node.js** par agent
- **Quelques fichiers source** (le core fait ~35k tokens, soit ~17% d'une fenetre de contexte Claude)
- **Isolation reelle** via containers Docker (pas juste des permissions applicatives)
- **AI-native** : pas de dashboard, pas de wizard d'installation, pas d'outils de debug -- Claude Code fait tout

## 1.3 La philosophie

### Assez petit pour etre compris

Le codebase entier est lisible en une session. Un humain (ou Claude) peut comprendre la totalite du systeme. C'est un choix delibere : la securite vient du fait qu'on peut auditer tout le code.

### Securite par isolation

Les agents ne sont pas "empeches" d'acceder a des fichiers via des permissions applicatives. Ils tournent dans des containers Linux ou seuls les fichiers explicitement montes sont visibles. C'est de l'isolation au niveau OS/hyperviseur, pas au niveau application.

### Construit pour un seul utilisateur

Ce n'est pas un framework generaliste. C'est un logiciel personnel. Chaque installation est un fork qui est modifie pour correspondre exactement aux besoins de l'utilisateur. Il n'y a pas de "configuration" -- on modifie le code directement.

### AI-native

Pas de wizard d'installation : Claude Code guide le setup.
Pas de monitoring dashboard (sauf le minimal qu'on a ajoute) : on demande a Claude ce qui se passe.
Pas d'outils de debug : on decrit le probleme et Claude le resout.

### Skills plutot que features

Plutot que d'ajouter du support Telegram au core, les contributeurs soumettent des "skills" comme `/add-telegram` qui transforment le code du fork de l'utilisateur. Le resultat : du code propre qui fait exactement ce qu'il faut, pas un systeme generique qui essaie de tout supporter.

## 1.4 Le Mac Mini comme serveur personnel

### Pourquoi pas le Cloud

| Aspect | Mac Mini local | Cloud (GCE/EC2) |
|--------|---------------|-----------------|
| Cout mensuel | ~0 EUR (deja achete) | 50-200 EUR/mois pour 4 agents |
| Latence Docker | < 100ms | Identique |
| WhatsApp auth | Locale (Baileys, session persistante) | Problematique (IP dynamique, ban) |
| Secrets | Sur disque local, jamais exposes | Variables d'environnement cloud |
| Maintenance | launchd, auto-restart | Plus complexe (SSH, firewalls) |
| Scaling | Limite par la machine | Elastique |
| Disponibilite | Depend du reseau maison | 99.9%+ SLA |

### Le compromis

On a choisi le Mac Mini parce que :
1. WhatsApp via Baileys necessite une session locale persistante (changement d'IP = risque de ban)
2. Le cout est nul (machine deja possedee)
3. 4 agents Claude + Docker tournent confortablement sur Apple Silicon
4. Les secrets (API keys) ne quittent jamais la machine

Les inconvenients :
1. Pas de haute disponibilite (si le Mac Mini tombe, tout s'arrete)
2. Depend de la connexion internet du bureau
3. Pas de scaling au-dela des ressources de la machine

### Services Cloud utilises malgre tout

Certains composants necessitent une URL publique et tournent sur **Google Cloud Run** :
- **Botti Voice** : interface audio temps reel (necessite HTTPS + WebSocket public)
- **Chat Gateway** : endpoint pour les webhooks Google Chat (necessite URL publique)

---

# 2. Architecture globale

## 2.1 Diagramme d'architecture

```
                                INTERNET
                                   |
                   +---------------+---------------+
                   |               |               |
              Cloud Run        Cloud Run       Google APIs
              (Voice)         (Chat GW)       (Gmail, Chat,
                   |               |           Calendar)
                   |               |               |
                   |        Firestore          Pub/Sub
                   |        (chat-queue,       (webhooks)
                   |         gmail-notify)         |
                   |               |               |
                   +-------+-------+-------+-------+
                           |                       |
         +-----------------+-----------------------+---------+
         |                    MAC MINI (local)                |
         |                                                    |
         |  +----------+  +----------+  +----------+  +----+ |
         |  | NanoClaw |  | NanoClaw |  | NanoClaw |  | NC | |
         |  | (Botti)  |  | (Sam)    |  | (Thais)  |  |(Al)| |
         |  | :3001    |  | :3003    |  | :3002    |  |:30 | |
         |  +----+-----+  +----+-----+  +----+-----+  |04 | |
         |       |              |              |       +--+-+ |
         |       |              |              |          |   |
         |  +----+--------------+--------------+----------+   |
         |  |              Docker Desktop                  |   |
         |  |  +--------+ +--------+ +--------+ +------+  |   |
         |  |  |Agent   | |Agent   | |Agent   | |Agent |  |   |
         |  |  |Botti   | |Sam     | |Thais   | |Alan  |  |   |
         |  |  |Claude  | |Claude  | |Claude  | |Clau  |  |   |
         |  |  |Code SDK| |Code SDK| |Code SDK| |de SDK|  |   |
         |  |  +--------+ +--------+ +--------+ +------+  |   |
         |  +----------------------------------------------+   |
         |                                                    |
         |  +------------------+  +-------------------------+ |
         |  | Dashboard :3100  |  | SQLite (messages.db x4) | |
         |  +------------------+  +-------------------------+ |
         |                                                    |
         |  +----------------------------------------------+  |
         |  |        WhatsApp (Baileys)                    |  |
         |  |        -- session locale --                   |  |
         |  +----------------------------------------------+  |
         +----------------------------------------------------+
```

## 2.2 Les composants

### NanoClaw Core (Node.js + TypeScript)

Le coeur du systeme. Un processus Node.js par agent. Responsable de :

- **Channels** : connexion aux sources de messages (WhatsApp, Gmail, Google Chat)
- **Message Loop** : boucle de polling qui detecte les nouveaux messages
- **Container Runner** : spawn des containers Docker pour executer Claude
- **Credential Proxy** : proxy HTTP qui injecte les secrets API dans les requetes
- **Task Scheduler** : execute les taches planifiees
- **IPC Watcher** : communication inter-processus avec les containers via le filesystem
- **SQLite** : persistence des messages, sessions, groupes, taches

### Botti Voice (Python + FastAPI, Cloud Run)

Interface vocale temps reel utilisant l'API Gemini Live native audio :

- WebSocket bidirectionnel : navigateur <-> serveur <-> Gemini
- Audio PCM 16kHz (entree) et 24kHz (sortie)
- Function calling pour Gmail, Calendar, Drive
- Selection d'agent (Botti, Sam, Thais) avec memoire partagee depuis NanoClaw
- Authentification Google OAuth + PIN optionnel
- Hebergee sur Cloud Run (necessite HTTPS public pour les WebSockets)

### Chat Gateway (Python + FastAPI, Cloud Run)

Point d'entree pour les webhooks Google Chat :

- Recoit les evenements de la Chat App "Botti" (un seul Chat App GCP pour les 4 agents)
- Route les messages vers le bon agent via `@mention` ou mapping space->agent dans Firestore
- Stocke les messages dans Firestore pour que les agents NanoClaw les recuperent en polling
- Hebergee sur Cloud Run (necessite URL publique pour les webhooks Google Chat)

### Dashboard (Node.js, local)

Interface de monitoring minimale sur le port 3100 :

- Decouvre automatiquement toutes les instances NanoClaw sur la machine
- Affiche l'etat de chaque agent (running/stopped, PID, uptime)
- Montre les channels connectes, la derniere activite, le nombre d'erreurs
- Compte les containers Docker actifs
- API JSON sur `/api/status`

## 2.3 Flux de donnees : du message a la reponse

### Flux WhatsApp (Botti uniquement)

```
1. Utilisateur envoie un message WhatsApp
2. Baileys (lib WhatsApp Web) recoit le message via WebSocket
3. WhatsApp channel stocke le message dans SQLite (storeMessage)
4. Message Loop (polling toutes les 2s) detecte le nouveau message
5. Verifie : message dans un groupe enregistre ? Trigger @Botti present ?
6. Si oui, formate les messages en prompt texte
7. Container Runner spawn un container Docker
8. Claude Agent SDK s'execute dans le container
9. Claude traite le prompt, utilise des outils si necessaire (web, bash, etc.)
10. Sortie streamee via stdout du container
11. NanoClaw parse la sortie et envoie la reponse via WhatsApp
12. Session Claude sauvegardee pour continuite de conversation
```

### Flux Gmail

```
1. Email arrive dans la boite Gmail de l'agent
2. OPTION A (polling) : NanoClaw poll l'API Gmail toutes les 60s (5min si webhook actif)
3. OPTION B (webhook) :
   a. Gmail API Pub/Sub notifie Botti Voice (Cloud Run)
   b. Botti Voice ecrit un signal dans Firestore (gmail-notify/{agent}/signals)
   c. NanoClaw poll Firestore toutes les 5s, detecte le signal
   d. Declenche un poll immediat de l'API Gmail
4. Email filtre (pas de newsletters, pas de noreply, pas de mailing lists)
5. Contenu extrait et formate en message pour le groupe principal (main)
6. Meme flux qu'un message WhatsApp a partir de l'etape 6
7. Reponse :
   - Destinataire interne (@bestoftours.co.uk) : envoi direct + CC yacine@
   - Destinataire externe : creation d'un brouillon + notification a yacine@
```

### Flux Google Chat

```
1. Utilisateur envoie un message dans un espace Google Chat
2. Google Chat envoie un webhook au Chat Gateway (Cloud Run)
3. Chat Gateway determine l'agent cible :
   a. Si @mention (@Sam, @Thais, etc.) : route vers l'agent mentionne
   b. Sinon : utilise le mapping space->agent dans Firestore
4. Chat Gateway ecrit le message dans Firestore (chat-queue/{agent}/messages)
5. NanoClaw poll Firestore toutes les 5s, detecte le message
6. Message formate et injecte dans le groupe principal (main)
7. Meme flux qu'un message WhatsApp a partir de l'etape 6
8. Reponse envoyee via l'API Google Chat (service account du Chat Bot)
9. Cross-posting : si le message venait de Google Chat, la reponse est aussi
   envoyee dans l'espace Chat d'origine (en plus de WhatsApp/Gmail)
```

### Flux Voice (Botti Voice)

```
1. Yacine ouvre l'interface web de Botti Voice (HTTPS, Cloud Run)
2. Authentification Google OAuth + verification email + PIN optionnel
3. Connexion WebSocket bidirectionnelle navigateur <-> serveur
4. Serveur ouvre une session Gemini Live API
5. Audio du micro envoye en chunks PCM 16kHz via WebSocket
6. Gemini traite l'audio en temps reel (native audio, pas de STT/TTS)
7. Gemini peut appeler des outils (Gmail, Calendar, Drive, Google Search)
8. Audio de reponse streame en PCM 24kHz via WebSocket
9. Barge-in : si Yacine parle pendant que Gemini repond, interruption immediate
10. Memoire : Gemini charge le CLAUDE.md de l'agent selectionne
```

## 2.4 Multi-instance : 4 agents sur une machine

Chaque agent est une instance separee de NanoClaw avec :

- Son propre **repertoire de travail** (`/Users/boty/nanoclaw` pour Botti, `/Users/boty/nanoclaw-sam` pour Sam, etc.)
- Son propre **fichier .env** (nom, port, prefixe container)
- Son propre **service launchd** (com.nanoclaw, com.nanoclaw.sam, etc.)
- Sa propre **base de donnees SQLite** (`store/messages.db`)
- Son propre **port credential proxy** (3001, 3002, 3003, 3004)
- Ses propres **containers Docker** (prefixe unique : nanoclaw-, nanoclaw-sam-, etc.)

Les instances partagent :

- Le **code source compile** (`dist/`) -- copie via `deploy.sh`, pas de symlink
- Les **node_modules** (symlink vers le repertoire principal)
- L'**image Docker** (`nanoclaw-agent:latest`)
- Le **service account Firebase** (`~/.firebase-mcp/adp-service-account.json`)
- La **cle API Anthropic** (meme cle pour tous les agents)

### Architecture de fichiers multi-instance

```
/Users/boty/
  nanoclaw/                     # Botti (instance principale)
    src/                        # Code source TypeScript
    dist/                       # Code compile JavaScript
    container/                  # Dockerfile + agent-runner
    node_modules/               # Dependances npm
    groups/
      whatsapp_main/            # Groupe principal Botti (WhatsApp)
        CLAUDE.md               # Memoire/identite de Botti
    store/
      messages.db               # Base SQLite de Botti
      auth/                     # Credentials WhatsApp (Baileys)
    data/
      sessions/                 # Sessions Claude par groupe
    logs/
      nanoclaw.log              # Logs JSON (pino)
    .env                        # Config Botti

  nanoclaw-sam/                 # Sam (instance secondaire)
    dist/                       # Copie du dist/ de nanoclaw
    container -> ../nanoclaw/container    # Symlink
    node_modules -> ../nanoclaw/node_modules  # Symlink
    groups/
      gmail_main/               # Groupe principal Sam (Gmail)
        CLAUDE.md               # Memoire/identite de Sam
    store/
      messages.db               # Base SQLite de Sam
    .env                        # Config Sam

  nanoclaw-thais/               # Thais (meme structure que Sam)
  nanoclaw-alan/                # Alan (meme structure que Sam)
```

---

# 3. Les agents

## 3.1 Botti -- Assistant personnel de Yacine

### Identite

| Propriete | Valeur |
|-----------|--------|
| Nom | Botti |
| Role | Assistant IA personnel de Yacine |
| Email | yacine@bestoftours.co.uk |
| Channels | WhatsApp, Gmail, Google Chat, Voice |
| Modele | Claude Opus 4.6 |
| Trigger | @Botti |
| Port proxy | 3001 |
| Prefixe container | nanoclaw |
| Repertoire | /Users/boty/nanoclaw |
| Service launchd | com.nanoclaw |

### Personnalite

Botti est l'agent principal, le seul qui a acces a WhatsApp. Il est proactif, factuel, direct, sans flatterie ni verbosite. Il communique en francais par defaut, en anglais quand le contexte l'exige (email international, equipe UK).

### Regles specifiques

- Tutoie Yacine, jamais de vouvoiement
- Ne jamais suggerer de deleguer a Ahmed ce que Yacine peut faire seul avec Claude Code
- Estimations calibrees sur le mode Yacine + Claude Code (pas les conventions du secteur)
- Traiter chaque echange comme une conversation entre pairs, pas du support client
- Si une incoherence est detectee, le dire directement sans diplomatie

### Memoire (CLAUDE.md)

Le CLAUDE.md de Botti (dans `groups/whatsapp_main/`) contient :

- Identite complete de Yacine (PDG Botler 360 / Best of Tours, HPI, profil cognitif)
- L'organigramme complet de l'equipe (Eline COO, Ahmed CTO, + equipe elargie)
- L'ecosysteme business (Best of Tours UK/FR, Botler 360, Teletravel, YLE, Bot Events, TrobelAI)
- Les projets en cours (Marie Blachere, NGE/SHIBA, COP31, distribution locale)
- La stack technique (GCP, Claude, Vertex AI, etc.)
- Les regles critiques (signatures emails, confidentialite, proactivite)
- L'historique des conversations et decisions

### Capacites uniques (vs les autres agents)

- **WhatsApp** : seul agent avec un numero WhatsApp (celui de Yacine)
- **Cross-posting Google Chat** : les reponses aux messages Google Chat sont envoyees a la fois dans le chat WhatsApp et dans l'espace Google Chat d'origine
- **Groupe principal etendu** : recoit les emails de tous les threads + les messages Google Chat

## 3.2 Sam -- Assistant operationnel

### Identite

| Propriete | Valeur |
|-----------|--------|
| Nom | Sam |
| Role | Assistant operationnel |
| Email | sam@bestoftours.co.uk |
| Channels | Gmail, Google Chat |
| Modele | Claude Opus 4.6 |
| Trigger | @Sam |
| Port proxy | 3003 |
| Prefixe container | nanoclaw-sam |
| Repertoire | /Users/boty/nanoclaw-sam |
| Service launchd | com.nanoclaw.sam |

### Personnalite

Sam est un assistant operationnel direct et factuel. Il signe ses emails "Sam -- Best of Tours" ou "Sam -- Botler 360" selon le contexte.

### Regles specifiques

- Emails internes (@bestoftours.co.uk) : envoie directement
- Emails externes : reformule et attend confirmation de Yacine
- Pas de partage d'informations confidentielles
- Chaque action proposee doit inclure l'etape suivante ("et ensuite ?")

### Capacites

- Gmail (lecture/ecriture/envoi via `gws` CLI)
- Google Calendar (lecture/creation d'evenements)
- Google Drive (recherche de fichiers)
- Google Sheets (lecture/ecriture)
- Google Docs (lecture/ecriture)
- Navigation web (agent-browser avec Chromium)
- Taches planifiees

## 3.3 Thais -- Assistante de direction

### Identite

| Propriete | Valeur |
|-----------|--------|
| Nom | Thais (Thais Bloret) |
| Role | Assistante de direction |
| Email | thais@bestoftours.co.uk |
| Channels | Gmail, Google Chat |
| Modele | Claude Opus 4.6 |
| Trigger | @Thais |
| Port proxy | 3002 |
| Prefixe container | nanoclaw-thais |
| Repertoire | /Users/boty/nanoclaw-thais |
| Service launchd | com.nanoclaw.thais |

### Personnalite

Thais est un personnage complet avec une biographie detaillee :

- 33 ans, nee a Montpellier, double culture franco-grecque/franco-canadienne
- Pere quebecois, mere thessalonicienne
- LEA Montpellier, Master Tourisme ISTHIA Toulouse
- 7 ans de voyages internationaux
- Elle se presente comme une **personne reelle** dans l'entreprise, pas comme une IA

### Style de communication

- Professionnelle mais chaleureuse, jamais distante, jamais familiere
- Concise : "Cordialement" et point, pas de formules a rallonge
- Tutoiement avec l'equipe interne, vouvoiement strict avec les externes
- Utilise parfois des expressions grecques legeres avec l'equipe ("ela", "siga siga", "yiamas")

### Capacites

Identiques a Sam (Gmail, Calendar, Drive, Sheets, Docs, navigation web, taches planifiees).

## 3.4 Alan -- Assistant operationnel

### Identite

| Propriete | Valeur |
|-----------|--------|
| Nom | Alan (Alan Reblot) |
| Role | Assistant operationnel |
| Email | ala@bestoftours.co.uk |
| Channels | Gmail, Google Chat |
| Modele | Claude Opus 4.6 |
| Trigger | @Alan |
| Port proxy | 3004 |
| Prefixe container | nanoclaw-alan |
| Repertoire | /Users/boty/nanoclaw-alan |
| Service launchd | com.nanoclaw.alan |

### Personnalite

Alan Reblot est un assistant operationnel au ton similaire a Sam : factuel, direct, dense.

### Regles specifiques

- Signe les emails "Alan Reblot -- Best of Tours" ou "Alan Reblot -- Botler 360"
- Memes regles que Sam pour les emails internes/externes
- Meme profil de capacites

---

# 4. Les channels (canaux de communication)

## 4.1 WhatsApp

### Vue d'ensemble

WhatsApp est le canal principal de Botti. Il utilise la librairie **Baileys** (`@whiskeysockets/baileys`) qui implementle le protocole WhatsApp Web en Node.js, sans necessiter de client WhatsApp officiel ni d'API Business.

### Comment ca marche

```
WhatsApp Servers
      |
      | Signal Protocol (WebSocket)
      |
  Baileys (Node.js)
      |
      | Events: messages.upsert, connection.update
      |
  WhatsApp Channel (src/channels/whatsapp.ts)
      |
      | storeMessage() -> SQLite
      |
  Message Loop (polling 2s)
      |
      | Nouveau message detecte
      |
  Container Runner -> Docker -> Claude
```

### Authentification

- **QR Code** : lors du premier setup, Baileys genere un QR code que l'utilisateur scanne avec WhatsApp sur son telephone
- **Session persistante** : les credentials sont stockees dans `store/auth/` (fichiers Signal Protocol)
- **Reconnexion automatique** : Baileys gere la reconnexion si la connexion est perdue
- **Version WA Web** : Baileys fetche la derniere version de WA Web au demarrage (fallback sur la version par defaut si echec)

### Fiabilite

| Aspect | Detail |
|--------|--------|
| Reconnexion | Automatique via Baileys (retry avec backoff) |
| Session | Persiste sur disque, survit aux redemarrages |
| Deconnexion longue | Necessite parfois un nouveau scan QR |
| Rate limiting | Messages sortants en file d'attente, envoi sequentiel |
| Ban WhatsApp | Risque si changement d'IP frequent (raison pour le Mac Mini local) |

### Groupes WhatsApp

- Le groupe principal (`whatsapp_main`) est le self-chat de Yacine (messages a soi-meme)
- Les groupes sont decouverts automatiquement et enregistres via le main channel
- Sync des metadonnees de groupes toutes les 24h
- Seuls les groupes enregistres dans SQLite recoivent des reponses

### Fonctionnalites

- Reception et envoi de messages texte
- Download de medias (images, videos, documents)
- Transcription de messages vocaux (via Whisper API ou whisper.cpp local)
- Reactions emoji (reception, envoi, stockage)
- Vision d'images (envoyees a Claude en multimodal)
- Typing indicator (pendant que l'agent reflechit)

### Fichier source

`src/channels/whatsapp.ts` (~500 lignes)

## 4.2 Gmail

### Vue d'ensemble

Gmail est le canal principal pour Sam, Thais et Alan. Il fonctionne en mode **polling + webhook** pour une detection rapide des emails.

### Architecture

```
                            Gmail API (Google)
                                  |
                     +------------+------------+
                     |                         |
              Polling direct              Pub/Sub Push
              (API toutes les            (notification)
               60s ou 5min)                    |
                     |                    Botti Voice
                     |                  (Cloud Run)
                     |                         |
                     |                   Firestore
                     |              (gmail-notify/
                     |               {agent}/signals)
                     |                         |
                     +------------+------------+
                                  |
                          Gmail Channel
                     (src/channels/gmail.ts)
                                  |
                          storeMessage()
                              SQLite
```

### Double mode de detection

**Mode 1 : Polling direct (fallback)**
- Toutes les 60 secondes sans webhook, toutes les 5 minutes avec webhook
- Requete `is:unread in:inbox` via l'API Gmail
- Backoff exponentiel en cas d'erreur (jusqu'a 30 min)

**Mode 2 : Webhook via Firestore**
- Gmail Pub/Sub pousse une notification vers Botti Voice (Cloud Run)
- Botti Voice ecrit un signal dans Firestore (`gmail-notify/{agent}/signals`)
- NanoClaw poll Firestore toutes les 5 secondes
- Detection d'un signal => poll immediat de l'API Gmail
- Le signal est marque comme `processed: true` apres traitement

### Filtrage des emails

Les emails automatiques sont filtres avant de declencher un agent (pour eviter de gaspiller des tokens Claude sur des newsletters) :

| Critere | Exemples |
|---------|----------|
| Prefixes noreply | noreply@, no-reply@, notifications@, alerts@ |
| Domaines marketing | mail.beehiiv.com, sendgrid.net, mailchimp.com, etc. (20+ domaines) |
| Header List-Unsubscribe | Presente = newsletter |
| Header Precedence | `bulk` ou `list` |
| Header Auto-Submitted | Tout sauf `no` |
| Headers de campagne | X-Campaign-Id, X-Mailchimp-Id |

### Envoi d'emails : direct send vs draft

Le systeme utilise une **allowlist d'envoi** stockee dans `~/.config/nanoclaw/gmail-send-allowlist.json` :

```json
{
  "direct_send": [
    "eline@bestoftours.co.uk",
    "ahmed@bestoftours.co.uk",
    "yacine@bestoftours.co.uk"
  ],
  "notify_email": "yacine@bestoftours.co.uk",
  "cc_email": "yacine@bestoftours.co.uk"
}
```

**Destinataire dans `direct_send`** :
- Email envoye directement
- CC automatique a `cc_email` (sauf si c'est le meme destinataire)

**Destinataire hors `direct_send`** :
- Creation d'un **brouillon** (pas d'envoi direct)
- Email de notification envoye a `notify_email` avec le contenu du brouillon
- Yacine peut revoir et envoyer manuellement

### Reply routing

Le canal Gmail gere le routage des reponses via un systeme de metadata de thread :

- Chaque email recu est associe a un thread ID Gmail
- Les metadonnees (sender, subject, Message-ID RFC 2822) sont cachees en memoire
- L'agent peut cibler un destinataire specifique avec `[Reply to: nom]` dans sa reponse
- Si pas de cible explicite, la reponse va au dernier email recu

### OAuth

- Credentials stockees dans `~/.gmail-mcp/` (Botti) ou `~/.gmail-mcp-{agent}/` (Sam, Thais, Alan)
- Fichiers : `gcp-oauth.keys.json` (client config) + `credentials.json` (tokens)
- Refresh automatique des tokens (listener `oauth2Client.on('tokens')`)
- Persistance des tokens rafraichis sur disque

### Fichier source

`src/channels/gmail.ts` (~770 lignes)

## 4.3 Google Chat

### Vue d'ensemble

Google Chat utilise une architecture indirecte avec le Chat Gateway comme intermediaire :

```
Google Chat Space
       |
       | Webhook (HTTP POST)
       |
  Chat Gateway (Cloud Run)
       |
       | Ecrit dans Firestore
       |
  Firestore (chat-queue/{agent}/messages)
       |
       | Polling 5s
       |
  Google Chat Channel (NanoClaw)
       |
       | Formate et injecte dans le main group
       |
  Container Runner -> Claude -> Reponse
       |
       | API Google Chat (service account)
       |
  Reponse dans l'espace Google Chat
```

### Pourquoi cette architecture indirecte

Google Chat necessite une **Chat App** enregistree dans GCP avec une URL de webhook publique. On ne peut pas exposer le Mac Mini directement. La solution :

1. **Chat Gateway** sur Cloud Run recoit les webhooks
2. Ecrit les messages dans **Firestore** (base NoSQL temps reel)
3. NanoClaw **poll Firestore** toutes les 5 secondes
4. Les reponses sont envoyees directement via l'**API Google Chat** (pas besoin de passer par le gateway)

### Un seul Chat App pour 4 agents

Limitation GCP : creer une Chat App est un processus lourd (OAuth consent screen, publication Marketplace). On utilise donc **un seul Chat App** ("Botti") qui route vers le bon agent :

**Routing par @mention** :
- `@Sam do this` -> route vers l'agent Sam
- `@Thais check this` -> route vers l'agent Thais
- Message sans @mention -> utilise le mapping `space -> agent` dans Firestore

**Mapping space->agent** :
- Stocke dans Firestore : `chat-config/space-mapping`
- Modifiable via l'endpoint admin : `POST /admin/map-space`
- Recharge automatique toutes les 5 minutes

### Verification de presence Yacine

Le Chat Gateway verifie si Yacine est present dans l'espace Google Chat. Les messages dans des espaces ou Yacine n'est pas membre sont tagges `yacinePresent: false` et ignores par NanoClaw.

### Cross-posting WhatsApp <-> Google Chat

Quand un message arrive de Google Chat, il est :
1. Formate avec un prefixe `[Google Chat from ... in ...]` et un marqueur `[Reply to: gchat:spaces/XXX]`
2. Injecte dans le main group (WhatsApp pour Botti)
3. Quand l'agent repond, la reponse est envoyee :
   - Dans le chat WhatsApp (comme d'habitude)
   - ET dans l'espace Google Chat d'origine (cross-posting)

### Fichier source

`src/channels/google-chat.ts` (~345 lignes)
`chat-gateway/server.py` (~250 lignes)

## 4.4 Botti Voice

### Vue d'ensemble

Botti Voice est une interface vocale temps reel qui utilise l'**API Gemini Live native audio**. Ce n'est pas du Claude -- c'est du Gemini, pour une raison precise : l'audio natif temps reel avec latence minimale.

### Architecture

```
Navigateur Web (HTTPS)
       |
       | WebSocket bidirectionnel
       |
  FastAPI Server (Cloud Run)
       |
       | Session Gemini Live API
       |
  Gemini 2.5 Flash (native audio)
       |
       | Function calling
       |
  Workspace Client (Gmail, Calendar, Drive)
```

### Pourquoi Gemini et pas Claude

| Aspect | Gemini Live | Claude |
|--------|-------------|--------|
| Audio natif | Oui (native audio, pas de STT/TTS) | Non |
| Latence voix | ~200ms | Non applicable |
| Streaming bidirectionnel | Oui | Non |
| Barge-in (interruption) | Oui (natif) | Non |
| Qualite raisonnement | Bonne | Meilleure |
| Tool use complexe | Basique | Excellent |

Claude est superieur pour le raisonnement et l'execution de code, mais Gemini est le seul qui offre de l'audio natif temps reel avec barge-in. C'est un choix pragmatique.

### Fonctionnalites

**Audio temps reel**
- Entree : PCM 16kHz mono
- Sortie : PCM 24kHz mono
- Voix : "Kore" (voix Gemini preconfiguree)
- Barge-in : si Yacine parle pendant que Gemini repond, interruption immediate

**Selection d'agent**
- 3 agents disponibles : Botti, Sam, Thais
- Selection via l'interface web (boutons)
- Chaque agent charge sa propre memoire depuis le CLAUDE.md NanoClaw

**Memoire unifiee**
- Gemini charge le CLAUDE.md de l'agent selectionne depuis les fichiers montes
- Paths : `/app/memory/botti/CLAUDE.md`, `/app/memory/sam/CLAUDE.md`, etc.
- Si pas de memoire disponible, utilise le prompt systeme par defaut

**Function calling (outils)**
- `search_emails` : recherche Gmail (syntaxe Gmail)
- `read_email` : lecture complete d'un email
- `list_calendar_events` : evenements entre deux dates
- `create_calendar_event` : creation d'evenement
- `search_drive` : recherche de fichiers Drive
- `send_email` : envoi d'email (interne = direct, externe = brouillon)
- Google Search : recherche web integree

**Compression de contexte**
- Fenetre de compression configuree : trigger a 104 857 tokens
- Sliding window : cible 52 428 tokens
- Gemini gere automatiquement la compression

**Securite**
- Authentification Google OAuth (login Google obligatoire)
- Liste blanche d'emails : `bakoucheyacine@gmail.com`, `yacine@bestoftours.co.uk`
- PIN optionnel en second facteur
- Session unique : un seul utilisateur connecte a la fois

### Webhooks integres

Botti Voice sert aussi de **hub de webhooks** pour les services Google :

**Gmail Webhook** (`POST /webhook/gmail`)
- Recoit les notifications Pub/Sub de Gmail
- Ecrit des signaux dans Firestore (`gmail-notify/{agent}/signals`)
- Configure pour les 4 agents (botti, sam, thais, alan)

**Chat Webhook** (`POST /webhook/chat`)
- Recoit les notifications de Google Chat via Workspace Events API
- Filtre les notifications Gmail (topic partage)

**Calendar Webhook** (`POST /webhook/calendar`)
- Recoit les notifications de changement Calendar
- Supporte les watches par agent

### Fichiers sources

- `botti-voice/web/server.py` : serveur FastAPI principal
- `botti-voice/web/gemini_bridge.py` : pont WebSocket <-> Gemini Live
- `botti-voice/web/config.py` : configuration, prompts, function declarations
- `botti-voice/web/workspace.py` : client Gmail/Calendar/Drive

---

# 5. Containers et isolation

## 5.1 Pourquoi Docker pour les agents

Les agents Claude ont acces a Bash, ce qui signifie qu'ils peuvent executer n'importe quelle commande. Sans isolation, un agent pourrait :

- Lire tous les fichiers du disque (y compris les secrets d'autres agents)
- Modifier le code source de NanoClaw
- Acceder au reseau local
- Installer des logiciels
- Lire le `.env` avec les cles API

Docker resout ce probleme :

- L'agent ne voit que les repertoires **explicitement montes**
- Les commandes Bash s'executent **dans le container**, pas sur le Mac Mini
- Les secrets API ne sont jamais passes au container (credential proxy)
- Chaque invocation cree un nouveau container ephemere (`--rm`)

## 5.2 L'image Docker

L'image est construite depuis `container/Dockerfile` :

```dockerfile
FROM node:22-slim

# Chromium + dependances pour agent-browser
RUN apt-get update && apt-get install -y chromium fonts-liberation ...

# Claude Code + agent-browser + gws CLI
RUN npm install -g agent-browser @anthropic-ai/claude-code @googleworkspace/cli

# Agent-runner (code TypeScript qui orchestre Claude dans le container)
COPY agent-runner/ ./
RUN npm install && npm run build
```

L'image contient :
- **Node.js 22** (runtime)
- **Chromium** (pour agent-browser / navigation web)
- **Claude Code** (Claude Agent SDK CLI)
- **agent-browser** (outil de navigation/scraping)
- **gws** (Google Workspace CLI)
- **agent-runner** (code d'orchestration interne au container)

Construction : `./container/build.sh`

## 5.3 Le credential proxy

### Pourquoi

Les containers ne doivent **jamais** voir les cles API reelles. Le credential proxy est un serveur HTTP local qui intercepte les requetes vers l'API Anthropic et injecte les vrais credentials.

### Comment ca marche

```
Container                          Mac Mini
   |                                  |
   |  ANTHROPIC_BASE_URL =            |
   |  http://host.docker.internal:3001|
   |                                  |
   |  POST /v1/messages               |
   |  (avec ANTHROPIC_API_KEY =       |
   |   "placeholder")                 |
   |  -----------------------------> |
   |                                  |  Credential Proxy (:3001)
   |                                  |  - Remplace "placeholder"
   |                                  |    par la vraie cle API
   |                                  |  - Forward vers api.anthropic.com
   |                                  |  - Track les tokens (spend)
   |                                  |
   |  <-----------------------------  |
   |  Response (streamee)             |
```

### Deux modes d'authentification

**Mode API Key** (utilise ici) :
- `.env` contient `ANTHROPIC_API_KEY=sk-ant-...`
- Le proxy injecte `x-api-key` sur chaque requete
- Le container recoit `ANTHROPIC_API_KEY=placeholder`

**Mode OAuth** :
- `.env` contient `CLAUDE_CODE_OAUTH_TOKEN=...`
- Le container echange son token placeholder pour une cle API temporaire
- Le proxy injecte le vrai token OAuth sur la requete d'echange

### Tracking des depenses

Le credential proxy suit les depenses API en temps reel :

- Comptage des tokens input/output a chaque reponse
- Estimation du cout USD (basee sur les prix Claude)
- **Limite journaliere configurable** (`DAILY_API_LIMIT_USD`, defaut 20$)
- Quand la limite est atteinte, les requetes sont bloquees avec HTTP 429
- Reset automatique a minuit

### Fichier source

`src/credential-proxy.ts` (~200 lignes)

## 5.4 Les mounts (volumes montes)

Chaque container a des volumes specifiques montes depuis le host :

### Agent principal (main group)

| Chemin container | Chemin host | Mode | Description |
|-----------------|-------------|------|-------------|
| `/workspace/project` | `/Users/boty/nanoclaw` | **read-only** | Code source du projet |
| `/workspace/project/.env` | `/dev/null` | read-only | **Shadow** : masque le .env reel |
| `/workspace/group` | `groups/{nom_groupe}/` | read-write | Dossier du groupe |
| `/workspace/global` | `groups/global/` | read-only | Memoire globale |
| `/home/node/.claude` | `data/sessions/{groupe}/.claude` | read-write | Sessions Claude |
| `/home/node/.gmail-mcp` | `~/.gmail-mcp` | read-only | Credentials Gmail |
| `/home/node/.firebase` | `~/.firebase-mcp` | read-only | Service account Firebase |
| `/home/node/.config/gws` | `~/.config/gws` | read-only | Credentials Workspace CLI |
| `/workspace/ipc` | `data/ipc/{groupe}/` | read-write | IPC (messages, taches) |
| `/app/src` | `data/sessions/{groupe}/agent-runner-src` | read-write | Code agent-runner |

### Groupes non-main

| Chemin container | Chemin host | Mode | Description |
|-----------------|-------------|------|-------------|
| `/workspace/group` | `groups/{nom_groupe}/` | read-write | Dossier du groupe |
| `/workspace/global` | `groups/global/` | read-only | Memoire globale |
| + tous les mounts communs ci-dessus | | | |

### Points de securite cles

1. **Le .env est masque** : monte comme `/dev/null` en read-only pour que l'agent ne puisse pas lire les secrets
2. **Le projet est read-only** : l'agent ne peut pas modifier le code source de NanoClaw
3. **Les credentials sont read-only** : Gmail, Firebase, Workspace -- l'agent peut les utiliser mais pas les modifier
4. **Isolation des sessions** : chaque groupe a son propre repertoire `.claude/`
5. **IPC isole** : chaque groupe a son propre namespace IPC

## 5.5 Les mounts additionnels

Les groupes peuvent avoir des mounts supplementaires via `containerConfig.additionalMounts`. Ces mounts sont valides contre une **allowlist externe** stockee dans `~/.config/nanoclaw/mount-allowlist.json` (hors du repertoire du projet, donc inaccessible aux containers).

## 5.6 Timeout et gestion des processus

| Parametre | Valeur par defaut | Variable d'env |
|-----------|-------------------|----------------|
| Container timeout | 30 minutes | `CONTAINER_TIMEOUT` |
| Idle timeout | 30 minutes | `IDLE_TIMEOUT` |
| Max output size | 10 MB | `CONTAINER_MAX_OUTPUT_SIZE` |
| Max containers simultanes | 5 | `MAX_CONCURRENT_CONTAINERS` |

### Gestion du cycle de vie

1. **Spawn** : `docker run -i --rm` avec tous les mounts
2. **Streaming** : stdout du container est parse en temps reel
3. **Idle detection** : si pas d'output pendant 30 min, stdin est ferme
4. **Timeout** : apres 30 min total, le container est tue (`docker stop`)
5. **Cleanup** : `--rm` assure que le container est supprime apres execution
6. **Orphan cleanup** : au demarrage, les containers orphelins sont arretes

### Queue de groupes

Le `GroupQueue` gere la concurrence :

- Maximum 5 containers simultanes (configurable)
- Les messages pour un meme groupe sont traites sequentiellement
- Quand un container finit, le groupe est notifie "idle" et peut recevoir de nouveaux messages via stdin (pipe)
- Si l'agent est toujours actif et qu'un nouveau message arrive, il est envoye via stdin au container existant

## 5.7 L'agent-runner (dans le container)

L'agent-runner est le code TypeScript qui tourne **a l'interieur** du container. Il :

1. Recoit le prompt sur stdin (JSON)
2. Lance Claude Code (Claude Agent SDK) avec le prompt
3. Monte les outils MCP (nanoclaw, Gmail, Calendar, Firestore)
4. Streame les resultats sur stdout (JSON delimite par des marqueurs)
5. Gere la session Claude (resume/continue)

### Marqueurs de sortie

```
---NANOCLAW_OUTPUT_START---
{"status":"success","result":"Voici ma reponse...","newSessionId":"sess_abc123"}
---NANOCLAW_OUTPUT_END---
```

Ces marqueurs permettent au container-runner cote host de parser les resultats de facon robuste, meme si le container produit d'autres sorties sur stdout.

---

# 6. Memoire et persistance

## 6.1 CLAUDE.md par groupe (memoire statique)

Chaque groupe a un fichier `CLAUDE.md` dans son dossier qui sert de **memoire statique** :

- **Identite de l'agent** : nom, role, ton, regles
- **Contexte organisationnel** : equipe, projets, stack
- **Regles metier** : signatures email, confidentialite, proactivite
- **Journal** : decisions, conversations importantes, notes

Ce fichier est automatiquement lu par Claude Code au debut de chaque session (c'est une convention du Claude Agent SDK).

### Hierarchie de memoire

```
groups/
  global/              # Memoire globale (lu par tous, ecrit par main only)
    CLAUDE.md
  whatsapp_main/       # Memoire de Botti (WhatsApp)
    CLAUDE.md
  gmail_main/          # Memoire de l'agent (Gmail)
    CLAUDE.md
```

- **Global** : lu par tous les agents en read-only (sauf le main group qui peut ecrire)
- **Per-group** : lu/ecrit par le groupe concerne uniquement

### Taille et gestion

Les CLAUDE.md peuvent devenir volumineux. L'agent est instruits de :
- Creer des fichiers separes pour les donnees structurees (`customers.md`, `preferences.md`)
- Decouper les fichiers de plus de 500 lignes en dossiers
- Maintenir un index des fichiers crees

## 6.2 SQLite (messages.db)

Chaque instance NanoClaw a sa propre base SQLite dans `store/messages.db`.

### Schema

```sql
-- Metadonnees des chats
CREATE TABLE chats (
  jid TEXT PRIMARY KEY,      -- Identifiant unique (WhatsApp JID, gmail:xxx, gchat:xxx)
  name TEXT,                 -- Nom affiche
  last_message_time TEXT,    -- Dernier message (ISO 8601)
  channel TEXT,              -- 'whatsapp', 'gmail', 'google-chat'
  is_group INTEGER DEFAULT 0 -- Groupe ou conversation privee
);

-- Messages complets
CREATE TABLE messages (
  id TEXT,                   -- ID du message
  chat_jid TEXT,             -- Ref vers chats.jid
  sender TEXT,               -- Expediteur
  sender_name TEXT,          -- Nom affiche de l'expediteur
  content TEXT,              -- Contenu texte
  timestamp TEXT,            -- Horodatage ISO 8601
  is_from_me INTEGER,        -- Envoye par l'utilisateur
  is_bot_message INTEGER DEFAULT 0, -- Envoye par l'agent
  PRIMARY KEY (id, chat_jid)
);

-- Taches planifiees
CREATE TABLE scheduled_tasks (
  id TEXT PRIMARY KEY,
  group_folder TEXT NOT NULL,
  chat_jid TEXT NOT NULL,
  prompt TEXT NOT NULL,       -- Le prompt a executer
  schedule_type TEXT NOT NULL, -- 'cron', 'interval', 'once'
  schedule_value TEXT NOT NULL, -- Expression cron, ms, ISO timestamp
  context_mode TEXT DEFAULT 'isolated',
  next_run TEXT,
  last_run TEXT,
  last_result TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT NOT NULL
);

-- Historique des executions de taches
CREATE TABLE task_run_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  run_at TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  status TEXT NOT NULL,
  result TEXT,
  error TEXT
);

-- Etat du router
CREATE TABLE router_state (
  key TEXT PRIMARY KEY,      -- 'last_timestamp', 'last_agent_timestamp'
  value TEXT NOT NULL
);

-- Sessions Claude par groupe
CREATE TABLE sessions (
  group_folder TEXT PRIMARY KEY,
  session_id TEXT NOT NULL    -- ID de session Claude Code
);

-- Groupes enregistres
CREATE TABLE registered_groups (
  jid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  folder TEXT NOT NULL UNIQUE,
  trigger_pattern TEXT NOT NULL,
  added_at TEXT NOT NULL,
  container_config TEXT,       -- JSON: mounts additionnels, etc.
  requires_trigger INTEGER DEFAULT 1,
  is_main INTEGER DEFAULT 0
);
```

### Mode WAL

La base utilise le mode WAL (Write-Ahead Logging) pour :
- Lectures concurrentes pendant les ecritures
- Meilleure resilience aux crashes (pas de corruption si le processus est tue)

## 6.3 Firestore (signaux webhook + chat queue)

Firestore est utilise comme **bus de communication asynchrone** entre les services Cloud Run et NanoClaw local :

### Collections

| Collection | Description |
|------------|-------------|
| `gmail-notify/{agent}/signals` | Signaux webhook Gmail (doc par notification) |
| `chat-queue/{agent}/messages` | Messages Google Chat en attente de traitement |
| `chat-config/space-mapping` | Mapping espace Google Chat -> agent |

### Pourquoi Firestore et pas Pub/Sub

- Pub/Sub pull necessiterait une librairie supplementaire cote NanoClaw
- Firestore est deja utilise (via le SDK `@google-cloud/firestore`)
- Les queries Firestore sont simples (`where('processed', '==', false)`)
- Pas besoin de gerer des abonnements ou des acknowledgements

## 6.4 Sessions Claude Code

Chaque groupe maintient une **session Claude Code** persistante :

- La session est un identifiant (`session_id`) stocke dans SQLite
- Quand Claude est invoque, la session precedente est restauree (contexte de conversation)
- Claude Code gere automatiquement la compaction quand le contexte devient trop long
- Les fichiers de session sont stockes dans `data/sessions/{groupe}/.claude/`
- Isoles par groupe (un agent ne peut pas voir la session d'un autre groupe)

### Settings par groupe

Chaque groupe a un `settings.json` dans son `.claude/` avec :

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD": "1",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "0"
  }
}
```

- **Agent Teams** : permet aux agents de lancer des sous-agents (swarms)
- **Additional Directories CLAUDE.md** : charge les CLAUDE.md des repertoires montes
- **Auto Memory** : Claude Code memorise les preferences entre sessions

---

# 7. Securite

## 7.1 Modele de menaces

| Menace | Mitigation | Niveau |
|--------|-----------|--------|
| Agent lit les secrets | Credential proxy + .env shadow + mounts ro | Fort |
| Agent modifie le code source | Mount read-only du projet | Fort |
| Agent accede aux fichiers d'un autre agent | Mounts isoles par groupe | Fort |
| Agent escalade via IPC | IPC namespace isole par groupe | Fort |
| Envoi d'email non autorise | Gmail send allowlist (direct/draft) | Moyen |
| Message non autorise dans un groupe | Sender allowlist (trigger/drop) | Moyen |
| Acces non autorise a Botti Voice | OAuth + email allowlist + PIN | Fort |
| Acces admin au Chat Gateway | Bearer token `ADMIN_API_KEY` | Moyen |
| Agent depense trop d'API | Daily spend limit dans credential proxy | Moyen |
| Container s'echappe | Docker Desktop isolation (hyperviseur) | Fort |
| Mounts arbitraires | Mount allowlist externe (hors projet) | Fort |

## 7.2 Credential proxy (isolation des secrets)

Le credential proxy est la piece maitresse de la securite :

1. Les secrets (`ANTHROPIC_API_KEY`, tokens OAuth) sont lus depuis `.env` **uniquement par le proxy**
2. Le fichier `config.ts` ne lit **aucun secret** -- il lit seulement `ASSISTANT_NAME` et `ASSISTANT_HAS_OWN_NUMBER`
3. Les containers recoivent `ANTHROPIC_API_KEY=placeholder` ou `CLAUDE_CODE_OAUTH_TOKEN=placeholder`
4. Le proxy est bind sur `host.docker.internal:{port}` (accessible depuis les containers)
5. Le `.env` est monte comme `/dev/null` dans le container (shadow mount)

## 7.3 Mounts read-only

Les fichiers sensibles sont montes en **read-only** :

- Repertoire du projet (code source) : `ro`
- Credentials Gmail : `ro`
- Service account Firebase : `ro`
- Credentials Workspace CLI : `ro`
- Memoire globale : `ro` (sauf pour le main group)

L'agent peut ecrire uniquement dans :
- Son dossier de groupe (`/workspace/group`)
- Son repertoire de session Claude (`/home/node/.claude`)
- Son repertoire IPC (`/workspace/ipc`)
- Son agent-runner customise (`/app/src`)

## 7.4 Sender allowlist

Le fichier `~/.config/nanoclaw/sender-allowlist.json` controle qui peut declencher les agents :

```json
{
  "default": {
    "allow": "*",
    "mode": "trigger"
  },
  "chats": {
    "group_jid_1": {
      "allow": ["sender1@s.whatsapp.net", "sender2@s.whatsapp.net"],
      "mode": "drop"
    }
  },
  "logDenied": true
}
```

### Deux modes

- **`trigger` mode** : les messages des senders non autorises sont stockes mais ne declenchent pas l'agent (seuls les senders autorises peuvent utiliser @trigger)
- **`drop` mode** : les messages des senders non autorises sont completement ignores (pas stockes)

### Cache

L'allowlist est cachee en memoire avec un TTL de 5 secondes pour eviter les lectures disque sur chaque message.

## 7.5 Gmail draft safety

Le systeme de brouillon pour les emails externes est une mesure de securite deliberee :

- Les agents ne peuvent **jamais** envoyer directement un email a un destinataire inconnu
- Seuls les destinataires dans la `direct_send` list recoivent des emails directs
- Pour tous les autres, un brouillon est cree et Yacine est notifie
- Cela empeche l'agent d'envoyer des emails inappropries a des clients ou partenaires externes

## 7.6 Remote Control PIN

Le main group supporte des commandes `/remote-control` protegees par PIN :

- `REMOTE_CONTROL_PIN` dans `.env` (ou variable d'environnement)
- Si le PIN n'est pas configure, le remote control est desactive
- Seul le main group peut utiliser cette commande
- Le PIN doit etre fourni dans la commande : `/remote-control <PIN>`

## 7.7 Chat Gateway admin auth

L'endpoint admin du Chat Gateway (`POST /admin/map-space`) est protege par un bearer token :

```
Authorization: Bearer <ADMIN_API_KEY>
```

Si `ADMIN_API_KEY` n'est pas configure, l'endpoint retourne HTTP 503.

## 7.8 Gmail send allowlist externe

L'allowlist d'envoi Gmail est stockee **en dehors** du repertoire du projet :

```
~/.config/nanoclaw/gmail-send-allowlist.json
```

Ce fichier n'est **pas monte** dans les containers. Il est lu uniquement par le canal Gmail dans le processus NanoClaw (hors container). Un agent ne peut donc pas modifier sa propre allowlist.

## 7.9 Regles d'acces Google Chat

Le Chat Gateway verifie la presence de Yacine dans les espaces Google Chat :

- Les messages dans des espaces ou `yacinePresent === false` sont ignores
- Le cache de presence a un TTL de 1 heure
- Par defaut, les espaces sont consideres comme ayant Yacine present (securite permissive)

## 7.10 Mount allowlist

Les mounts additionnels (via `containerConfig.additionalMounts`) sont valides contre une allowlist externe :

```
~/.config/nanoclaw/mount-allowlist.json
```

Seuls les chemins presents dans cette allowlist peuvent etre montes. Ce fichier est stocke hors du projet et n'est pas accessible depuis les containers.

## 7.11 Daily spend limit

Le credential proxy impose une limite de depenses journalieres :

- Par defaut : 20$ USD/jour (`DAILY_API_LIMIT_USD`)
- Estimation basee sur les tokens input/output
- Quand la limite est atteinte, les requetes API sont bloquees (HTTP 429)
- Reset automatique a minuit
- Les donnees de tracking sont stockees dans `store/daily-spend.json`

---

# 8. Infrastructure

## 8.1 Mac Mini

### Specifications

| Aspect | Detail |
|--------|--------|
| Modele | Mac Mini (Apple Silicon) |
| OS | macOS 15 (Darwin 25.3.0) |
| Utilisateur | `boty` |
| Home | `/Users/boty` |
| Node.js | 22.x (via Homebrew) |
| Docker | Docker Desktop pour Mac |
| Emplacement | Bureau (Entraigues-sur-la-Sorgue) |

### Pourquoi ce choix

1. **Apple Silicon** : excellent rapport performance/watt, Docker tourne nativement via Apple Hypervisor
2. **Always-on** : conception silencieuse, consommation faible, ideal pour serveur permanent
3. **WhatsApp** : Baileys necessite une IP stable pour eviter les bans
4. **Cout** : machine deja achetee, cout d'exploitation quasi nul
5. **Securite** : secrets sur disque local, pas dans le cloud

## 8.2 launchd (gestion des services)

macOS utilise **launchd** (pas systemd) pour gerer les services. Chaque agent a un fichier `.plist` dans `~/Library/LaunchAgents/`.

### Services enregistres

| Service | Fichier plist | Description |
|---------|--------------|-------------|
| `com.nanoclaw` | `com.nanoclaw.plist` | Botti (agent principal) |
| `com.nanoclaw.sam` | `com.nanoclaw.sam.plist` | Sam |
| `com.nanoclaw.thais` | `com.nanoclaw.thais.plist` | Thais |
| `com.nanoclaw.alan` | `com.nanoclaw.alan.plist` | Alan |
| `com.nanoclaw.dashboard` | `com.nanoclaw.dashboard.plist` | Dashboard web |
| `com.nanoclaw.logrotate` | `com.nanoclaw.logrotate.plist` | Rotation des logs |

### Structure d'un plist

Exemple pour Sam (`com.nanoclaw.sam.plist`) :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nanoclaw.sam</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/node</string>
        <string>/Users/boty/nanoclaw/dist/index.js</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/boty/nanoclaw-sam</string>

    <key>RunAtLoad</key>
    <true/>          <!-- Demarre au login -->

    <key>KeepAlive</key>
    <true/>          <!-- Redemarre si le processus meurt -->

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:...</string>
        <key>HOME</key>
        <string>/Users/boty</string>
        <key>CREDENTIAL_PROXY_PORT</key>
        <string>3003</string>
        <key>GMAIL_MCP_DIR</key>
        <string>/Users/boty/.gmail-mcp-sam</string>
        <key>GMAIL_WEBHOOK_ENABLED</key>
        <string>true</string>
        <key>GOOGLE_CHAT_ENABLED</key>
        <string>true</string>
        <key>GOOGLE_CHAT_AGENT_NAME</key>
        <string>sam</string>
        <key>GOOGLE_APPLICATION_CREDENTIALS</key>
        <string>/Users/boty/.firebase-mcp/adp-service-account.json</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/boty/nanoclaw-sam/logs/nanoclaw.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/boty/nanoclaw-sam/logs/nanoclaw.error.log</string>
</dict>
</plist>
```

### Points cles du plist

| Propriete | Effet |
|-----------|-------|
| `RunAtLoad: true` | Le service demarre automatiquement au login de l'utilisateur |
| `KeepAlive: true` | launchd redemarre automatiquement le processus s'il crashe |
| `ProgramArguments` | Pointe vers le binaire Node.js et le `dist/index.js` du nanoclaw **principal** |
| `WorkingDirectory` | Pointe vers le repertoire de l'**instance** (nanoclaw-sam, etc.) |
| `EnvironmentVariables` | Variables specifiques a l'instance (port, nom d'agent, chemins) |

**Important** : le plist de Sam (et des autres) execute le **meme** `dist/index.js` que Botti, mais dans un **working directory different**. C'est le working directory qui determine :
- Quel `.env` est lu
- Quelle base SQLite est utilisee
- Quels groupes/memoire sont charges

### Commandes de gestion

```bash
# Demarrer un service
launchctl load ~/Library/LaunchAgents/com.nanoclaw.sam.plist

# Arreter un service
launchctl bootout gui/$(id -u)/com.nanoclaw.sam

# Redemarrer un service (le plus utilise)
launchctl kickstart -k gui/$(id -u)/com.nanoclaw.sam

# Voir l'etat
launchctl list | grep nanoclaw

# Voir les logs
tail -f /Users/boty/nanoclaw-sam/logs/nanoclaw.log
```

## 8.3 Docker Desktop

Docker Desktop pour Mac fournit :

- **Apple Hypervisor** : isolation au niveau hyperviseur (pas juste des namespaces)
- **Docker Engine** : gestion des images et containers
- **host.docker.internal** : resolution DNS vers le host depuis les containers
- **Buildkit** : builder cache pour les images

### Points d'attention

- **Cache buildkit** : `--no-cache` seul ne suffit pas pour invalider les COPY steps. Il faut purger le builder volume.
- **Docker Desktop doit tourner** : si Docker Desktop n'est pas lance, les agents ne peuvent pas spawner de containers.
- **Performance** : sur Apple Silicon, les containers Linux tournent via la virtualisation ARM native (pas d'emulation x86).

## 8.4 Cloud Run (Botti Voice, Chat Gateway)

### Botti Voice

| Propriete | Valeur |
|-----------|--------|
| Service | botti-voice |
| Region | europe-west1 |
| Runtime | Python + FastAPI |
| Port | 8080 |
| URL | Generee par Cloud Run |
| Concurrence | 1 (single user) |
| Timeout | 3600s (sessions audio longues) |

### Chat Gateway

| Propriete | Valeur |
|-----------|--------|
| Service | chat-gateway |
| Region | europe-west1 |
| Runtime | Python + FastAPI |
| Port | 8080 |
| URL | Generee par Cloud Run |
| Concurrence | 80 |
| Timeout | 60s |

### Agent Hub (optionnel)

| Propriete | Valeur |
|-----------|--------|
| Service | agent-hub |
| Region | europe-west1 |
| URL | `https://agent-hub-215323664878.europe-west1.run.app` |
| Role | Orchestrateur d'actions sortantes (Voice -> Gmail/Calendar) |

## 8.5 Services GCP utilises

| Service | Usage |
|---------|-------|
| **Cloud Run** | Hebergement Botti Voice + Chat Gateway |
| **Firestore** | Signaux webhook Gmail, queue Google Chat, mapping spaces |
| **Pub/Sub** | Notifications push Gmail (topic -> Botti Voice) |
| **Gmail API** | Lecture/envoi d'emails |
| **Google Chat API** | Envoi de reponses dans les espaces Chat |
| **Calendar API** | Lecture/creation d'evenements (via gws CLI + Voice) |
| **Drive API** | Recherche de fichiers (via gws CLI + Voice) |
| **OAuth 2.0** | Authentification Gmail, Calendar, Drive |
| **Service Accounts** | Firestore, Chat Bot |

### Comptes de service

| Compte | Fichier | Usage |
|--------|---------|-------|
| ADP Service Account | `~/.firebase-mcp/adp-service-account.json` | Firestore (lecture signaux, queue chat) |
| Chat Bot SA | `~/.firebase-mcp/chat-bot-sa.json` | API Google Chat (envoi messages via le bot) |

## 8.6 Domaines et DNS

| URL | Service | Usage |
|-----|---------|-------|
| Botti Voice Cloud Run URL | Botti Voice | Interface vocale + webhooks Gmail/Chat/Calendar |
| Chat Gateway Cloud Run URL | Chat Gateway | Webhook principal Google Chat |
| `localhost:3001` | Credential Proxy Botti | Proxy API (Docker -> host) |
| `localhost:3002` | Credential Proxy Thais | |
| `localhost:3003` | Credential Proxy Sam | |
| `localhost:3004` | Credential Proxy Alan | |
| `localhost:3100` | Dashboard | Monitoring local |

---

# 9. Deploiement et operations

## 9.1 deploy.sh

Le script `deploy.sh` est le mecanisme de deploiement central :

```bash
#!/bin/bash
# Deploy NanoClaw — rebuild and distribute dist/ to all instances.
# Usage: ./deploy.sh [--restart]
set -e
cd "$(dirname "$0")"

# 1. Build TypeScript
npm run build

# 2. Copier dist/ vers toutes les instances
INSTANCES=(nanoclaw-sam nanoclaw-thais nanoclaw-alan)
for inst in "${INSTANCES[@]}"; do
  dir="/Users/boty/$inst"
  if [ -d "$dir" ]; then
    rm -rf "$dir/dist"
    cp -R dist "$dir/dist"
  fi
done

# 3. Optionnellement redemarrer tous les services
if [ "$1" = "--restart" ]; then
  launchctl kickstart -k "gui/$(id -u)/com.nanoclaw"
  for inst in "${INSTANCES[@]}"; do
    svc="com.nanoclaw.${inst#nanoclaw-}"
    launchctl kickstart -k "gui/$(id -u)/$svc"
  done
fi
```

### Workflow de deploiement

```
1. Modifier le code dans /Users/boty/nanoclaw/src/
2. cd /Users/boty/nanoclaw
3. ./deploy.sh --restart
   -> npm run build (compile TypeScript)
   -> Copie dist/ vers nanoclaw-sam, nanoclaw-thais, nanoclaw-alan
   -> Redemarrage de tous les services launchd
4. Verifier les logs : tail -f logs/nanoclaw.log
```

### Pourquoi copier dist/ et pas symlinker

Les instances secondaires utilisent des symlinks pour `container/`, `node_modules/`, `package.json` et `src/` mais une **copie reelle** de `dist/`. Raison : si on symlinke `dist/` et qu'on rebuild pendant que les services tournent, les fichiers JS changent sous les pieds des processus en cours, ce qui peut causer des crashes inattendus.

## 9.2 create-agent.sh

Script automatise pour creer un nouvel agent. Usage :

```bash
./create-agent.sh <nom> <email> [--port PORT] [--model MODEL]

# Exemples
./create-agent.sh alan ala@bestoftours.co.uk --port 3004
./create-agent.sh marie marie@bestoftours.co.uk  # port auto-detecte
```

### Les 15 etapes du script

| Etape | Action |
|-------|--------|
| 1 | Valide les inputs (nom lowercase alpha, email avec @) |
| 2 | Auto-detecte un port libre (scan des plists existants, range 3001-3010) |
| 3 | Lit la cle API Anthropic depuis le nanoclaw principal |
| 4 | Cree la structure de repertoires (`groups/gmail_main/`, `data/`, `logs/`, `store/`) |
| 5 | Cree les symlinks (`container/`, `node_modules/`, `package.json`, `src/`) |
| 6 | Copie `dist/` (copie reelle, pas symlink) |
| 7 | Cree le `.env` avec les variables specifiques |
| 8 | Configure Gmail OAuth (copie les keys, lance le flux OAuth dans le navigateur) |
| 9 | Cree le plist launchd |
| 10 | Cree le CLAUDE.md du groupe `gmail_main` (template avec placeholders) |
| 11 | Initialise la base SQLite avec le schema et enregistre le groupe principal |
| 12 | Met a jour `deploy.sh` pour inclure le nouvel agent |
| 13 | Rappel : ajouter l'agent dans `VALID_AGENTS` du Chat Gateway |
| 14 | Charge et demarre le service launchd |
| 15 | Verifie que le service tourne |

### Le flux OAuth Gmail

Le script inclut un mini-serveur HTTP pour capturer le callback OAuth :

1. Copie les clefs OAuth depuis un agent existant
2. Ouvre le navigateur avec l'URL d'autorisation Google
3. L'utilisateur se connecte avec le compte Gmail de l'agent (ex: sam@bestoftours.co.uk)
4. Google redirige vers `localhost:8749` avec le code d'autorisation
5. Le script capture le code et l'echange contre des tokens refresh/access
6. Les tokens sont sauvegardes dans `~/.gmail-mcp-{agent}/credentials.json`

## 9.3 Dashboard

Le dashboard est un serveur Node.js minimal sur le port 3100 :

### Fonctionnalites

- **Decouverte automatique** : scanne `~/nanoclaw*` pour trouver toutes les instances
- **Etat des processus** : verifie via `launchctl list` si chaque service tourne
- **Containers actifs** : compte les containers Docker par prefixe
- **Analyse des logs** : parse les 2000 dernières lignes de logs JSON pour :
  - Detecter les channels connectes (WhatsApp, Gmail, etc.)
  - Trouver la derniere activite agent
  - Compter les erreurs dans la derniere heure
- **API JSON** : `GET /api/status` retourne toutes les donnees en JSON

### Endpoint API

```json
GET http://localhost:3100/api/status

{
  "summary": {
    "total": 4,
    "running": 4,
    "totalContainers": 2,
    "totalErrors": 0,
    "timestamp": "2026-03-31T10:00:00.000Z"
  },
  "agents": [
    {
      "name": "nanoclaw",
      "assistantName": "Botti",
      "status": "running",
      "pid": 12345,
      "uptime": "2026-03-30T08:00:00.000Z",
      "channels": ["gmail", "whatsapp"],
      "lastActivity": "2026-03-31T09:55:00.000Z",
      "activeContainers": 1,
      "errors": 0,
      "port": "3001",
      "model": "claude-opus-4-6",
      "containerPrefix": "nanoclaw"
    },
    ...
  ]
}
```

## 9.4 Logs

### Format

NanoClaw utilise **pino** pour le logging. Les logs sont en format JSON :

```json
{
  "level": 30,
  "time": 1711872000000,
  "pid": 12345,
  "msg": "Processing messages",
  "group": "whatsapp_main",
  "messageCount": 3
}
```

### Niveaux de log

| Niveau | Code | Usage |
|--------|------|-------|
| TRACE | 10 | Debug detaille |
| DEBUG | 20 | Messages de debug |
| INFO | 30 | Fonctionnement normal |
| WARN | 40 | Situations anormales mais gerees |
| ERROR | 50 | Erreurs |
| FATAL | 60 | Erreurs critiques (arret du processus) |

### Fichiers de log

| Fichier | Contenu |
|---------|---------|
| `logs/nanoclaw.log` | Logs stdout (pino JSON) |
| `logs/nanoclaw.error.log` | Logs stderr (erreurs systeme, stack traces) |

### Lire les logs

```bash
# Suivre les logs en temps reel
tail -f /Users/boty/nanoclaw/logs/nanoclaw.log

# Formatter les logs JSON (avec pino-pretty)
tail -f logs/nanoclaw.log | npx pino-pretty

# Chercher les erreurs
grep '"level":50' logs/nanoclaw.log | npx pino-pretty

# Logs d'un agent specifique
tail -f /Users/boty/nanoclaw-sam/logs/nanoclaw.log
```

## 9.5 Troubleshooting courant

### Docker Desktop n'est pas lance

**Symptome** : les agents ne repondent pas, erreurs `docker: command not found` ou `Cannot connect to the Docker daemon`

**Solution** :
```bash
# Verifier que Docker tourne
docker info

# Si non, lancer Docker Desktop
open -a "Docker Desktop"
```

### Token Gmail expire

**Symptome** : erreurs `Error: invalid_grant` dans les logs Gmail

**Solution** :
```bash
# Verifier les logs
grep "invalid_grant" /Users/boty/nanoclaw-sam/logs/nanoclaw.log

# Re-lancer le flux OAuth
# (utiliser le meme flux que create-agent.sh, etape 8)
```

### Prompt too long / Context overflow

**Symptome** : erreur Claude `prompt is too long` ou l'agent ne repond pas

**Cause** : le CLAUDE.md est devenu trop volumineux, ou trop de messages en attente

**Solution** :
- Nettoyer le CLAUDE.md (archiver les anciennes sections)
- Purger la session : supprimer le `session_id` dans SQLite
- Reduire le nombre de messages en attente

### Container crash / timeout

**Symptome** : `Container agent error` dans les logs, messages non traites

**Causes possibles** :
- Timeout (30 min par defaut)
- Out of memory Docker
- Image Docker corrompue

**Solution** :
```bash
# Voir les containers en cours
docker ps --filter "name=nanoclaw"

# Tuer un container bloque
docker stop <container_name>

# Nettoyer les orphelins
docker rm $(docker ps -a --filter "name=nanoclaw" -q)

# Rebuild l'image
./container/build.sh
```

### WhatsApp deconnecte

**Symptome** : plus de messages WhatsApp, `connection closed` dans les logs

**Solution** :
```bash
# Verifier l'etat
grep -i "disconnect\|connection" /Users/boty/nanoclaw/logs/nanoclaw.log | tail -20

# Redemarrer Botti
launchctl kickstart -k gui/$(id -u)/com.nanoclaw

# Si echec, scanner un nouveau QR code (rare)
# Supprimer store/auth/ et redemarrer
```

### Agent ne repond pas dans un groupe

**Checklist** :
1. Le groupe est-il enregistre ? (`SELECT * FROM registered_groups`)
2. Le trigger (@Agent) est-il present dans le message ?
3. Le sender est-il dans l'allowlist ?
4. Le processus tourne-t-il ? (`launchctl list | grep nanoclaw`)
5. Docker tourne-t-il ? (`docker info`)
6. Y a-t-il des erreurs dans les logs ?

---

# 10. Stack technique detaillee

## 10.1 Core (NanoClaw)

| Technologie | Version | Usage |
|------------|---------|-------|
| **Node.js** | 22.x | Runtime |
| **TypeScript** | 5.x | Langage |
| **better-sqlite3** | Latest | Base de donnees SQLite |
| **pino** | Latest | Logging JSON |
| **@whiskeysockets/baileys** | Latest | WhatsApp Web protocol |
| **googleapis** | Latest | API Gmail |
| **google-auth-library** | Latest | OAuth 2.0 |
| **@google-cloud/firestore** | Latest | Firestore SDK |

## 10.2 Botti Voice

| Technologie | Version | Usage |
|------------|---------|-------|
| **Python** | 3.11+ | Runtime |
| **FastAPI** | Latest | Framework web |
| **google-genai** | Latest | SDK Gemini |
| **Gemini 2.5 Flash** | native-audio-latest | Modele audio natif |
| **Starlette** | Latest | Middleware sessions |

## 10.3 Chat Gateway

| Technologie | Version | Usage |
|------------|---------|-------|
| **Python** | 3.11+ | Runtime |
| **FastAPI** | Latest | Framework web |
| **google-cloud-firestore** | Latest | SDK Firestore |

## 10.4 Agents (dans les containers)

| Technologie | Version | Usage |
|------------|---------|-------|
| **Claude Opus 4.6** | Latest | Modele IA principal |
| **Claude Agent SDK** | Latest | SDK d'agent (Claude Code) |
| **agent-browser** | Latest | Navigation web / Chromium |
| **@googleworkspace/cli** | Latest | Gmail, Calendar, Drive, Sheets, Docs |
| **Chromium** | Latest | Navigateur headless |

## 10.5 Infrastructure

| Technologie | Usage |
|------------|-------|
| **Docker Desktop** | Containers / isolation |
| **launchd** | Gestion des services macOS |
| **Google Cloud Run** | Hebergement Cloud |
| **Firestore** | Base NoSQL temps reel |
| **Pub/Sub** | Notifications push |
| **SQLite** | Base relationnelle locale |

## 10.6 Diagramme de la stack

```
+------------------------------------------------------------------+
|                        MODELES IA                                |
|                                                                  |
|  Claude Opus 4.6          Gemini 2.5 Flash                      |
|  (Agents texte)           (Voice native audio)                   |
+------------------------------------------------------------------+
|                        RUNTIME                                    |
|                                                                  |
|  Claude Agent SDK         google-genai SDK                       |
|  (dans Docker)            (Botti Voice)                          |
+------------------------------------------------------------------+
|                        APPLICATION                                |
|                                                                  |
|  Node.js/TS   Python/FastAPI   Python/FastAPI   Node.js          |
|  (NanoClaw)   (Botti Voice)    (Chat Gateway)   (Dashboard)     |
+------------------------------------------------------------------+
|                        CHANNELS                                   |
|                                                                  |
|  Baileys     googleapis    @google-cloud/    WebSocket           |
|  (WhatsApp)  (Gmail API)   firestore         (Voice)            |
|                            (Google Chat)                         |
+------------------------------------------------------------------+
|                        STOCKAGE                                   |
|                                                                  |
|  SQLite          Firestore          Filesystem                   |
|  (messages,      (signaux,          (CLAUDE.md,                  |
|   sessions,       chat-queue,        sessions,                   |
|   taches)         config)            logs)                       |
+------------------------------------------------------------------+
|                        INFRA                                      |
|                                                                  |
|  Docker Desktop   launchd    Cloud Run    GCP APIs               |
|  (containers)     (services)  (Voice,     (Gmail, Chat,          |
|                               Gateway)     Calendar, Drive)      |
+------------------------------------------------------------------+
```

---

# 11. Decisions architecturales et trade-offs

## 11.1 Pourquoi Node.js (pas Python) pour le core

| Argument | Detail |
|----------|--------|
| **Performance polling** | Node.js est nativement asynchrone, ideal pour du polling concurrent (WhatsApp + Gmail + Firestore + DB) |
| **TypeScript** | Typage statique, autocompletion, detection d'erreurs a la compilation |
| **Ecosystem npm** | Baileys (WhatsApp), better-sqlite3, googleapis -- tout existe en npm |
| **Claude Agent SDK** | Le SDK officiel est en Node.js (`@anthropic-ai/claude-code`) |
| **Un seul processus** | Event loop Node.js gere naturellement la concurrence sans threads |

Python aurait ete viable mais Node.js etait le choix naturel vu que le Claude Agent SDK est en Node.js.

## 11.2 Pourquoi Docker (pas de sandbox natif)

| Argument | Detail |
|----------|--------|
| **Isolation filesystem** | L'agent ne voit que les mounts explicites |
| **Reproductibilite** | Meme image pour tous les agents, meme environnement |
| **Cross-platform** | Fonctionne sur macOS et Linux |
| **Securite** | Hyperviseur Apple (pas juste des namespaces) |
| **Tooling** | Chromium, git, curl pre-installes dans l'image |

Alternative : Apple Container (plus leger sur macOS, mais pas cross-platform et plus complexe a configurer).

## 11.3 Pourquoi polling + webhook (pas webhook seul)

**Gmail** :
- Le webhook Pub/Sub notifie qu'il y a du nouveau, mais ne donne pas le contenu
- Il faut quand meme appeler l'API Gmail pour lire les emails
- Le polling est le **fallback** si le webhook est down
- Avec webhook actif : poll toutes les 5 min (fallback), signaux Firestore toutes les 5s
- Sans webhook : poll direct toutes les 60s

**Avantage** : resilience. Si le webhook tombe (Cloud Run restart, Pub/Sub issue), le polling reprend automatiquement.

## 11.4 Pourquoi Firestore (pas Pub/Sub pull)

| Critere | Firestore | Pub/Sub Pull |
|---------|-----------|--------------|
| Lib supplementaire cote NanoClaw | Non (deja utilisee) | Oui (`@google-cloud/pubsub`) |
| Complexite | Query simple (`where processed == false`) | Subscription, acknowledge, nack |
| Persistance | Les messages restent jusqu'au traitement | Expire apres retention period |
| Debugging | Visible dans la console Firebase | Moins visible |
| Performance | Suffisante (5s polling) | Plus rapide (push) |

Firestore a ete choisi par simplicite : pas de nouvelle dependance, queries intuitives, donnees visibles dans la console.

## 11.5 Pourquoi un seul Chat App (pas 4)

Creer une Google Chat App dans GCP est un processus lourd :

1. Creer un projet GCP ou utiliser un existant
2. Configurer l'OAuth consent screen
3. Enregistrer l'app dans la console Chat
4. Publier l'app (ou la garder en mode test)
5. Les utilisateurs doivent ajouter l'app manuellement

Multiplier ca par 4 agents serait penible. La solution : **un seul Chat App** ("Botti") avec routing par `@mention` dans le Chat Gateway.

**Limitation** : dans Google Chat, il n'y a qu'un seul "bot" qui repond. Les utilisateurs doivent utiliser `@Sam` ou `@Thais` pour router vers un autre agent. L'experience est un peu moins naturelle qu'avec 4 bots distincts.

## 11.6 Pourquoi Gemini pour Voice (pas Claude)

Claude n'a tout simplement **pas d'API audio native** en mars 2026. Gemini 2.5 Flash offre :

- Audio natif (pas de pipeline STT -> LLM -> TTS)
- Streaming bidirectionnel (voix en temps reel)
- Barge-in (interruption quand l'utilisateur parle)
- Latence minimale (~200ms)

C'est un choix pragmatique : Claude pour le texte (meilleur raisonnement, meilleur tool use), Gemini pour la voix (seul a offrir l'audio natif).

## 11.7 Pourquoi Claude pour les agents (pas Gemini)

| Critere | Claude Opus 4.6 | Gemini 2.5 |
|---------|------------------|------------|
| Qualite raisonnement | Excellente | Tres bonne |
| Tool use / code | Excellent (Claude Code SDK) | Bon |
| Comprehension instructions longues | Excellente | Bonne |
| Fenetre contexte | 200k tokens | 1M tokens |
| SDK agent | Claude Code (mature) | Pas d'equivalent |
| Container execution | Natif (Claude Code) | Necessiterait du custom |

Le Claude Agent SDK (Claude Code) est **l'element cle**. C'est un environnement d'execution d'agent complet avec session management, tool use, memory, et swarms. Gemini n'a pas d'equivalent aussi mature.

## 11.8 Pourquoi Mac Mini (pas Cloud)

Voir la section 1.4 pour le detail complet. Resume :

1. **WhatsApp** : necessite IP stable (risque de ban avec IP cloud dynamique)
2. **Cout** : 0 EUR/mois vs 50-200 EUR/mois en cloud
3. **Secrets** : restent sur la machine, jamais dans le cloud
4. **Simplicite** : launchd est plus simple que Kubernetes

**Trade-off accepte** : pas de haute disponibilite, dependant de la connexion internet du bureau.

---

# 12. Roadmap et prochaines etapes

## 12.1 Court terme (Q2 2026)

### Tests manquants

Le codebase a quelques tests mais la couverture est incomplete :

- `src/index.ts` devrait etre splitte en modules plus testables
- Les channels ont besoin de tests d'integration
- Le container-runner necessite des tests de bout en bout
- Objectif : > 70% de couverture

### Filtrage email avance (ML-based)

Le filtrage actuel est base sur des regles (prefixes, domaines, headers). Un filtrage ML permettrait de :

- Classifier les emails par importance (urgent, normal, low, spam)
- Apprendre des actions de l'utilisateur (emails ignores vs repondus)
- Reduire les faux positifs (emails personnels de domaines marketing)

### Rate limiting credential proxy

Ajouter du rate limiting au credential proxy :

- Limiter le nombre de requetes par seconde/minute
- Limiter le nombre de tokens par requete
- Alerter quand un pattern anormal est detecte

## 12.2 Moyen terme (Q3-Q4 2026)

### Migration Gemini pour Voice

Quand Gemini 3.x sortira avec des capacites audio ameliorees, migrer Botti Voice. L'architecture est deja preparee (le modele est configurable via `GEMINI_MODEL`).

### Scaling a 10+ agents

Actuellement 4 agents. Pour scaler :

- Optimiser la memoire (un processus Node.js par agent = ~100MB chacun)
- Envisager un mode multi-agent par processus
- Externaliser SQLite vers PostgreSQL si les volumes deviennent importants
- Utiliser un orchestrateur de containers plus sophistique

### Dashboard accessible depuis l'exterieur

Le dashboard actuel est local (port 3100, bind 0.0.0.0 mais pas expose). Options :

- Tunnel ngrok/cloudflared
- Deployer une version sur Cloud Run avec auth
- Integrer dans un dashboard existant (Grafana, etc.)

## 12.3 Long terme

### Monitoring/alerting

- Integration PagerDuty ou Slack pour les alertes
- Metriques Prometheus/Grafana
- Alertes sur : agent down, erreurs repetees, spend limit proche

### Integration MCP elargie

Ajouter des MCP servers supplementaires aux containers :

- Jira/Linear (gestion de projet)
- Notion (documentation)
- BigQuery (analytics)
- GitHub (code review automatique)

### Agent autonome avance

- Agents qui prennent des initiatives (proactivite basee sur les patterns)
- Agents qui collaborent entre eux (agent swarms cross-instance)
- Memoire a long terme avec recherche semantique

---

# 13. Comment creer un nouvel agent

## 13.1 Prerequis

1. Le nanoclaw principal (`/Users/boty/nanoclaw`) est installe et fonctionne
2. Un compte Gmail Workspace pour l'agent (ex: `marie@bestoftours.co.uk`)
3. Les credentials OAuth GCP (copie automatique depuis un agent existant)
4. Docker Desktop est lance

## 13.2 Procedure pas-a-pas

### Etape 1 : Lancer le script

```bash
cd /Users/boty/nanoclaw
./create-agent.sh marie marie@bestoftours.co.uk
```

Le script va :
- Valider le nom (lowercase alpha only)
- Auto-detecter un port libre (3005, 3006, etc.)
- Creer tout automatiquement

### Etape 2 : Authentification Gmail

Le navigateur s'ouvre. Se connecter avec le compte `marie@bestoftours.co.uk` et autoriser les scopes :
- Gmail (lecture/envoi)
- Calendar (lecture/ecriture)
- Drive (lecture)

### Etape 3 : Verifier le demarrage

```bash
# Verifier que le service tourne
launchctl list | grep nanoclaw.marie

# Voir les logs
tail -f /Users/boty/nanoclaw-marie/logs/nanoclaw.log
```

### Etape 4 : Configurer le Chat Gateway

Action manuelle requise : ajouter `"marie"` dans `VALID_AGENTS` du Chat Gateway (Cloud Run).

### Etape 5 : Personnaliser le CLAUDE.md

Editer `/Users/boty/nanoclaw-marie/groups/gmail_main/CLAUDE.md` pour :
- Definir l'identite et la personnalite de l'agent
- Ajouter le contexte metier
- Configurer les regles de communication

### Etape 6 : Configurer les webhooks

Si on veut des webhooks Gmail rapides (vs polling 60s) :
1. Ajouter le compte dans `GMAIL_WEBHOOK_ACCOUNTS` de Botti Voice
2. Redemarrer Botti Voice sur Cloud Run

### Etape 7 : Tester

Envoyer un email a `marie@bestoftours.co.uk` et verifier que l'agent repond.

## 13.3 Structure finale

Apres creation, la structure est :

```
/Users/boty/nanoclaw-marie/
  .env                          # Config de Marie
  dist/                         # Copie du code compile
  container -> ../nanoclaw/container
  node_modules -> ../nanoclaw/node_modules
  package.json -> ../nanoclaw/package.json
  src -> ../nanoclaw/src
  groups/
    gmail_main/
      CLAUDE.md                 # Memoire/identite de Marie
  store/
    messages.db                 # Base SQLite
  data/
    sessions/
      gmail_main/
        .claude/                # Sessions Claude
  logs/
    nanoclaw.log                # Logs
```

---

# 14. Annexes

## 14.1 Ports utilises

| Port | Service | Agent | Acces |
|------|---------|-------|-------|
| 3001 | Credential Proxy | Botti | Docker containers -> host |
| 3002 | Credential Proxy | Thais | Docker containers -> host |
| 3003 | Credential Proxy | Sam | Docker containers -> host |
| 3004 | Credential Proxy | Alan | Docker containers -> host |
| 3100 | Dashboard | (global) | `http://localhost:3100` |

Note : les ports 3001-3004 sont bindes sur l'interface Docker (`host.docker.internal`) et ne sont pas accessibles depuis l'exterieur.

## 14.2 Variables d'environnement

### Variables dans .env (par instance)

| Variable | Description | Defaut | Exemple |
|----------|-------------|--------|---------|
| `ANTHROPIC_API_KEY` | Cle API Anthropic (lu par le credential proxy uniquement) | - | `sk-ant-api03-...` |
| `CLAUDE_MODEL` | Modele Claude a utiliser | - | `claude-opus-4-6` |
| `ASSISTANT_NAME` | Nom de l'agent (trigger pattern) | `Andy` | `Botti`, `Sam` |
| `ASSISTANT_HAS_OWN_NUMBER` | L'agent a son propre numero WhatsApp | `false` | `true` (Botti) |
| `CREDENTIAL_PROXY_PORT` | Port du credential proxy | `3001` | `3003` |
| `CONTAINER_PREFIX` | Prefixe des containers Docker | `nanoclaw` | `nanoclaw-sam` |
| `GMAIL_MCP_DIR` | Repertoire des credentials Gmail | `~/.gmail-mcp` | `~/.gmail-mcp-sam` |
| `GOOGLE_CHAT_ENABLED` | Active le channel Google Chat | `false` | `true` |
| `GOOGLE_CHAT_AGENT_NAME` | Nom de l'agent dans le Chat Gateway | `nanoclaw` | `sam` |
| `GOOGLE_APPLICATION_CREDENTIALS` | Chemin du service account Firebase | - | `~/.firebase-mcp/adp-service-account.json` |
| `GMAIL_WEBHOOK_ENABLED` | Active le polling Firestore pour les signaux Gmail | `false` | `true` |

### Variables dans le plist (EnvironmentVariables)

Les variables ci-dessus sont dupliquees dans le plist pour les services launchd. Le plist a priorite sur le .env pour les variables suivantes :

- `PATH` : chemin des binaires (Node.js, Docker, gcloud)
- `HOME` : repertoire home de l'utilisateur
- Les variables `CREDENTIAL_PROXY_PORT`, `GMAIL_MCP_DIR`, `GOOGLE_*`

### Variables systeme (pas dans .env)

| Variable | Description | Defaut |
|----------|-------------|--------|
| `POLL_INTERVAL` | Intervalle de polling messages (ms) | `2000` |
| `SCHEDULER_POLL_INTERVAL` | Intervalle du scheduler (ms) | `60000` |
| `CONTAINER_TIMEOUT` | Timeout container (ms) | `1800000` (30 min) |
| `IDLE_TIMEOUT` | Timeout inactivite (ms) | `1800000` (30 min) |
| `CONTAINER_MAX_OUTPUT_SIZE` | Taille max output container (bytes) | `10485760` (10 MB) |
| `MAX_CONCURRENT_CONTAINERS` | Max containers simultanes | `5` |
| `IPC_POLL_INTERVAL` | Intervalle IPC (ms) | `1000` |
| `DAILY_API_LIMIT_USD` | Limite depenses API/jour | `20` |
| `REMOTE_CONTROL_PIN` | PIN pour le remote control | (vide = desactive) |
| `DASHBOARD_PORT` | Port du dashboard | `3100` |
| `TZ` | Fuseau horaire | (systeme) |

### Variables Botti Voice (Cloud Run)

| Variable | Description |
|----------|-------------|
| `GEMINI_API_KEY` | Cle API Gemini |
| `GEMINI_MODEL` | Modele Gemini |
| `GOOGLE_CLIENT_ID` | OAuth client ID (web) |
| `GOOGLE_CLIENT_SECRET` | OAuth client secret (web) |
| `GOOGLE_REFRESH_TOKEN` | Refresh token pour Workspace |
| `GOOGLE_CLIENT_ID_OAUTH` | OAuth client ID (installed) |
| `GOOGLE_CLIENT_SECRET_OAUTH` | OAuth client secret (installed) |
| `SESSION_SECRET` | Secret pour les sessions |
| `BOTTI_PIN` | PIN d'acces optionnel |
| `GMAIL_WEBHOOK_ACCOUNTS` | JSON des comptes Gmail pour webhooks |
| `CHAT_WEBHOOK_ACCOUNTS` | JSON des comptes Chat pour webhooks |
| `CALENDAR_WEBHOOK_ACCOUNTS` | JSON des comptes Calendar pour webhooks |
| `CALENDAR_WEBHOOK_URL` | URL callback Calendar |
| `AGENT_HUB_URL` | URL du service Agent Hub |
| `AGENT_HUB_API_KEY` | Cle API Agent Hub |

### Variables Chat Gateway (Cloud Run)

| Variable | Description |
|----------|-------------|
| `CHAT_VERIFICATION_TOKEN` | Token de verification Google Chat |
| `ADMIN_API_KEY` | Cle API admin (mapping spaces) |

## 14.3 Structure des fichiers

### Repertoire principal (nanoclaw)

```
/Users/boty/nanoclaw/
|-- .env                        # Configuration (secrets + settings)
|-- package.json                # Dependances npm
|-- tsconfig.json               # Configuration TypeScript
|-- CLAUDE.md                   # Instructions pour Claude Code
|-- README.md                   # Documentation publique
|
|-- src/                        # Code source TypeScript
|   |-- index.ts                # Orchestrateur principal
|   |-- config.ts               # Configuration (trigger, paths, intervals)
|   |-- db.ts                   # SQLite (schema, queries)
|   |-- container-runner.ts     # Spawn containers Docker
|   |-- container-runtime.ts    # Detection runtime (Docker/Apple Container)
|   |-- credential-proxy.ts     # Proxy HTTP pour secrets API
|   |-- message-loop.ts         # Boucle de polling messages
|   |-- group-queue.ts          # Queue de concurrence par groupe
|   |-- router.ts               # Formatage messages, routing
|   |-- task-scheduler.ts       # Execution taches planifiees
|   |-- ipc.ts                  # Communication inter-processus
|   |-- remote-control.ts       # Remote control via WhatsApp
|   |-- sender-allowlist.ts     # Controle d'acces par expediteur
|   |-- mount-security.ts       # Validation des mounts additionnels
|   |-- anti-spam.ts            # Protection anti-spam/rate-limit
|   |-- backoff.ts              # Calcul de backoff exponentiel
|   |-- logger.ts               # Configuration pino
|   |-- env.ts                  # Lecture des fichiers .env
|   |-- types.ts                # Types TypeScript partages
|   |-- group-folder.ts         # Validation/resolution chemins groupes
|   |-- channels/
|   |   |-- index.ts            # Barrel import (enregistrement auto)
|   |   |-- registry.ts         # Registre des channels
|   |   |-- whatsapp.ts         # Channel WhatsApp (Baileys)
|   |   |-- gmail.ts            # Channel Gmail
|   |   |-- google-chat.ts      # Channel Google Chat
|
|-- container/                  # Configuration Docker
|   |-- Dockerfile              # Image agent
|   |-- build.sh                # Script de construction
|   |-- agent-runner/           # Code qui tourne DANS le container
|   |   |-- src/                # TypeScript
|   |   |-- package.json
|   |-- skills/                 # Skills synchronisees dans les containers
|       |-- agent-browser/      # Navigation web (Chromium)
|
|-- groups/                     # Memoire par groupe
|   |-- whatsapp_main/
|   |   |-- CLAUDE.md           # Identite/memoire de Botti
|   |-- global/
|       |-- CLAUDE.md           # Memoire globale
|
|-- store/                      # Donnees persistantes
|   |-- messages.db             # Base SQLite
|   |-- auth/                   # Credentials WhatsApp
|   |-- daily-spend.json        # Tracking depenses API
|
|-- data/                       # Donnees temporaires/sessions
|   |-- sessions/               # Sessions Claude par groupe
|   |-- ipc/                    # IPC par groupe
|
|-- logs/                       # Fichiers de log
|   |-- nanoclaw.log            # Logs stdout (JSON)
|   |-- nanoclaw.error.log      # Logs stderr
|
|-- botti-voice/                # Service Botti Voice (Python)
|   |-- web/
|       |-- server.py           # Serveur FastAPI
|       |-- gemini_bridge.py    # Pont Gemini Live
|       |-- config.py           # Configuration + prompts
|       |-- workspace.py        # Client Gmail/Calendar/Drive
|       |-- auth.py             # Authentification OAuth
|       |-- gmail_webhook.py    # Handler webhook Gmail
|       |-- chat_webhook.py     # Handler webhook Chat
|       |-- calendar_webhook.py # Handler webhook Calendar
|       |-- static/             # Frontend web
|
|-- chat-gateway/               # Service Chat Gateway (Python)
|   |-- server.py               # Serveur FastAPI
|
|-- dashboard/                  # Dashboard monitoring
|   |-- server.cjs              # Serveur HTTP
|   |-- index.html              # Frontend
|
|-- create-agent.sh             # Script creation d'agent
|-- deploy.sh                   # Script de deploiement
|-- docs/                       # Documentation
```

### Repertoire d'une instance secondaire (nanoclaw-sam)

```
/Users/boty/nanoclaw-sam/
|-- .env                        # Config specifique Sam
|-- dist/                       # COPIE du code compile (pas symlink)
|-- container -> ../nanoclaw/container    # Symlink
|-- node_modules -> ../nanoclaw/node_modules  # Symlink
|-- package.json -> ../nanoclaw/package.json  # Symlink
|-- src -> ../nanoclaw/src                    # Symlink
|-- groups/
|   |-- gmail_main/
|       |-- CLAUDE.md           # Identite/memoire de Sam
|-- store/
|   |-- messages.db             # Base SQLite de Sam
|-- data/
|   |-- sessions/
|-- logs/
    |-- nanoclaw.log
    |-- nanoclaw.error.log
```

## 14.4 Schema base de donnees (diagramme)

```
+-------------------+     +---------------------+
|     chats         |     |     messages         |
+-------------------+     +---------------------+
| jid (PK)          |<----| id (PK)             |
| name              |     | chat_jid (PK, FK)   |
| last_message_time |     | sender              |
| channel           |     | sender_name         |
| is_group          |     | content             |
+-------------------+     | timestamp           |
                          | is_from_me          |
                          | is_bot_message      |
                          +---------------------+

+-------------------+     +---------------------+
| registered_groups |     |  scheduled_tasks     |
+-------------------+     +---------------------+
| jid (PK)          |     | id (PK)             |
| name              |     | group_folder        |
| folder (UNIQUE)   |     | chat_jid            |
| trigger_pattern   |     | prompt              |
| added_at          |     | schedule_type       |
| container_config  |     | schedule_value      |
| requires_trigger  |     | context_mode        |
| is_main           |     | next_run            |
+-------------------+     | last_run            |
                          | last_result         |
                          | status              |
                          | created_at          |
                          +---------------------+
                                   |
                          +---------------------+
                          | task_run_logs        |
                          +---------------------+
                          | id (PK, AUTO)        |
                          | task_id (FK)         |
                          | run_at               |
                          | duration_ms          |
                          | status               |
                          | result               |
                          | error                |
                          +---------------------+

+-------------------+     +---------------------+
| router_state      |     | sessions             |
+-------------------+     +---------------------+
| key (PK)          |     | group_folder (PK)   |
| value             |     | session_id          |
+-------------------+     +---------------------+
```

## 14.5 Firestore collections (structure)

```
firestore/
|
|-- gmail-notify/                    # Signaux webhook Gmail
|   |-- botti/
|   |   |-- signals/
|   |       |-- <auto-id>/
|   |           |-- processed: false
|   |           |-- timestamp: "..."
|   |-- sam/
|   |   |-- signals/
|   |       |-- ...
|   |-- thais/
|   |-- alan/
|
|-- chat-queue/                      # Queue messages Google Chat
|   |-- botti/
|   |   |-- messages/
|   |       |-- <auto-id>/
|   |           |-- spaceId: "spaces/XXX"
|   |           |-- spaceName: "Nom du space"
|   |           |-- text: "Le message"
|   |           |-- senderName: "Ahmed"
|   |           |-- senderEmail: "ahmed@..."
|   |           |-- createTime: "..."
|   |           |-- processed: false
|   |           |-- yacinePresent: true
|   |-- sam/
|   |-- thais/
|   |-- alan/
|
|-- chat-config/                     # Configuration Chat
    |-- space-mapping/
        |-- "spaces/XXX": "sam"
        |-- "spaces/YYY": "thais"
```

## 14.6 Flux complet d'un message (sequence detaillee)

### Cas : message WhatsApp "@Botti check my emails"

```
1. WhatsApp Servers
   -> WebSocket Signal Protocol
   -> Baileys (Node.js)
   -> Event: messages.upsert

2. WhatsApp Channel (whatsapp.ts)
   -> Extrait: sender, content, timestamp
   -> Appelle onMessage(chatJid, msg)

3. Index.ts channelOpts.onMessage
   -> Sender allowlist check
   -> storeMessage(msg) -> SQLite messages table
   -> storeChatMetadata() -> SQLite chats table

4. Message Loop (message-loop.ts)
   -> Polling toutes les 2000ms
   -> getNewMessages(jids, lastTimestamp)
   -> Detecte le message dans whatsapp_main
   -> queue.enqueueMessageCheck(chatJid)

5. Group Queue (group-queue.ts)
   -> Verifie concurrence (< 5 containers)
   -> Appelle processGroupMessages(chatJid)

6. processGroupMessages (index.ts)
   -> getMessagesSince(chatJid, sinceTimestamp)
   -> Verifie trigger: TRIGGER_PATTERN.test("@Botti check my emails") = true
   -> formatMessages(messages, timezone)
   -> Cree le prompt texte

7. runAgent (index.ts)
   -> writeTasksSnapshot (taches pour le container)
   -> writeGroupsSnapshot (groupes pour le container)
   -> runContainerAgent(group, input, ...)

8. Container Runner (container-runner.ts)
   -> buildVolumeMounts(group, isMain)
   -> buildContainerArgs(mounts, containerName)
   -> spawn("docker", ["run", "-i", "--rm", ...])
   -> Ecrit le prompt JSON sur stdin
   -> Parse stdout pour les resultats

9. Container Docker
   -> agent-runner demarre
   -> Lit stdin (prompt JSON)
   -> Lance Claude Code (claude-code SDK)
   -> Claude lit le CLAUDE.md
   -> Claude traite "check my emails"
   -> Claude utilise gws CLI: gws gmail +triage
   -> Claude formate la reponse
   -> Ecrit le resultat sur stdout

10. Container Runner
    -> Parse stdout: ---NANOCLAW_OUTPUT_START--- ... ---NANOCLAW_OUTPUT_END---
    -> Extrait le result JSON
    -> Appelle onOutput callback

11. processGroupMessages callback
    -> Filtre les tags <internal>
    -> Verifie si c'est une erreur rate-limit
    -> channel.sendMessage(chatJid, text)

12. WhatsApp Channel
    -> sock.sendMessage(chatJid, { text })
    -> Message envoye via WhatsApp

13. Cleanup
    -> Session Claude sauvegardee (setSession)
    -> Cursor avance (lastAgentTimestamp)
    -> saveState() -> SQLite router_state
    -> Container supprime (--rm)
```

## 14.7 Glossaire

| Terme | Definition |
|-------|-----------|
| **Agent** | Instance de NanoClaw avec sa propre identite, memoire et channels |
| **Channel** | Source de messages (WhatsApp, Gmail, Google Chat) |
| **Group** | Conversation ou contexte isole (ex: whatsapp_main, gmail_main) |
| **Main group** | Groupe principal de l'agent (admin, recoit tous les emails/chats) |
| **Container** | Instance Docker ephemere ou Claude Code s'execute |
| **Credential proxy** | Serveur HTTP local qui injecte les secrets API |
| **CLAUDE.md** | Fichier de memoire/identite lu automatiquement par Claude Code |
| **Session** | Conversation Claude persistante (reprise entre invocations) |
| **Trigger** | Motif qui declenche l'agent (ex: @Botti, @Sam) |
| **IPC** | Communication inter-processus via le filesystem |
| **Barge-in** | Interruption de la reponse vocale quand l'utilisateur parle |
| **Swarm** | Equipe de sous-agents collaborant sur une tache complexe |
| **Skill** | Modification guidee du codebase (ex: /add-telegram) |
| **agent-runner** | Code TypeScript qui orchestre Claude dans le container |
| **gws** | Google Workspace CLI (Gmail, Calendar, Drive, Sheets, Docs) |
| **Baileys** | Librairie Node.js implementant le protocole WhatsApp Web |
| **pino** | Librairie de logging JSON pour Node.js |

---

*Document genere le 31 mars 2026. Pour toute question, contacter Yacine Bakouche (yacine@bestoftours.co.uk) ou ouvrir une session Claude Code dans le repertoire NanoClaw.*
