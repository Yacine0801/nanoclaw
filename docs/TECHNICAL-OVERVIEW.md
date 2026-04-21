# NanoClaw v2.0.0 -- Vue technique complete

**Document a destination d'Ahmed Amdouni, CTO de Botler 360 / Best of Tours**

Version : 2.0.0
Date : 4 avril 2026
Auteur : Yacine Bakouche + Claude Code
Licence : Botler 360 SAS -- Proprietary

---

# Table des matieres

1.  [Introduction](#1-introduction)
2.  [Architecture globale](#2-architecture-globale)
3.  [Les 4 agents](#3-les-4-agents)
4.  [Les canaux de communication](#4-les-canaux-de-communication)
5.  [Containers et isolation](#5-containers-et-isolation)
6.  [Memoire et persistance](#6-memoire-et-persistance)
7.  [Securite](#7-securite)
8.  [Observabilite](#8-observabilite)
9.  [Tests](#9-tests)
10. [Infrastructure](#10-infrastructure)
11. [Operations](#11-operations)
12. [Stack technique](#12-stack-technique)
13. [Decisions architecturales](#13-decisions-architecturales)
14. [Scores de qualite](#14-scores-de-qualite)
15. [Configuration](#15-configuration)
16. [Roadmap](#16-roadmap)
17. [Comment creer un nouvel agent](#17-comment-creer-un-nouvel-agent)
18. [Annexes](#18-annexes)

---

# 1. Introduction

## 1.1 Qu'est-ce que NanoClaw

NanoClaw est un systeme d'agents IA personnels qui tournent sur un Mac Mini local.
Chaque agent est une instance autonome de Claude (via le Claude Agent SDK / Claude Code)
qui peut :

- Recevoir et repondre a des messages via WhatsApp, Gmail, Google Chat
- Envoyer et lire des emails
- Naviguer sur le web (Chromium headless dans les containers)
- Executer du code dans un sandbox Docker isole
- Planifier des taches recurrentes (cron, intervalles, one-shot)
- Maintenir une memoire persistante entre les sessions
- Acceder a Google Calendar, Drive, Sheets, Docs via le CLI `gws`
- Parler en mode vocal via Botti Voice (Gemini Live)

## 1.2 Pourquoi on l'a construit

NanoClaw est ne d'une frustration avec OpenClaw (anciennement ClawBot), un projet open-source
similaire qui etait devenu ingerable :

- ~500 000 lignes de code, 53 fichiers de configuration, 70+ dependances
- 4-5 processus differents, securite applicative (allowlists, pairing codes)
- Impossible de comprendre le code en entier

NanoClaw prend l'approche inverse :

- **Un seul processus Node.js** par agent (~14 000 lignes TypeScript au total)
- **Isolation reelle** via containers Docker (pas juste des permissions applicatives)
- **AI-native** : pas de dashboard complexe, Claude Code fait le setup et le debug
- **Construit pour un seul utilisateur** : chaque installation est un fork personnalise

## 1.3 Chiffres cles de la v2.0.0

| Metrique                          | Valeur                                       |
|----------------------------------|----------------------------------------------|
| Version                          | 2.0.0                                        |
| Nombre d'agents                  | 4 (Botti, Sam, Thais, Alan)                  |
| Tests                            | 514 (28 fichiers de tests)                   |
| Lignes de code source TS         | ~14 000                                      |
| Lignes de tests TS               | ~10 800                                      |
| Commits sur la periode 1-4 avril | ~20                                           |
| Canaux de communication          | 4 (WhatsApp, Gmail, Google Chat, Voice)      |
| Services launchd                 | 8                                             |
| Services Cloud Run               | 2 (Botti Voice, Chat Gateway)                |
| Licence                          | Proprietaire Botler 360 SAS                  |

## 1.4 La philosophie

### Assez petit pour etre compris

Le codebase entier est lisible en une session. Un humain (ou Claude) peut comprendre la
totalite du systeme. C'est un choix delibere : la securite vient du fait qu'on peut auditer
tout le code.

### Securite par isolation

Les agents ne sont pas "empeches" d'acceder a des fichiers via des permissions applicatives.
Ils tournent dans des containers Linux ou seuls les fichiers explicitement montes sont
visibles. C'est de l'isolation au niveau OS/hyperviseur, pas au niveau application.

### Construit pour un seul utilisateur

Ce n'est pas un framework generaliste. C'est un logiciel personnel. Chaque installation est
un fork qui est modifie pour correspondre exactement aux besoins de l'utilisateur. Il n'y a
pas de "configuration generique" -- on modifie le code directement si necessaire.

### AI-native

- Pas de wizard d'installation : Claude Code guide le setup
- Monitoring minimal (dashboard + health endpoints) : on demande a Claude ce qui se passe
- Skills plutot que features : `/add-telegram`, `/add-slack`, etc. transforment le code

### Skills plutot que features

Plutot que d'ajouter du support Telegram au core, les contributeurs soumettent des "skills"
comme `/add-telegram` qui transforment le code du fork de l'utilisateur. Le resultat : du
code propre qui fait exactement ce qu'il faut, pas un systeme generique.

## 1.5 Le Mac Mini comme serveur personnel

### Pourquoi pas le Cloud

| Aspect           | Mac Mini local            | Cloud (GCE/EC2)         |
|-----------------|---------------------------|--------------------------|
| Cout mensuel    | 0 EUR (deja achete)       | ~40-80 EUR/mois          |
| Latence Docker  | <200ms spawn              | Identique                |
| WhatsApp        | Session locale, stable    | Risque de ban (IP DC)    |
| Controle        | Total (disque, reseau)    | Limite par le provider   |
| Disponibilite   | ~99.5% (electrique)       | 99.99%                   |

Le Mac Mini est le bon compromis pour un systeme personnel : cout nul, controle total,
latence minimale. Les services qui doivent etre accessibles de l'exterieur (Chat Gateway,
Botti Voice) sont sur Cloud Run.

---

# 2. Architecture globale

## 2.1 Diagramme d'ensemble

```
 +---------------------------------------------------------------------+
 |                        Mac Mini (macOS)                              |
 |                                                                      |
 |  +--------------------------+  +--------------------------+          |
 |  |  NanoClaw Instance 1     |  |  NanoClaw Instance 2     |          |
 |  |  "Botti" (port 3001)     |  |  "Sam" (port 3003)       |          |
 |  |  WhatsApp + Gmail + Chat |  |  Gmail + Chat             |          |
 |  +----------+---------------+  +----------+---------------+          |
 |             |                              |                         |
 |  +--------------------------+  +--------------------------+          |
 |  |  NanoClaw Instance 3     |  |  NanoClaw Instance 4     |          |
 |  |  "Thais" (port 3002)     |  |  "Alan" (port 3004)      |          |
 |  |  Gmail + Chat            |  |  Gmail + Chat             |          |
 |  +----------+---------------+  +----------+---------------+          |
 |             |                              |                         |
 |  +----------------------------------------------------------+       |
 |  |              Docker Desktop (containers)                  |       |
 |  |  +----------+  +----------+  +----------+  +----------+  |       |
 |  |  | Agent    |  | Agent    |  | Agent    |  | Agent    |  |       |
 |  |  | Container|  | Container|  | Container|  | Container|  |       |
 |  |  | (Botti)  |  | (Sam)    |  | (Thais)  |  | (Alan)   |  |       |
 |  |  +----------+  +----------+  +----------+  +----------+  |       |
 |  +----------------------------------------------------------+       |
 |                                                                      |
 |  +-------------------------+  +-------------------------+            |
 |  | Dashboard (port 3100)   |  | Watchdog (toutes 5min)  |            |
 |  +-------------------------+  +-------------------------+            |
 +---------------------------------------------------------------------+
         |                    |                     |
         v                    v                     v
 +----------------+  +-----------------+  +-------------------+
 | WhatsApp       |  | Gmail API       |  | Firestore         |
 | (Baileys,      |  | (OAuth2,        |  | nanoclaw-messages |
 |  session        |  |  Pub/Sub)       |  | nanoclaw-signals  |
 |  locale)        |  |                 |  | chat-config       |
 +----------------+  +-----------------+  +-------------------+
                                                    ^
                                                    |
 +---------------------------------------------------------------------+
 |                      Google Cloud Platform                           |
 |                                                                      |
 |  +---------------------------+  +---------------------------+        |
 |  |  Cloud Run:               |  |  Cloud Run:               |        |
 |  |  Botti Voice              |  |  Chat Gateway             |        |
 |  |  (Gemini Live audio,      |  |  (Google Chat App,        |        |
 |  |   agent selector,         |  |   Firestore writer,       |        |
 |  |   unified memory)         |  |   rate limiter)           |        |
 |  +---------------------------+  +---------------------------+        |
 |                                                                      |
 |  +-----------+  +-----------+  +-----------+  +-----------+         |
 |  | Pub/Sub   |  | GCS       |  | Chat API  |  | Gmail API |         |
 |  | gmail-    |  | nanoclaw- |  | spaces.   |  | webhook   |         |
 |  | push      |  | backups-  |  | messages  |  | push      |         |
 |  |           |  | adp       |  |           |  |           |         |
 |  +-----------+  +-----------+  +-----------+  +-----------+         |
 +---------------------------------------------------------------------+
```

## 2.2 Flux de donnees par canal

### WhatsApp (Botti uniquement)

```
 Utilisateur                      Mac Mini
     |                               |
     |  Message WhatsApp             |
     +------------------------------>|
     |                    +----------+-----------+
     |                    | Baileys (WebSocket)  |
     |                    | Decode protobuf      |
     |                    +----------+-----------+
     |                               |
     |                    onMessage(chatJid, msg)
     |                               |
     |                    +----------+-----------+
     |                    | SQLite: messages      |
     |                    +----------+-----------+
     |                               |
     |                    Message Loop (poll 2s)
     |                               |
     |                    +----------+-----------+
     |                    | Group Queue           |
     |                    | (max 5 containers)    |
     |                    +----------+-----------+
     |                               |
     |                    +----------+-----------+
     |                    | Docker container      |
     |                    | Claude Agent SDK      |
     |                    | API via proxy :3001   |
     |                    +----------+-----------+
     |                               |
     |  Reponse WhatsApp             |
     |<------------------------------+
```

### Gmail (tous les agents)

```
 Expedieur                   GCP                      Mac Mini
     |                        |                           |
     | Email                  |                           |
     +----------------------->|                           |
     |              +---------+----------+                |
     |              | Gmail API          |                |
     |              | Pub/Sub push       |                |
     |              +---------+----------+                |
     |                        |                           |
     |              +---------+----------+                |
     |              | Botti Voice        |                |
     |              | (webhook receiver) |                |
     |              +---------+----------+                |
     |                        |                           |
     |              +---------+----------+                |
     |              | Firestore          |                |
     |              | nanoclaw-signals/  |                |
     |              | {instance}/gmail   |                |
     |              +---------+----------+                |
     |                        |                           |
     |                        |  poll (5s)                |
     |                        +-------------------------->|
     |                        |                           |
     |                        |           +---------------+--------+
     |                        |           | Gmail API: messages.get |
     |                        |           +---------------+--------+
     |                        |                           |
     |                        |           +---------------+--------+
     |                        |           | isAutomatedEmail filter |
     |                        |           | - noreply, marketing   |
     |                        |           | - newsletter           |
     |                        |           +---------------+--------+
     |                        |                           |
     |                        |           Passe -> processGroupMessages
     |                        |                           |
     |                        |           +---------------+--------+
     |                        |           | Container + Claude     |
     |                        |           | Reponse via gws CLI    |
     |                        |           +------------------------+
```

**Fallback** : Si aucun signal Firestore n'arrive dans les 5 minutes
(`GMAIL_WEBHOOK_FALLBACK_POLL_MS = 300000`), NanoClaw interroge l'API Gmail directement.

### Google Chat (tous les agents)

```
 Utilisateur Chat           GCP                       Mac Mini
     |                       |                            |
     | @Botti question       |                            |
     +---------------------->|                            |
     |             +---------+---------+                  |
     |             | Google Chat App   |                  |
     |             | (webhook HTTP)    |                  |
     |             +---------+---------+                  |
     |                       |                            |
     |             +---------+---------+                  |
     |             | Chat Gateway      |                  |
     |             | (Cloud Run)       |                  |
     |             | FastAPI, rate     |                  |
     |             | limit, route      |                  |
     |             +---------+---------+                  |
     |                       |                            |
     |             +---------+---------+                  |
     |             | Firestore         |                  |
     |             | nanoclaw-messages/ |                  |
     |             | {agent}/google-   |                  |
     |             | chat              |                  |
     |             +---------+---------+                  |
     |                       |                            |
     |                       |  poll (5s)                 |
     |                       +--------------------------->|
     |                       |                            |
     |                       |          +-----------------+------+
     |                       |          | GoogleChatChannel      |
     |                       |          | pollFirestore()        |
     |                       |          +-----------------+------+
     |                       |                            |
     |                       |          Container + Claude|
     |                       |                            |
     |                       |          Chat API          |
     |  Reponse dans le space|<---------------------------+
     |<----------------------+                            |
```

**Routage** : Le Chat Gateway utilise un mapping `space -> agent` stocke dans Firestore
(`chat-config/space-mapping`). Chaque space Google Chat est assigne a un agent specifique.
Le champ `agentName` dans chaque message Firestore permet a chaque instance NanoClaw de
ne lire que ses propres messages.

### Botti Voice

```
 Yacine (navigateur)         Cloud Run                 Mac Mini
     |                          |                          |
     | WebSocket audio          |                          |
     +------------------------->|                          |
     |                +---------+---------+                |
     |                | Botti Voice       |                |
     |                | (FastAPI +        |                |
     |                |  Gemini Live)     |                |
     |                +---------+---------+                |
     |                          |                          |
     |                Agent selector                       |
     |                (Botti/Sam/Thais)                    |
     |                          |                          |
     |                Unified memory                       |
     |                (CLAUDE.md mounts)                   |
     |                          |                          |
     | Audio reponse            |                          |
     |<-------------------------+                          |
     |                          |                          |
     |                (Optionnel: send_email via Gmail API)|
     |                          |                          |
```

Botti Voice est une application web audio en temps reel. Elle utilise l'API Gemini Live
pour la conversation vocale, avec la memoire unifiee de NanoClaw (les fichiers CLAUDE.md
des agents sont montes dans le container Cloud Run).

## 2.3 Architecture interne d'une instance NanoClaw

Chaque instance NanoClaw est un processus Node.js unique qui orchestre plusieurs
sous-systemes independants :

```
+--------------------------------------------------------------+
|  NanoClaw Instance (ex: Botti, port 3001)                    |
|                                                               |
|  +------------------+   +------------------+                  |
|  | Channel Manager  |   |   State (SQLite) |                  |
|  |                  |   |  - messages       |                  |
|  |  +-----------+   |   |  - sessions       |                  |
|  |  | WhatsApp  |   |   |  - groups         |                  |
|  |  +-----------+   |   |  - router state   |                  |
|  |  +-----------+   |   +------------------+                  |
|  |  |   Gmail   |   |                                         |
|  |  +-----------+   |   +------------------+                  |
|  |  +-----------+   |   | Credential Proxy |                  |
|  |  | Google    |   |   | :3001            |                  |
|  |  |  Chat     |   |   |  /health         |                  |
|  |  +-----------+   |   |  /metrics         |                  |
|  +------------------+   |  API passthrough  |                  |
|                         |  Circuit breaker  |                  |
|  +------------------+   |  Daily spend      |                  |
|  | Message Loop     |   +------------------+                  |
|  | (poll DB, 2s)    |                                         |
|  +------------------+   +------------------+                  |
|                         | Task Scheduler   |                  |
|  +------------------+   | (poll DB, 60s)   |                  |
|  | IPC Watcher      |   +------------------+                  |
|  | (poll fs, 1s)    |                                         |
|  +------------------+   +------------------+                  |
|                         | Group Queue      |                  |
|  +------------------+   | (max 5 parallel) |                  |
|  | Message Processor|   +------------------+                  |
|  | (format, spawn)  |                                         |
|  +------------------+                                         |
+--------------------------------------------------------------+
        |
        v
+-------------------+
| Docker Container  |
| (Linux, --rm,     |
|  --network none)  |
| Claude Agent SDK  |
+-------------------+
```

**Fichiers cles et leurs roles** :

| Fichier                   | Role                                              | Lignes |
|--------------------------|---------------------------------------------------|--------|
| `index.ts`               | Orchestrateur, wiring, startup, shutdown          | ~175   |
| `state.ts`               | Gestion etat (timestamps, sessions, groupes)      | ~110   |
| `message-processor.ts`   | Traitement messages, spawn containers             | ~300   |
| `channel-manager.ts`     | Init canaux, callbacks, remote control            | ~180   |
| `config.ts`              | Configuration depuis .env (non-secrets)           | ~85    |
| `constants.ts`           | Constantes centralisees par domaine               | ~65    |
| `types.ts`               | Interfaces TypeScript                             | ~110   |
| `db.ts`                  | Operations SQLite                                 | ~400   |
| `credential-proxy.ts`    | Proxy HTTP, circuit breaker, daily spend          | ~400   |
| `container-runner.ts`    | Spawn containers, mounts, output parsing          | ~500   |
| `container-runtime.ts`   | Detection runtime, orphan cleanup                 | ~120   |
| `mount-security.ts`      | Validation mounts additionnels                    | ~430   |
| `group-queue.ts`         | File d'attente concurrence                        | ~390   |
| `message-loop.ts`        | Boucle de polling messages                        | ~130   |
| `task-scheduler.ts`      | Execution taches planifiees                       | ~200   |
| `ipc.ts`                 | Watcher IPC file-based                            | ~250   |
| `router.ts`              | Formatage et routage messages                     | ~200   |
| `anti-spam.ts`           | Detection rate limit, cooldown                    | ~45    |
| `backoff.ts`             | Calcul backoff exponentiel                        | ~10    |
| `metrics.ts`             | Registre Prometheus                               | ~225   |
| `logger.ts`              | Pino structured logging                           | ~22    |
| `env-validation.ts`      | Validation Zod au demarrage                       | ~175   |
| `sender-allowlist.ts`    | Allowlist expediteurs                             | ~150   |
| `remote-control.ts`      | Remote Control Claude Code                        | ~150   |
| `channels/whatsapp.ts`   | Canal WhatsApp                                    | ~500   |
| `channels/gmail.ts`      | Canal Gmail                                       | ~600   |
| `channels/google-chat.ts`| Canal Google Chat                                 | ~500   |
| `channels/registry.ts`   | Registre de canaux                                | ~30    |

---

# 3. Les 4 agents

## 3.1 Botti

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| Role              | Assistant personnel de Yacine                    |
| Email             | yacine@bestoftours.co.uk                         |
| Modele            | claude-opus-4-6                                  |
| Port proxy        | 3001                                             |
| Canaux            | WhatsApp, Gmail, Google Chat, Voice              |
| Instance dir      | `/Users/boty/nanoclaw`                           |
| Launchd           | `com.nanoclaw`                                   |
| Prefix container  | `nanoclaw`                                       |

**Role detaille** : Botti est l'agent principal. Il est le seul a avoir WhatsApp et Voice.
C'est lui qui recoit les commandes de Remote Control, qui a acces au projet NanoClaw en
lecture seule dans son container (main group), et qui sert de canal d'alerte pour le watchdog.

**CLAUDE.md resume** : Francais par defaut, tutoie Yacine, factuel et direct. Connait
l'organisation (Botler 360, Best of Tours), l'equipe de direction (Eline, Ahmed), et les
regles d'email (interne = direct, externe = brouillon + confirmation).

## 3.2 Sam

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| Role              | Assistant operationnel                           |
| Email             | sam@bestoftours.co.uk                            |
| Modele            | claude-opus-4-6                                  |
| Port proxy        | 3003                                             |
| Canaux            | Gmail, Google Chat                               |
| Instance dir      | `/Users/boty/nanoclaw-sam`                       |
| Launchd           | `com.nanoclaw.sam`                                |
| Prefix container  | `nanoclaw-sam`                                   |

**Role detaille** : Sam gere les operations courantes via email et Chat. Il peut traiter
les demandes de l'equipe, gerer le calendrier, rechercher des documents dans Drive.

## 3.3 Thais

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| Role              | Assistante de direction                          |
| Email             | thais@bestoftours.co.uk                          |
| Modele            | claude-opus-4-6                                  |
| Port proxy        | 3002                                             |
| Canaux            | Gmail, Google Chat                               |
| Instance dir      | `/Users/boty/nanoclaw-thais`                     |
| Launchd           | `com.nanoclaw.thais`                              |
| Prefix container  | `nanoclaw-thais`                                 |

**Role detaille** : Thais assiste la direction. Memes capacites email/Chat que Sam, avec
un CLAUDE.md adapte a son role de support de direction.

## 3.4 Alan

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| Role              | Assistant operationnel                           |
| Email             | ala@bestoftours.co.uk                            |
| Modele            | claude-opus-4-6                                  |
| Port proxy        | 3004                                             |
| Canaux            | Gmail, Google Chat                               |
| Instance dir      | `/Users/boty/nanoclaw-alan`                      |
| Launchd           | `com.nanoclaw.alan`                               |
| Prefix container  | `nanoclaw-alan`                                  |

**Role detaille** : Alan est le dernier agent ajoute. Il assiste les operations via
email et Chat, comme Sam.

## 3.5 Regles communes a tous les agents

Tous les agents partagent ces regles (definies dans le CLAUDE.md template de `create-agent.sh`) :

1. **Langue** : Francais par defaut, anglais si le contexte l'exige
2. **Ton** : Factuel, direct, dense. Zero flatterie
3. **Tutoiement** : Yacine et l'equipe interne. Vouvoiement des contacts externes
4. **Emails internes** (`@bestoftours.co.uk`) : envoi direct
5. **Emails externes** : reformulation + attente de confirmation
6. **Signature** : "Nom -- Best of Tours" ou "Nom -- Botler 360" selon le contexte
7. **Confidentialite** : Ne jamais partager d'informations financieres, RH, contractuelles
8. **Proactivite** : Toujours donner le "et ensuite ?" -- l'etape d'apres
9. **Formatage** : WhatsApp/Chat formatting (*bold*, _italic_, bullet points), pas de markdown

## 3.6 Regles specifiques a Botti

En plus des regles communes, Botti a :

- Acces au Remote Control (commande `/remote-control` via WhatsApp, protege par PIN)
- Acces en lecture seule au projet NanoClaw dans son container (main group)
- Cross-posting Google Chat -> WhatsApp (et vice-versa)
- Canal d'alerte du watchdog

---

# 4. Les canaux de communication

## 4.1 Architecture des canaux

Les canaux sont des modules qui s'auto-enregistrent au demarrage via le pattern
registry/factory :

```
src/channels/
  index.ts          -- barrel import (declenche l'auto-enregistrement)
  registry.ts       -- Map<name, factory> + registerChannel() + getChannelFactory()
  whatsapp.ts       -- canal WhatsApp (Baileys)
  gmail.ts          -- canal Gmail (OAuth2 + Firestore webhook)
  google-chat.ts    -- canal Google Chat (Firestore polling + Chat API)
```

Chaque canal implemente l'interface `Channel` :

```typescript
interface Channel {
  name: string;
  connect(): Promise<void>;
  sendMessage(jid: string, text: string): Promise<void>;
  isConnected(): boolean;
  ownsJid(jid: string): boolean;
  disconnect(): Promise<void>;
  setTyping?(jid: string, isTyping: boolean): Promise<void>;
  syncGroups?(force: boolean): Promise<void>;
}
```

## 4.2 WhatsApp

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| Bibliotheque      | @whiskeysockets/baileys 7.0.0-rc.9               |
| Protocole         | WebSocket (Multi-Device)                         |
| Auth              | QR code ou pairing code                          |
| Agent(s)          | Botti uniquement                                 |
| Poll interval     | 2s (configurable via POLL_INTERVAL)              |
| Group sync        | 24h (GROUP_SYNC_INTERVAL_MS)                     |

**Fonctionnement** :
1. Baileys etablit une connexion WebSocket avec les serveurs WhatsApp
2. Les messages entrants declenchent `onMessage(chatJid, msg)`
3. Les messages sont stockes dans SQLite
4. Le Message Loop detecte les nouveaux messages et les met en queue
5. Le container agent traite et repond

**Authentification** :
- Premiere connexion : QR code affiche dans le terminal (`npm run auth`)
- Sessions persistees dans `data/sessions/whatsapp_main/`
- Reconnexion automatique en cas de deconnexion

**Fonctionnalites** :
- Indicateur de frappe (typing indicator)
- Synchronisation des groupes et contacts
- Reactions emoji (skill `/add-reactions`)
- Vision d'images (skill `/add-image-vision`)
- Transcription vocale (skill `/add-voice-transcription`)
- Telechargement de medias (images, documents, audio)

## 4.3 Gmail

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| API               | Gmail API v1 (googleapis)                        |
| Auth              | OAuth2 (refresh token)                           |
| Agent(s)          | Tous (Botti, Sam, Thais, Alan)                   |
| Mode              | Dual : polling + webhook Firestore               |
| Poll (webhook on) | 5min fallback (GMAIL_WEBHOOK_FALLBACK_POLL_MS)   |
| Poll (webhook off)| Configurable via POLL_INTERVAL                   |
| Signal poll       | 5s (FIRESTORE_SIGNAL_POLL_MS)                    |

**Mode dual polling/webhook** :

Le canal Gmail supporte deux modes simultanes :

1. **Webhook via Pub/Sub** : Gmail envoie une notification push au topic Pub/Sub
   `gmail-push`. Botti Voice (Cloud Run) recoit cette notification et ecrit un
   signal dans Firestore (`nanoclaw-signals/{instance}/gmail-webhook`). NanoClaw
   poll Firestore toutes les 5 secondes et, quand un signal arrive, interroge
   l'API Gmail pour les nouveaux messages.

2. **Polling direct** : Si aucun signal Firestore n'arrive dans les 5 minutes,
   NanoClaw fait un poll direct de l'API Gmail. C'est le mode de secours.

**Filtrage des emails automatiques** :

Avant de transmettre un email a l'agent, le canal Gmail filtre :
- `noreply@`, `no-reply@`, `mailer-daemon@`
- Emails de newsletters (headers `List-Unsubscribe`)
- Emails marketing (headers `X-Marketing`, `X-Campaign`)
- Adresses dans des listes de blocage configurables

Metrique : `nanoclaw_emails_filtered_total` avec label `reason`.

**Securite d'envoi** :

L'envoi d'email par les agents est controle par une allowlist externe :
- Fichier : `~/.config/nanoclaw/gmail-send-allowlist.json`
- Format : `{ "direct_send": ["email1", ...], "notify_email": "...", "cc_email": "..." }`
- **Emails dans `direct_send`** : envoi direct autorise
- **Emails hors liste** : creation d'un brouillon + notification a `notify_email`
- Cache TTL : 60 secondes (GMAIL_ALLOWLIST_CACHE_TTL_MS)

**Credentials** :
- Fichier OAuth : `~/.gmail-mcp-{agent}/credentials.json`
- Fichier client : `~/.gmail-mcp-{agent}/gcp-oauth.keys.json`
- Scopes : `https://mail.google.com/`, `calendar`, `drive.readonly`

## 4.4 Google Chat

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| API               | Google Chat API v1                               |
| Auth              | Service Account (Firebase/GCP)                   |
| Agent(s)          | Tous                                             |
| Poll              | 5s (GOOGLE_CHAT_POLL_MS)                         |
| Gateway           | Chat Gateway (Cloud Run, FastAPI)                |

**Architecture du routage** :

Il y a **un seul Chat App** ("Botti") enregistre dans Google Workspace. Tous les messages
Chat passent par ce Chat App, qui est configure pour envoyer les webhooks au Chat Gateway
(Cloud Run).

Le Chat Gateway :
1. Recoit le webhook HTTP de Google Chat
2. Verifie le token de verification (`CHAT_VERIFICATION_TOKEN`)
3. Determine l'agent cible via le mapping `space -> agent` dans Firestore
4. Ecrit le message dans Firestore : `nanoclaw-messages/{agent}/google-chat`
5. L'instance NanoClaw correspondante poll Firestore et traite le message

**Mapping des spaces** :
- Stocke dans Firestore : `chat-config/space-mapping`
- Format : `{ "spaces/XXX": "sam", "spaces/YYY": "botti" }`
- Editable en direct (modifiable via l'endpoint admin du gateway ou directement dans Firestore)
- Agents valides : `botti`, `sam`, `thais`, `alan`
- Agent par defaut si non mappe : `botti`

**Permissions par utilisateur** :

L'acces aux agents via Google Chat est controle par des regles par utilisateur,
definies dans le CLAUDE.md de chaque agent et appliquees par le Chat Gateway.
Les utilisateurs autorises incluent Yacine, Eline et Ahmed.

**Detection de presence** :

Le gateway maintient un cache de presence de Yacine dans chaque space (TTL 1 heure).
Le champ `yacinePresent` dans les messages Firestore permet aux agents de savoir si
Yacine est dans le space et d'adapter leur comportement.

**Cross-posting** :

Quand un message Google Chat declenche une reponse, celle-ci est aussi envoyee dans le
groupe WhatsApp correspondant via le tracking `lastGchatReplyTarget`. Cela permet a
Yacine de recevoir les reponses des agents dans WhatsApp meme s'il a initie la
conversation depuis Chat.

**Rate limiting** :

Le Chat Gateway applique un rate limit en memoire :
- Endpoints chat : 60 requetes/minute par IP
- Endpoints admin : 10 requetes/minute par IP

## 4.5 Botti Voice

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| Framework         | FastAPI (Python)                                 |
| Modele IA         | Gemini 2.5 Flash (native audio)                  |
| Deploiement       | Cloud Run                                        |
| Protocole         | WebSocket (audio bidirectionnel)                 |

**Fonctionnement** :
- Interface web qui ouvre un WebSocket audio vers le serveur
- `GeminiBridge` transmet l'audio au modele Gemini Live en temps reel
- Reponse audio generee et streamee vers le navigateur
- Agent selector : l'utilisateur peut choisir quel agent (Botti/Sam/Thais) parle
- Memoire unifiee : les fichiers CLAUDE.md des agents NanoClaw sont montes dans le
  container Cloud Run et charges au demarrage de chaque session

**Configuration** (extraite de `botti-voice/web/config.py`) :

```python
GEMINI_MODEL = "models/gemini-2.5-flash-native-audio-latest"
NANOCLAW_MEMORY_PATHS = {
    "botti": "/app/memory/botti/CLAUDE.md",
    "sam": "/app/memory/sam/CLAUDE.md",
    "thais": "/app/memory/thais/CLAUDE.md",
}
VOICE_PREAMBLE = "Tu es en mode vocal. Tutoie toujours Yacine..."
```

**Preamble vocal** :
- Tutoiement obligatoire
- Francais par defaut, anglais si contexte
- Reponses courtes (3-4 phrases max)
- Pas de markdown (mode vocal)
- Maximum 3 items dans les listes

---

# 5. Containers et isolation

## 5.1 Image Docker

L'image `nanoclaw-agent:latest` est construite avec `container/build.sh`. Elle contient :

- Node.js + npm
- Claude Code CLI (installe globalement)
- Chromium headless (pour `agent-browser`)
- `gws` CLI (Google Workspace)
- `git`
- pdftotext, whisper (optionnel)

L'image est partagee par tous les agents. Le container est cree `--rm` (auto-supprime a
la fin) et `--network none` (pas d'acces Internet direct).

## 5.2 Cycle de vie du container

```
processGroupMessages(chatJid)
     |
     v
runContainerAgent(group, input)
     |
     +-- buildVolumeMounts(group, isMain)
     |     Determine les mounts selon le type de groupe
     |
     +-- buildContainerArgs(mounts, containerName)
     |     Construit les arguments docker run
     |
     v
spawn("docker", ["run", ...args])
     |
     +-- stdin.write(prompt)          <- envoie le prompt formate
     |
     +-- stdout streaming             <- parse les resultats JSON
     |     { result: "...", status: "success" | "error" }
     |     { newSessionId: "..." }
     |
     +-- idle timeout (30min)         <- ferme stdin si agent inactif
     |
     +-- process exit                 <- --rm auto-supprime le container
     |
     v
GroupQueue: activeCount--, drain next
```

## 5.3 Mounts (volumes)

### Main group (Botti)

| Mount container              | Chemin host                          | Mode  |
|-----------------------------|--------------------------------------|-------|
| `/workspace/project`        | `/Users/boty/nanoclaw/`              | RO    |
| `/workspace/project/.env`   | `/dev/null`                          | RO    |
| `/workspace/group`          | `groups/{folder}/`                   | RW    |
| `/workspace/data`           | `data/{folder}/`                     | RW    |
| `/home/user/.claude/`       | `data/sessions/{folder}/.claude/`    | RW    |
| `/workspace/extra/*`        | Mounts additionnels (allowlist)      | Var.  |

### Non-main groups

| Mount container              | Chemin host                          | Mode  |
|-----------------------------|--------------------------------------|-------|
| `/workspace/group`          | `groups/{folder}/`                   | RW    |
| `/workspace/global`         | `groups/global/`                     | RO    |
| `/home/user/.claude/`       | `data/sessions/{folder}/.claude/`    | RW    |
| `/workspace/extra/*`        | Mounts additionnels (allowlist)      | Var.  |

### Shadowing du .env

Le fichier `.env` est toujours masque par un mount de `/dev/null`. Les containers ne
voient jamais les secrets (API keys, tokens). Les credentials sont injectees par le
credential proxy.

## 5.4 Credential Proxy

Le credential proxy est un serveur HTTP local qui sert d'intermediaire entre les containers
et l'API Anthropic.

| Propriete          | Valeur                                           |
|-------------------|--------------------------------------------------|
| Port              | Configurable (3001-3004 selon l'instance)        |
| Bind              | `127.0.0.1` (ou `host.docker.internal`)          |
| Modes d'auth      | API Key ou OAuth                                 |

**Fonctionnement** :
1. Le container voit `ANTHROPIC_BASE_URL=http://host.docker.internal:{port}`
2. Le container envoie ses requetes API a cette URL sans credentials
3. Le proxy intercepte la requete et injecte la vraie API key / OAuth token
4. Le proxy forward la requete a `api.anthropic.com`
5. Le proxy parse la reponse pour tracker l'usage (tokens)

**Endpoints** :
- `GET /health` : Health check (retourne status des canaux, groupes, uptime)
- `GET /metrics` : Metriques Prometheus (text exposition format)
- `*` : Tout le reste est proxifie vers l'API Anthropic

**Daily spend tracking** :
- Le proxy parse les reponses pour extraire `usage.input_tokens` et `usage.output_tokens`
- Calcul du cout estime : `(input/1M) * 3.0 + (output/1M) * 15.0` USD
- Limite configurable : `DAILY_API_LIMIT_USD` (defaut : 20 USD)
- Quand la limite est atteinte, le proxy bloque les nouvelles requetes
- L'etat est persiste dans `store/daily-spend.json` et reinitialise chaque jour

## 5.5 Circuit Breaker

Le credential proxy implemente un circuit breaker pour proteger contre les cascades
d'erreurs lors des pannes de l'API Anthropic :

```
  CLOSED  ──5 erreurs 5xx──>  OPEN
    ^                           |
    |                      60s timeout
    |                           |
    +──succes──  HALF-OPEN  <──+
    |                |
    +──echec (5xx)───+
```

| Parametre         | Valeur                                           |
|-------------------|--------------------------------------------------|
| Seuil d'ouverture | 5 erreurs 5xx consecutives (CIRCUIT_BREAKER_THRESHOLD) |
| Timeout reset     | 60 secondes (CIRCUIT_BREAKER_RESET_MS)            |
| Etat initial      | `closed`                                         |

**Etats** :
- `closed` : Normal, toutes les requetes passent
- `open` : Bloque toutes les requetes (retourne 503)
- `half-open` : Laisse passer une requete "probe" pour tester si le service est revenu

## 5.6 Variables d'environnement du container

| Variable                    | Valeur                                        |
|----------------------------|-----------------------------------------------|
| `ANTHROPIC_BASE_URL`       | `http://host.docker.internal:{port}`          |
| `CLAUDE_MODEL`             | Modele configure dans .env                    |
| `ASSISTANT_NAME`           | Nom de l'agent                                |
| `HOME`                     | `/home/user`                                  |
| `TZ`                       | Timezone du host                              |

Le container **n'a jamais** :
- `ANTHROPIC_API_KEY`
- `CLAUDE_CODE_OAUTH_TOKEN`
- Les secrets .env du host

## 5.7 Group Queue (concurrence)

La GroupQueue gere la concurrence des containers :

- Maximum 5 containers simultanement (configurable via `MAX_CONCURRENT_CONTAINERS`)
- File d'attente par groupe (un seul container par groupe a la fois)
- 5 retries avec backoff exponentiel (base 5s, GROUP_QUEUE_MAX_RETRIES = 5)
- Shutdown graceful avec timeout de 10 secondes
- Nettoyage des orphelins au demarrage

### Architecture interne de la GroupQueue

La GroupQueue maintient un etat par groupe (`GroupState`) :

```typescript
interface GroupState {
  active: boolean;           // Un container tourne pour ce groupe
  idleWaiting: boolean;      // Container en attente de nouvelles instructions
  isTaskContainer: boolean;  // Container execute une tache planifiee (pas un message)
  runningTaskId: string | null;  // ID de la tache en cours
  pendingMessages: boolean;  // Messages en attente de traitement
  pendingTasks: QueuedTask[];    // Taches en attente
  process: ChildProcess | null;  // Processus Docker
  containerName: string | null;  // Nom du container (pour logs/cleanup)
  groupFolder: string | null;    // Dossier du groupe (pour IPC)
  retryCount: number;            // Nombre de retries consecutifs
}
```

### Algorithme de priorite

Quand un container termine :
1. **Taches planifiees d'abord** : Les taches ne sont pas redecouvertes par le polling
   (contrairement aux messages), elles doivent donc etre prioritaires
2. **Messages ensuite** : Les messages sont redecouvrables depuis SQLite
3. **Drain global** : Si le groupe n'a rien en attente, libere le slot pour les groupes
   en attente de la file globale

### Mecanisme de piping

Quand un container est deja actif pour un groupe et que de nouveaux messages arrivent,
la GroupQueue peut "piper" les messages directement dans le container actif via l'IPC
file-based :

1. Le Message Loop detecte de nouveaux messages pour un groupe avec container actif
2. Il appelle `queue.sendMessage(chatJid, formattedText)`
3. La queue ecrit un fichier JSON dans `data/ipc/{folder}/input/`
4. Le container (via agent-runner) detecte le fichier et le transmet a Claude
5. Claude repond sans avoir a relancer un nouveau container

Cela reduit drastiquement la latence pour les conversations en cours.

### Shutdown graceful

Au shutdown, la GroupQueue ne tue **pas** les containers actifs. Elle les detache
et laisse le flag `--rm` et le idle timeout gerer le nettoyage. Cela evite de
couper un agent en plein milieu d'une reponse si le host process redemarre
(courant avec WhatsApp qui force des reconnexions).

### Backoff exponentiel sur les retries

En cas d'echec du traitement d'un groupe :

| Retry | Delai                            |
|-------|----------------------------------|
| 1     | 5s (BASE_RETRY_MS)               |
| 2     | 10s                              |
| 3     | 20s                              |
| 4     | 40s                              |
| 5     | 80s                              |
| 6+    | Abandon (reset au prochain message entrant) |

## 5.8 IPC (Inter-Process Communication)

Le systeme IPC permet la communication bidirectionnelle entre le host NanoClaw et les
containers Docker via le systeme de fichiers :

### Structure des repertoires IPC

```
data/ipc/
  {groupFolder}/
    messages/           -- Messages sortants (container -> host)
      {timestamp}.json  -- { "type": "send", "jid": "...", "text": "..." }
    tasks/              -- Commandes de taches (container -> host)
      {timestamp}.json  -- { "action": "create|update|delete", ... }
    input/              -- Messages entrants (host -> container)
      {timestamp}.json  -- { "type": "message", "text": "..." }
      _close            -- Sentinel pour fermer le container
```

### Cycle de vie

1. Le container cree un fichier JSON dans `messages/` ou `tasks/`
2. Le IPC Watcher (`ipc.ts`) poll ces repertoires toutes les secondes (`IPC_POLL_INTERVAL`)
3. Il lit, traite et supprime chaque fichier
4. Les erreurs sont deplacees dans un dossier `errors/`

### Rate limiting IPC

Chaque groupe est limite a 20 taches actives (`MAX_TASKS_PER_GROUP`). Au-dela,
les nouvelles creations de taches sont rejetees avec un message d'erreur.

### Actions supportees

| Action          | Direction           | Description                              |
|----------------|---------------------|------------------------------------------|
| `send_message` | container -> host   | Envoi d'un message a un chat             |
| `schedule_task`| container -> host   | Creation d'une tache planifiee           |
| `update_task`  | container -> host   | Modification d'une tache existante       |
| `delete_task`  | container -> host   | Suppression d'une tache                  |
| `register`     | container -> host   | Enregistrement d'un nouveau groupe       |
| `sync_groups`  | container -> host   | Synchronisation des groupes disponibles  |
| `message`      | host -> container   | Envoi d'un message au container actif    |
| `_close`       | host -> container   | Demande de fermeture du container        |

## 5.9 Container Runtime Abstraction

Le module `container-runtime.ts` abstrait les specificites du runtime Docker :

- **Detection du bind host** : `127.0.0.1` sur macOS/WSL, IP du bridge `docker0` sur Linux
- **Host gateway** : `host.docker.internal` (ajout explicite sur Linux via `--add-host`)
- **Verification au demarrage** : `docker info` pour verifier que Docker est lance
- **Nettoyage des orphelins** : `docker ps --filter name={prefix}` pour trouver et
  tuer les containers d'une session precedente

L'abstraction est concue pour faciliter un eventuel switch vers Apple Container
(skill `/convert-to-apple-container`) -- il suffit de modifier ce fichier.

---

# 6. Memoire et persistance

## 6.1 CLAUDE.md (memoire de l'agent)

Chaque groupe a un fichier `CLAUDE.md` dans son dossier `groups/{folder}/CLAUDE.md`.
C'est la memoire principale de l'agent pour ce groupe. Elle contient :

- L'identite et le ton de l'agent
- Les informations sur l'organisation
- Les regles de comportement
- Les preferences de l'utilisateur
- Un index des fichiers de memoire crees par l'agent

L'agent peut modifier ce fichier pour mettre a jour sa memoire. Les modifications
persistent entre les sessions grace au mount RW du dossier groupe.

### Memoire globale

Le dossier `groups/global/` contient un CLAUDE.md partage entre tous les groupes
d'une instance. Il est monte en lecture seule pour les non-main groups.

### Memoire auto

Claude Code a sa propre fonctionnalite de memoire auto (`CLAUDE_CODE_DISABLE_AUTO_MEMORY=0`).
Les preferences apprises sont stockees dans `data/sessions/{folder}/.claude/`.

## 6.2 SQLite

Chaque instance a sa propre base de donnees SQLite : `store/messages.db`

### Tables

| Table               | Role                                            |
|--------------------|-------------------------------------------------|
| `chats`            | Metadonnees des conversations (jid, nom, canal) |
| `messages`         | Tous les messages recus et envoyes              |
| `scheduled_tasks`  | Taches planifiees (cron, interval, once)        |
| `task_run_logs`    | Historique d'execution des taches               |
| `router_state`     | Etat du routeur (last_timestamp, curseurs)      |
| `sessions`         | Session Claude par groupe (session_id)          |
| `registered_groups`| Groupes enregistres et leur configuration       |

### Schema des tables principales

```sql
-- Messages
CREATE TABLE messages (
  id TEXT,
  chat_jid TEXT,
  sender TEXT,
  sender_name TEXT,
  content TEXT,
  timestamp TEXT,
  is_from_me INTEGER,
  is_bot_message INTEGER DEFAULT 0,
  PRIMARY KEY (id, chat_jid)
);

-- Taches planifiees
CREATE TABLE scheduled_tasks (
  id TEXT PRIMARY KEY,
  group_folder TEXT NOT NULL,
  chat_jid TEXT NOT NULL,
  prompt TEXT NOT NULL,
  schedule_type TEXT NOT NULL,   -- 'cron', 'interval', 'once'
  schedule_value TEXT NOT NULL,  -- crontab expression, interval ms, ISO date
  next_run TEXT,
  last_run TEXT,
  last_result TEXT,
  status TEXT DEFAULT 'active',  -- 'active', 'paused', 'completed'
  created_at TEXT NOT NULL,
  context_mode TEXT DEFAULT 'isolated'  -- 'group', 'isolated'
);

-- Groupes enregistres
CREATE TABLE registered_groups (
  jid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  folder TEXT NOT NULL UNIQUE,
  trigger_pattern TEXT NOT NULL,
  added_at TEXT NOT NULL,
  container_config TEXT,
  requires_trigger INTEGER DEFAULT 1,
  is_main INTEGER DEFAULT 0
);
```

## 6.3 Firestore

Firestore est utilise pour la communication entre les services Cloud Run et NanoClaw.

### Collections

| Collection            | Usage                                          |
|----------------------|------------------------------------------------|
| `nanoclaw-messages`  | Messages Google Chat (par agent/canal)         |
| `nanoclaw-signals`   | Signaux Gmail webhook (par instance)           |
| `chat-config`        | Configuration du Chat Gateway                  |

### Structure des documents

**nanoclaw-messages/{agent}/google-chat** :
```json
{
  "spaceId": "spaces/XXX",
  "spaceName": "Mon Espace",
  "messageId": "msg_123",
  "messageName": "spaces/XXX/messages/msg_123",
  "text": "Hello @Botti",
  "senderName": "Yacine",
  "senderEmail": "yacine@bestoftours.co.uk",
  "senderType": "HUMAN",
  "createTime": "2026-04-04T10:00:00Z",
  "agentName": "botti",
  "yacinePresent": true,
  "processed": false
}
```

**nanoclaw-signals/{instance}/gmail-webhook** :
```json
{
  "timestamp": "2026-04-04T10:00:00Z",
  "historyId": "12345"
}
```

**chat-config/space-mapping** :
```json
{
  "spaces/ABC123": "botti",
  "spaces/DEF456": "sam",
  "spaces/GHI789": "thais"
}
```

## 6.4 Sessions Claude

Chaque groupe maintient une session Claude persistante. L'ID de session est stocke dans
la table `sessions` de SQLite et passe au container au demarrage. Cela permet a Claude
de reprendre le contexte d'une conversation precedente.

Les fichiers de session Claude sont stockes dans `data/sessions/{folder}/.claude/` et
montes dans le container en RW.

## 6.5 Task Scheduler (taches planifiees)

Le task scheduler (`task-scheduler.ts`) execute des taches recurrentes et ponctuelles :

### Types de taches

| Type       | schedule_value                | Exemple                          |
|-----------|-------------------------------|----------------------------------|
| `cron`    | Expression crontab            | `0 9 * * 1-5` (9h LUN-VEN)     |
| `interval`| Intervalle en millisecondes   | `3600000` (toutes les heures)    |
| `once`    | Date ISO 8601                 | `2026-04-05T10:00:00Z`           |

### Fonctionnement

1. Le scheduler poll la DB toutes les 60s (`SCHEDULER_POLL_INTERVAL`)
2. Il interroge `getDueTasks()` pour les taches dont `next_run <= now`
3. Pour chaque tache due, il la met en queue dans la GroupQueue
4. Le container agent execute la tache avec le prompt configure
5. Apres execution, `computeNextRun()` calcule la prochaine execution
6. Les taches `once` passent a `status = 'completed'`
7. Le resultat est journalise dans `task_run_logs`

### Anti-drift pour les intervalles

Le calcul de `next_run` pour les taches intervalle est ancre sur l'heure prevue
originale, pas sur `Date.now()`. Cela evite la derive cumulative :

```typescript
// Ancrage sur le temps prevu, pas sur maintenant
let next = new Date(task.next_run!).getTime() + ms;
while (next <= now) {
  next += ms;  // Saute les executions manquees
}
```

### Contexte d'execution

Chaque tache a un `context_mode` :
- `group` : Execute dans le contexte du groupe (avec la session et la memoire)
- `isolated` : Execute dans un contexte vierge (pas de session precedente)

### Journalisation

Chaque execution est enregistree dans `task_run_logs` :
- `task_id` : Reference a la tache
- `run_at` : Horodatage
- `duration_ms` : Duree d'execution
- `status` : `success` ou `error`
- `result` / `error` : Sortie ou message d'erreur

## 6.6 Conversations (journal)

Les agents creent automatiquement un dossier `conversations/` dans leur workspace
(`groups/{folder}/conversations/`) pour archiver les conversations passees. C'est un
fichier Markdown par jour/sujet, consultable par l'agent pour rappeler du contexte.

## 6.6 Daily Spend

Le suivi des couts API est persiste dans `store/daily-spend.json` :

```json
{
  "date": "2026-04-04",
  "input_tokens": 1500000,
  "output_tokens": 50000,
  "estimated_usd": 5.25,
  "limit_hit": false
}
```

Reinitialise automatiquement chaque jour.

---

# 7. Securite

## 7.1 Vue d'ensemble

```
+--------------------------------------------------------------+
|  HOST                                                         |
|                                                               |
|  ~/.config/nanoclaw/                                          |
|    sender-allowlist.json    (qui peut trigger l'agent)        |
|    mount-allowlist.json     (quels chemins les containers     |
|                              peuvent voir)                    |
|    gmail-send-allowlist.json (qui l'agent peut emailer)       |
|    watchdog-state.json      (etat du watchdog)                |
|                                                               |
|  .env                                                         |
|    ANTHROPIC_API_KEY        (jamais monte dans les containers)|
|    CLAUDE_CODE_OAUTH_TOKEN  (jamais monte dans les containers)|
|    REMOTE_CONTROL_PIN       (jamais monte dans les containers)|
|                                                               |
|  +----------------------------------------------------------+|
|  | Credential Proxy (:3001-3004, 127.0.0.1 only)            ||
|  |  - Injecte API key / OAuth token dans les requetes        ||
|  |  - Circuit breaker (5 failures -> open for 60s)           ||
|  |  - Daily spend limiter ($20/jour par defaut)              ||
|  |  - Containers voient ANTHROPIC_BASE_URL=http://host:PORT  ||
|  |    mais jamais la vraie API key                            ||
|  +----------------------------------------------------------+|
+--------------------------------------------------------------+
         |
         v
+--------------------------------------------------------------+
| CONTAINER (Docker)                                            |
|  --network none     (pas d'acces Internet direct)             |
|  --rm               (auto-cleanup a la sortie)                |
|  .env shadow        (/dev/null monte sur .env)                |
|  Mounts valides     (uniquement les chemins de l'allowlist)   |
+--------------------------------------------------------------+
```

## 7.2 Isolation des credentials

Les containers n'ont **jamais** acces aux secrets :

1. **API Key** : Injectee par le credential proxy, jamais dans les variables d'environnement
   du container
2. **.env shadow** : Le fichier `.env` est masque par un mount `/dev/null` -> le container
   ne peut pas lire les secrets meme si le projet est monte en RO
3. **OAuth tokens** : Geres par le proxy, jamais exposes

## 7.3 Mount Security (allowlist)

Les mounts additionnels du container sont valides par `mount-security.ts` :

- **Allowlist** : `~/.config/nanoclaw/mount-allowlist.json`
- **Hot-reload** : Cache TTL de 60 secondes

### Processus de validation

Pour chaque mount additionnel demande :

1. **Chargement allowlist** : Lit le fichier JSON (cache 60s)
2. **Validation container path** : Pas de `..`, pas de chemin absolu, non vide
3. **Expansion du chemin** : `~` -> home directory
4. **Resolution des symlinks** : `fs.realpathSync()` pour dejouer les traversals
5. **Verification patterns bloques** : Le chemin reel ne doit contenir aucun pattern bloque
6. **Verification allowed roots** : Le chemin reel doit etre sous un root autorise
7. **Calcul readonly effectif** : Forcage en RO si `nonMainReadOnly` ou root sans RW

### Patterns bloques par defaut

```
.ssh, .gnupg, .gpg, .aws, .azure, .gcloud, .kube, .docker,
credentials, .env, .netrc, .npmrc, .pypirc, id_rsa, id_ed25519,
private_key, .secret
```

L'administrateur peut ajouter des patterns supplementaires dans `blockedPatterns`
de l'allowlist. Les patterns par defaut sont toujours inclus (merge).

### Format de l'allowlist

```json
{
  "allowedRoots": [
    {
      "path": "~/projects",
      "allowReadWrite": true,
      "description": "Development projects"
    },
    {
      "path": "~/Documents/work",
      "allowReadWrite": false,
      "description": "Work documents (read-only)"
    }
  ],
  "blockedPatterns": ["password", "secret", "token"],
  "nonMainReadOnly": true
}
```

### Securite anti-traversal

La resolution des symlinks est **obligatoire** avant toute validation. Sans cela,
un agent pourrait creer un symlink dans son workspace pointant vers `/etc/shadow`
et demander un mount sur ce symlink. `fs.realpathSync()` resout le chemin reel
et la validation s'applique sur le chemin final.

## 7.4 Sender Allowlist

Controle qui peut declencher l'agent via WhatsApp/Chat :

- **Fichier** : `~/.config/nanoclaw/sender-allowlist.json`
- **Modes** :
  - `trigger` : Le message est stocke mais n'active pas l'agent
  - `drop` : Le message est purement et simplement ignore
  - `*` : Tout le monde est autorise
- **Hot-reload** : Cache TTL de 5 secondes (SENDER_ALLOWLIST_CACHE_TTL_MS)

## 7.5 Gmail Send Safety

L'envoi d'email par les agents est doublement securise :

1. **Allowlist externe** : `~/.config/nanoclaw/gmail-send-allowlist.json`
   - `direct_send` : Liste des emails a qui l'agent peut envoyer directement
   - `notify_email` : Email de notification quand l'agent cree un brouillon
   - `cc_email` : CC automatique sur les emails sortants

2. **Draft mode** : Pour les destinataires hors allowlist, l'agent cree un brouillon
   au lieu d'envoyer directement, et notifie `notify_email` pour revue manuelle

## 7.6 Remote Control PIN

La commande `/remote-control` (qui donne acces a Claude Code sur le host) est protegee
par un PIN :

- Configure via `REMOTE_CONTROL_PIN` dans `.env`
- Minimum 4 caracteres
- Si non configure, le Remote Control est **desactive**
- Seul le main group peut l'utiliser
- Usage : `/remote-control <PIN>` dans WhatsApp

## 7.7 Chat Gateway Authentication

Le Chat Gateway (Cloud Run) a deux niveaux d'auth :

1. **Verification token** : `CHAT_VERIFICATION_TOKEN` pour valider les webhooks Google Chat
2. **Admin API key** : `ADMIN_API_KEY` pour les endpoints d'administration

## 7.8 IPC Rate Limiting

Le systeme IPC (file-based IPC entre le host et les containers) est limite :

- Maximum 20 taches actives par groupe (MAX_TASKS_PER_GROUP)
- Previent les agents de creer des boucles infinies de taches

## 7.9 Session ID Redaction

Les IDs de session sont automatiquement masques dans les logs structurs :

```typescript
const logger = pino({
  redact: ['sessionId', 'newSessionId', 'session_id'],
});
```

Cela empeche les IDs de session d'apparaitre dans les logs en clair.

## 7.10 Anti-spam

L'anti-spam protege contre les boucles d'erreurs :

- Detection des erreurs de rate limit (patterns : `hit your limit`, `rate_limit`, `429`, `overloaded`)
- Cooldown de 4 heures par JID entre les notifications d'erreur (ERROR_COOLDOWN_MS)
- Nettoyage des entrees obsoletes (>7 jours, STALE_ENTRY_MS)
- Message de fallback : "Je suis temporairement indisponible. Je reviens des que possible."

## 7.11 Network Isolation

Les containers Docker tournent avec `--network none` : aucun acces direct a Internet.
La seule connexion reseau autorisee est vers le credential proxy sur le host via
`host.docker.internal:{port}`.

---

# 8. Observabilite

## 8.1 Health Endpoint

Chaque instance expose un endpoint `/health` sur son port de credential proxy :

```bash
curl http://localhost:3001/health
```

Reponse :
```json
{
  "status": "ok",
  "assistant": "Botti",
  "channels": ["whatsapp", "gmail", "google-chat"],
  "groups": 3,
  "uptime": 86400
}
```

## 8.2 Prometheus Metrics

Chaque instance expose un endpoint `/metrics` au format Prometheus text exposition :

```bash
curl http://localhost:3001/metrics
```

### Counters

| Metrique                             | Description                         | Labels                |
|-------------------------------------|-------------------------------------|-----------------------|
| `nanoclaw_messages_received_total`  | Messages recus par canal            | `channel`             |
| `nanoclaw_messages_processed_total` | Messages traites par groupe         | `group`               |
| `nanoclaw_containers_spawned_total` | Containers agents lances            | --                    |
| `nanoclaw_container_errors_total`   | Erreurs de containers               | --                    |
| `nanoclaw_emails_filtered_total`    | Emails filtres par raison           | `reason`              |
| `nanoclaw_api_requests_total`       | Requetes API proxy par statut       | `status`              |

### Gauges

| Metrique                             | Description                         | Labels                |
|-------------------------------------|-------------------------------------|-----------------------|
| `nanoclaw_active_containers`        | Containers en cours d'execution     | --                    |
| `nanoclaw_registered_groups`        | Nombre de groupes enregistres       | --                    |
| `nanoclaw_uptime_seconds`           | Uptime du processus                 | --                    |
| `nanoclaw_circuit_breaker_state`    | Etat du circuit breaker (1=actif)   | `state`               |

### Histograms

| Metrique                                  | Description                   | Buckets                              |
|------------------------------------------|-------------------------------|--------------------------------------|
| `nanoclaw_container_duration_seconds`    | Duree d'execution container   | 1, 5, 10, 30, 60, 120, 300, 600, 1800 |
| `nanoclaw_api_request_duration_seconds`  | Latence requetes API proxy    | 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30   |
| `nanoclaw_gmail_poll_duration_seconds`   | Duree du poll Gmail           | 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2    |
| `nanoclaw_gchat_poll_duration_seconds`   | Duree du poll Google Chat     | 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2    |
| `nanoclaw_firestore_signal_check_seconds`| Duree check signal Firestore  | 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2    |

### Implementation

Les metriques sont implementees sans dependance externe dans `src/metrics.ts`. Le registre
est en memoire et formate les metriques en texte Prometheus a chaque requete `/metrics`.

## 8.3 Dashboard

Le dashboard est un serveur HTTP minimal (Node.js, CommonJS) sur le port 3100 qui :

- Decouvre automatiquement toutes les instances NanoClaw
- Appelle `/health` sur chaque instance
- Affiche l'etat en temps reel dans une page HTML
- Pas de framework frontend, HTML/CSS/JS inline

```bash
curl http://localhost:3100
```

Launchd service : `com.nanoclaw.dashboard`

## 8.4 Watchdog

Le watchdog est un script bash (`scripts/watchdog.sh`) execute toutes les 5 minutes
par launchd. Il :

1. Fait un health check sur chaque port (3001, 3002, 3003, 3004)
2. Compare avec le service launchd correspondant
3. Si un agent est down, envoie une alerte via WhatsApp (via l'instance Botti)
4. Cooldown de 30 minutes entre les alertes pour le meme agent
5. Detecte les retablissements et envoie un message "recovered"
6. Etat persiste dans `~/.config/nanoclaw/watchdog-state.json`

Launchd service : `com.nanoclaw.watchdog`

## 8.5 Structured Logging

Tous les logs sont structures en JSON via Pino :

```json
{
  "level": 30,
  "time": 1712232000000,
  "msg": "Processing messages",
  "group": "gmail_main",
  "messageCount": 3
}
```

**Configuration** :
- Niveau par defaut : `info` (configurable via `LOG_LEVEL`)
- En mode TTY (developpement) : `pino-pretty` avec couleurs
- En production : JSON brut sur stdout
- Redaction automatique : `sessionId`, `newSessionId`, `session_id`
- Erreurs non rattrapees : routees via Pino pour les timestamps

**Rotation** : Le script `scripts/rotate-logs.sh` tourne quotidiennement a 3h du matin :
- Retention : 7 jours pour les logs normaux
- Retention : 14 jours pour les logs de containers

Launchd service : `com.nanoclaw.logrotate`

---

# 9. Tests

## 9.1 Vue d'ensemble

| Type              | Fichiers | Tests  | Framework |
|------------------|----------|--------|-----------|
| Unit             | ~20      | ~380   | Vitest    |
| Integration      | ~5       | ~80    | Vitest    |
| E2E Docker       | 1        | ~40    | Vitest    |
| Stress           | ~2       | ~14    | Vitest    |
| **Total**        | **28**   | **514**| **Vitest** |

## 9.2 Tests unitaires

Les tests unitaires couvrent chaque module individuellement :

| Fichier                          | Ce qui est teste                            |
|---------------------------------|---------------------------------------------|
| `backoff.test.ts`               | Calcul du backoff exponentiel               |
| `credential-proxy.test.ts`      | Circuit breaker, daily spend, proxy logic   |
| `container-runner.test.ts`      | Build args, volume mounts, output parsing   |
| `container-runtime.test.ts`     | Detection runtime, orphan cleanup           |
| `db.test.ts`                    | Operations SQLite, schema, migrations       |
| `group-folder.test.ts`          | Validation des noms de dossiers groupes     |
| `group-queue.test.ts`           | Concurrence, retries, shutdown              |
| `formatting.test.ts`            | Formatage des messages, XML escaping        |
| `ipc-auth.test.ts`              | Auth IPC, rate limiting                     |
| `remote-control.test.ts`        | PIN auth, start/stop, URL parsing           |
| `routing.test.ts`               | Routage messages, formatage sortant         |
| `sender-allowlist.test.ts`      | Modes trigger/drop, hot-reload              |
| `task-scheduler.test.ts`        | Cron parsing, execution, retries            |
| `timezone.test.ts`              | Injection timezone                          |
| `channels/gmail.test.ts`        | Filtrage email, webhook, polling            |
| `channels/google-chat.test.ts`  | Polling Firestore, envoi Chat API           |
| `channels/registry.test.ts`     | Auto-enregistrement des canaux              |
| `channels/whatsapp.test.ts`     | Messages, reactions, media                  |

## 9.3 Tests E2E Docker

Le fichier `src/e2e/container-e2e.test.ts` teste l'isolation reelle du container :

- `.env` est shadow par `/dev/null`
- Le container tourne en non-root
- Les repertoires workspace existent
- Les repertoires IPC sont accessibles en ecriture
- `ANTHROPIC_BASE_URL` pointe vers le proxy
- `host.docker.internal` est resolvable
- Le container peut faire des requetes HTTP vers le host
- Les orphelins sont nettoyes correctement
- Node.js, npm, Claude CLI, Chromium, git sont disponibles
- La timezone est respectee

## 9.4 Tests d'integration

Les tests d'integration dans `src/integration/` testent l'interaction entre modules :

- Message loop + group queue + message processor
- Channel manager + database + routing
- IPC watcher + task scheduler

## 9.5 Comment lancer les tests

```bash
# Tous les tests
npm test

# Watch mode (re-execute sur modification)
npm run test:watch

# Tests specifiques
npx vitest run src/credential-proxy.test.ts

# Tests E2E (necessite Docker running)
npx vitest run src/e2e/

# Avec couverture
npx vitest run --coverage
```

## 9.6 Ce qui n'est PAS couvert

- Tests de charge realistes (100+ messages simultanes)
- Tests d'integration Cloud Run (Botti Voice, Chat Gateway)
- Tests d'acceptation utilisateur (manuels)
- Tests de performance de l'API Anthropic
- Tests Python (botti-voice, chat-gateway) -- pas dans la suite Vitest

---

# 10. Infrastructure

## 10.1 Mac Mini

| Composant         | Specification                                    |
|------------------|--------------------------------------------------|
| Machine          | Mac Mini (Apple Silicon)                         |
| OS               | macOS Darwin 25.3.0                              |
| Node.js          | >= 20 (via Homebrew)                             |
| Docker           | Docker Desktop for Mac                           |
| SQLite           | better-sqlite3 (natif, compile a l'install)      |
| Process manager  | launchd (natif macOS)                            |

## 10.2 Services launchd

Tous les plists sont dans `~/Library/LaunchAgents/` :

| Service                       | Role                              | Planification        |
|------------------------------|-----------------------------------|-----------------------|
| `com.nanoclaw`               | Botti (instance principale)       | KeepAlive, RunAtLoad |
| `com.nanoclaw.sam`           | Sam                               | KeepAlive, RunAtLoad |
| `com.nanoclaw.thais`         | Thais                             | KeepAlive, RunAtLoad |
| `com.nanoclaw.alan`          | Alan                              | KeepAlive, RunAtLoad |
| `com.nanoclaw.dashboard`     | Dashboard monitoring (port 3100)  | KeepAlive, RunAtLoad |
| `com.nanoclaw.watchdog`      | Health check alerting             | Toutes les 5 min     |
| `com.nanoclaw.backup`        | Backup GCS                        | 4h00 chaque jour     |
| `com.nanoclaw.logrotate`     | Rotation des logs                 | 3h00 chaque jour     |

### Commandes de gestion

```bash
# Lister les services NanoClaw
launchctl list | grep nanoclaw

# Redemarrer un agent
launchctl kickstart -k gui/$(id -u)/com.nanoclaw        # Botti
launchctl kickstart -k gui/$(id -u)/com.nanoclaw.sam     # Sam
launchctl kickstart -k gui/$(id -u)/com.nanoclaw.thais   # Thais
launchctl kickstart -k gui/$(id -u)/com.nanoclaw.alan    # Alan

# Arreter un agent
launchctl bootout gui/$(id -u)/com.nanoclaw.sam

# Demarrer un agent
launchctl load ~/Library/LaunchAgents/com.nanoclaw.sam.plist

# Voir les logs
tail -f ~/nanoclaw/logs/nanoclaw.log | jq .
tail -f ~/nanoclaw-sam/logs/nanoclaw.log | jq .
```

## 10.3 Services Cloud Run

| Service           | Framework | Langage | Role                              |
|------------------|-----------|---------|-----------------------------------|
| Botti Voice      | FastAPI   | Python  | Audio vocal (Gemini Live),        |
|                  |           |         | webhook Gmail, agent selector     |
| Chat Gateway     | FastAPI   | Python  | Webhook Google Chat,              |
|                  |           |         | Firestore writer, rate limiter    |

## 10.4 GCP Services

| Service           | Role                                             |
|------------------|--------------------------------------------------|
| Firestore        | Messages Google Chat, signaux Gmail, config      |
| Pub/Sub          | Notifications push Gmail (`gmail-push` topic)    |
| GCS              | Backups quotidiens (`gs://nanoclaw-backups-adp`) |
| Cloud Run        | Botti Voice, Chat Gateway                        |
| Gmail API        | Envoi/reception emails                           |
| Chat API         | Envoi de reponses dans Google Chat               |
| Calendar API     | Lecture/ecriture agenda                          |
| Drive API        | Lecture de fichiers                              |

## 10.5 Docker Desktop

- Image : `nanoclaw-agent:latest`
- Build : `./container/build.sh`
- Runtime : Docker Desktop for Mac
- Reseau container : `--network none`
- Cleanup : `--rm` (auto-supprime)
- Host gateway : `host.docker.internal`

## 10.6 Structure des repertoires

```
~/nanoclaw/                         <- Instance principale (Botti)
  .env                              <- Config + secrets
  package.json                      <- v2.0.0, dependances
  src/                              <- Code source TypeScript
  dist/                             <- Compile JavaScript
  container/                        <- Dockerfile, build.sh, skills
  groups/                           <- Dossiers de memoire par groupe
  data/                             <- Sessions, IPC, WhatsApp auth
  store/                            <- SQLite DB, daily spend
  logs/                             <- Logs (pino JSON)
  scripts/                          <- backup.sh, watchdog.sh, rotate-logs.sh
  dashboard/                        <- server.cjs (port 3100)
  chat-gateway/                     <- server.py (Cloud Run)
  botti-voice/                      <- web/ (Cloud Run)
  docs/                             <- ARCHITECTURE.md, etc.
  create-agent.sh                   <- Script creation d'agent
  deploy.sh                         <- Build + distribution dist/
  node_modules/                     <- Dependances (partagees via symlink)

~/nanoclaw-sam/                     <- Instance Sam
  .env
  dist/                             <- Copie (pas symlink)
  groups/gmail_main/                <- Memoire Sam
  data/
  store/
  logs/
  container -> ~/nanoclaw/container <- Symlink
  node_modules -> ~/nanoclaw/...    <- Symlink
  package.json -> ~/nanoclaw/...    <- Symlink
  src -> ~/nanoclaw/src             <- Symlink

~/nanoclaw-thais/                   <- Instance Thais (meme structure que Sam)
~/nanoclaw-alan/                    <- Instance Alan (meme structure que Sam)

~/.config/nanoclaw/                 <- Config de securite (hors projet)
  mount-allowlist.json
  sender-allowlist.json
  gmail-send-allowlist.json
  watchdog-state.json

~/.gmail-mcp-sam/                   <- Credentials Gmail Sam
  credentials.json
  gcp-oauth.keys.json
~/.gmail-mcp-thais/                 <- Credentials Gmail Thais
~/.gmail-mcp-alan/                  <- Credentials Gmail Alan
~/.firebase-mcp/
  adp-service-account.json          <- Service account Firestore/Chat
```

---

# 11. Operations

## 11.1 deploy.sh

Le script `deploy.sh` compile le TypeScript et distribue le `dist/` a toutes les instances :

```bash
./deploy.sh            # Build + copie dist/
./deploy.sh --restart  # Build + copie + restart tous les services
```

**Fonctionnement** :
1. `npm run build` -- compile TypeScript -> `dist/`
2. Pour chaque instance (sam, thais, alan) :
   - Supprime l'ancien `dist/` (symlink ou directory)
   - Copie le nouveau `dist/`
3. Si `--restart` : kickstart tous les services launchd

**Important** : `dist/` est une **copie**, pas un symlink. C'est un choix delibere pour
eviter que les instances secondaires chargent du code en cours de compilation.

## 11.2 create-agent.sh

Script automatise de creation d'un nouvel agent en **15 etapes** :

```bash
./create-agent.sh alan ala@bestoftours.co.uk --port 3004
./create-agent.sh marie marie@bestoftours.co.uk  # port auto-detecte
```

**Les 15 etapes** :

1. **Validate inputs** : Nom (lowercase alpha), email (contient @)
2. **Determine port** : Scan des plists existants, auto-detection du port libre (3001-3010)
3. **Read API key** : Copie la `ANTHROPIC_API_KEY` de l'instance principale
4. **Create directory structure** : `groups/gmail_main`, `data`, `logs`, `store`
5. **Create symlinks** : `container`, `node_modules`, `package.json`, `src`
6. **Copy dist/** : Copie reelle (pas symlink)
7. **Create .env** : Avec le port, le modele, les configs Google Chat/Gmail
8. **Set up Gmail OAuth** : Copie les keys OAuth, lance le flow OAuth dans le navigateur,
   echange le code pour un refresh token, sauve `credentials.json`
9. **Create launchd plist** : Genere le fichier `.plist` avec toutes les variables d'environnement
10. **Create CLAUDE.md** : Genere la memoire initiale de l'agent avec le template
11. **Register in DB** : Initialise SQLite avec le schema, insere le groupe `gmail:main`
12. **Update deploy.sh** : Ajoute l'instance au tableau `INSTANCES`
13. **Chat gateway reminder** : Rappel d'ajouter l'agent a `VALID_AGENTS` dans le gateway
14. **Load and start service** : `launchctl load` le plist
15. **Verify** : Verifie que le service tourne, affiche les logs

## 11.3 backup.sh

Backup quotidien a 4h du matin vers Google Cloud Storage :

```bash
# Execute automatiquement par launchd
# Peut aussi etre lance manuellement
./scripts/backup.sh
```

**Ce qui est sauvegarde** :
- Bases de donnees SQLite (via `.backup` pour la consistance)
- Fichiers `.env` de chaque instance
- Dossiers `groups/` (memoire des agents)
- Fichiers de configuration de securite (`~/.config/nanoclaw/`)
- Credentials Gmail (`~/.gmail-mcp-*/credentials.json`)

**Configuration** :
- Bucket : `gs://nanoclaw-backups-adp`
- Retention : 30 jours
- Logs : `~/nanoclaw/logs/backup.log`

Launchd service : `com.nanoclaw.backup`

## 11.4 Rotation des logs

Le script `scripts/rotate-logs.sh` tourne quotidiennement a 3h du matin :

- Logs normaux : retention 7 jours
- Logs containers : retention 14 jours
- Suppression des fichiers rotatifs anciens

Launchd service : `com.nanoclaw.logrotate`

## 11.5 Watchdog

Le watchdog (`scripts/watchdog.sh`) tourne toutes les 5 minutes :

1. Health check HTTP sur les ports 3001, 3002, 3003, 3004
2. Si un agent est down :
   - Envoie une alerte WhatsApp via Botti
   - Cooldown de 30 minutes entre alertes pour le meme agent
3. Si un agent revient :
   - Envoie un message "recovered" via WhatsApp
4. Etat persiste dans `~/.config/nanoclaw/watchdog-state.json`

Launchd service : `com.nanoclaw.watchdog`

## 11.6 Message Loop (boucle de polling)

Le Message Loop (`message-loop.ts`) est le coeur du systeme de detection des messages.

### Algorithme

```
Toutes les 2 secondes (POLL_INTERVAL) :
  1. Interroger SQLite pour les messages plus recents que lastTimestamp
  2. Pour chaque groupe avec de nouveaux messages :
     a. Verifier si c'est un main group (pas de trigger requis)
     b. Sinon, verifier si un trigger @NomAgent est present
     c. Verifier que l'expediteur est autorise (sender allowlist)
     d. Si un container actif existe pour ce groupe :
        -> Piper le message via IPC (queue.sendMessage)
     e. Sinon :
        -> Mettre en queue (queue.enqueueMessageCheck)
  3. Avancer le curseur lastTimestamp
  4. Sauvegarder l'etat dans SQLite
```

### Gestion des curseurs

Deux curseurs independants :

- **lastTimestamp** : Dernier timestamp lu depuis la DB (par le message loop)
- **lastAgentTimestamp[chatJid]** : Dernier timestamp traite par l'agent pour ce groupe

La separation permet de detecter les messages meme si l'agent n'a pas encore termine
de traiter le lot precedent.

### Startup Recovery

Au demarrage, `recoverPendingMessages()` verifie s'il y a des messages non traites :

```
Pour chaque groupe enregistre :
  1. Lire les messages depuis lastAgentTimestamp[chatJid]
  2. Si il y en a -> enqueue le groupe pour traitement
```

Cela gere le cas ou NanoClaw a crashe entre l'avancement du curseur et le traitement
effectif des messages.

### Deduplication

Les messages sont dedupliques par groupe : meme si 5 messages arrivent pour le meme
groupe pendant un cycle de polling, un seul `enqueueMessageCheck` est emis.

## 11.7 Commandes de diagnostic

```bash
# Etat de tous les services
launchctl list | grep nanoclaw

# Health check d'un agent
curl -s http://localhost:3001/health | jq .

# Metriques Prometheus
curl -s http://localhost:3001/metrics

# Containers Docker actifs
docker ps --filter "name=nanoclaw"

# Logs en direct (formate)
tail -f ~/nanoclaw/logs/nanoclaw.log | jq .

# Derniers logs d'erreur
tail -20 ~/nanoclaw/logs/nanoclaw.error.log

# Verifier la DB
sqlite3 ~/nanoclaw/store/messages.db ".tables"
sqlite3 ~/nanoclaw/store/messages.db "SELECT count(*) FROM messages;"

# Verifier le spend quotidien
cat ~/nanoclaw/store/daily-spend.json | jq .

# Rebuild container
./container/build.sh

# Build + deploy
./deploy.sh --restart
```

## 11.7 Procedure de redemarrage

### Redemarrer un agent

```bash
launchctl kickstart -k gui/$(id -u)/com.nanoclaw.sam
```

### Redemarrer tous les agents

```bash
./deploy.sh --restart
```

### Redemarrer apres une mise a jour du code

```bash
# 1. Compiler
npm run build

# 2. Distribuer et redemarrer
./deploy.sh --restart

# 3. Verifier
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health
curl http://localhost:3004/health
```

### Redemarrer apres un crash

```bash
# 1. Verifier l'etat
launchctl list | grep nanoclaw

# 2. Verifier les logs
tail -50 ~/nanoclaw/logs/nanoclaw.error.log

# 3. Nettoyer les containers orphelins
docker rm -f $(docker ps -q --filter "name=nanoclaw")

# 4. Redemarrer
launchctl kickstart -k gui/$(id -u)/com.nanoclaw
```

---

# 12. Stack technique

| Technologie                  | Version    | Usage                               |
|------------------------------|-----------|--------------------------------------|
| **Node.js**                  | >= 20     | Runtime principal                    |
| **TypeScript**               | 5.7       | Langage principal                    |
| **Python**                   | 3.x       | Botti Voice, Chat Gateway            |
| **FastAPI**                  | -         | Chat Gateway, Botti Voice API        |
| **Claude Agent SDK**         | via CLI   | Intelligence agent (dans containers) |
| **Claude Code CLI**          | latest    | Claude Code dans les containers      |
| **Gemini Live API**          | v1beta    | Audio vocal (Botti Voice)            |
| **Gemini 2.5 Flash**        | native-audio | Modele audio                      |
| **Claude Opus 4.6**         | -         | Modele agent par defaut              |
| **SQLite** (better-sqlite3)  | 11.8      | Base de donnees locale               |
| **Firestore**                | 8.3       | Communication Cloud Run <-> NanoClaw |
| **Docker**                   | Desktop   | Isolation containers agent           |
| **Baileys**                  | 7.0.0-rc9 | Client WhatsApp Web                 |
| **googleapis**               | 144.0     | Gmail, Calendar, Drive, Chat API     |
| **Pino**                     | 9.6       | Logging structure JSON               |
| **Zod**                      | 4.3       | Validation des variables d'env       |
| **cron-parser**              | 5.5       | Parsing expressions cron             |
| **Vitest**                   | 4.0       | Framework de tests                   |
| **Prettier**                 | 3.8       | Formatage du code                    |
| **Husky**                    | 9.1       | Pre-commit hooks                     |
| **tsx**                      | 4.19      | Execution TypeScript directe (dev)   |
| **launchd**                  | (macOS)   | Gestionnaire de processus            |
| **Google Cloud SDK**         | (gcloud)  | Backups GCS, deploys Cloud Run       |
| **Chromium**                 | (headless)| Navigation web dans les containers   |

---

# 13. Decisions architecturales

## 13.1 Pourquoi Node.js

- Event-driven, parfait pour du polling et des WebSockets
- Baileys (WhatsApp) est une lib Node.js
- googleapis est une lib Node.js mature
- Un seul langage pour le core (TypeScript)
- Performance suffisante pour 4 agents

## 13.2 Pourquoi Docker (et pas Apple Container)

- Portabilite : meme image sur Mac et Linux
- Docker Desktop est stable sur macOS
- `--network none` pour l'isolation reseau
- `host.docker.internal` pour la communication avec le host
- Apple Container est supporte (skill `/convert-to-apple-container`) mais Docker est le defaut

## 13.3 Pourquoi polling + webhook

Le polling est le mode de base car il est simple et fiable. Les webhooks sont un
**complement** pour reduire la latence :

- Gmail : webhook via Pub/Sub reduit la latence de detection de ~60s a ~5s
- Google Chat : webhook obligatoire (Chat App), Firestore comme bus de messages
- WhatsApp : temps reel via WebSocket natif (pas de polling)

Le fallback polling est toujours present pour gerer les cas ou le webhook echoue.

## 13.4 Pourquoi Firestore

- Seul datastore accessible a la fois depuis Cloud Run et le Mac Mini local
- Gratuit pour le volume de donnees concerne (<1 GB)
- Temps reel (pourrait utiliser onSnapshot, mais on poll pour simplifier)
- Pas de VPN ou tunnel necessaire

## 13.5 Pourquoi un seul Chat App

Google Workspace ne permet qu'un nombre limite de Chat Apps par organisation.
Plutot que de creer un Chat App par agent, on a un seul Chat App ("Botti") qui
route les messages vers le bon agent via le mapping Firestore.

## 13.6 Pourquoi Gemini pour la voix

- Gemini Live supporte l'audio natif bidirectionnel
- Claude ne supporte pas encore l'audio en streaming
- Gemini 2.5 Flash est rapide et peu couteux pour le vocal
- La memoire NanoClaw est chargee dans le prompt Gemini

## 13.7 Pourquoi Claude pour les agents

- Claude Agent SDK / Claude Code donne un agent complet avec outils
- Meilleur raisonnement et suivi d'instructions que les alternatives
- Modele Opus 4.6 pour la qualite maximale
- Support natif des sessions persistantes

## 13.8 Pourquoi Mac Mini

- Zero cout recurrent (machine deja achetee)
- WhatsApp via Baileys est plus stable en local (pas de risque IP data center)
- Apple Silicon performant pour les charges locales
- Controle total (disque, reseau, configurations)

## 13.9 Pourquoi split index.ts

Le fichier `index.ts` original faisait >500 lignes et melangeait trop de responsabilites.
Le split en 4 modules ameliore :

- **Lisibilite** : Chaque fichier a une seule responsabilite
- **Testabilite** : Les modules peuvent etre testes individuellement
- **Maintenabilite** : Modifications localisees sans risque de casser d'autres parties

| Module                 | Responsabilite                               |
|-----------------------|----------------------------------------------|
| `index.ts`            | Orchestrateur, wiring, startup, shutdown     |
| `state.ts`            | Gestion de l'etat (timestamps, sessions)     |
| `message-processor.ts`| Traitement des messages, spawn containers    |
| `channel-manager.ts`  | Init canaux, callbacks, remote control       |

## 13.10 Pourquoi constants.ts

Les magic numbers etaient disperses dans le code. `constants.ts` centralise toutes les
constantes numeriques par domaine :

- Anti-spam : `ERROR_COOLDOWN_MS`, `STALE_ENTRY_MS`
- Group queue : `GROUP_QUEUE_MAX_RETRIES`, `GROUP_QUEUE_BASE_RETRY_MS`
- Circuit breaker : `CIRCUIT_BREAKER_THRESHOLD`, `CIRCUIT_BREAKER_RESET_MS`
- Gmail : `FIRESTORE_SIGNAL_POLL_MS`, `GMAIL_WEBHOOK_FALLBACK_POLL_MS`
- Google Chat : `GOOGLE_CHAT_POLL_MS`
- IPC : `MAX_TASKS_PER_GROUP`

Avantage : un seul endroit pour voir et modifier toutes les constantes.

## 13.11 Pourquoi le circuit breaker

Sans circuit breaker, si l'API Anthropic tombe :
1. Chaque container fait des requetes qui echouent
2. Les timeouts s'accumulent
3. Les containers s'empilent
4. La machine est saturee

Avec le circuit breaker :
1. Apres 5 echecs consecutifs, le proxy coupe (503 immediat)
2. 60 secondes de pause
3. Un probe unique teste si le service est revenu
4. Si oui, on reprend. Si non, on re-coupe

## 13.12 Pourquoi dist/ separe par instance

Initialement, `dist/` etait un symlink partage entre les instances. Probleme :
si on compile (`npm run build`) pendant que les instances tournent, elles peuvent
charger du code a moitie compile.

Solution : `dist/` est une **copie** pour chaque instance. Le script `deploy.sh`
gere la distribution apres compilation.

## 13.13 Pourquoi le backoff exponentiel

La fonction `calculateBackoff` est extraite dans `backoff.ts` pour etre reutilisee :

```typescript
function calculateBackoff(consecutiveErrors: number, baseMs: number, maxMs: number): number {
  return consecutiveErrors > 0
    ? Math.min(baseMs * Math.pow(2, consecutiveErrors), maxMs)
    : baseMs;
}
```

Utilise par :
- Gmail channel (polling errors)
- Google Chat channel (polling errors)
- Group queue (retries)

---

# 14. Scores de qualite

Evaluation de la qualite du systeme selon 11 categories :

| #  | Categorie                    | Score   | Justification                                                    |
|----|------------------------------|---------|------------------------------------------------------------------|
| 1  | Securite                     | 88/100  | Credential proxy, mount isolation, sender allowlist, Gmail       |
|    |                              |         | draft safety, PIN auth. -12 : pas de chiffrement at rest SQLite, |
|    |                              |         | pas de WAF sur Cloud Run.                                        |
| 2  | Observabilite                | 95/100  | Health endpoints, Prometheus metrics, dashboard, watchdog,       |
|    |                              |         | structured logging. -5 : pas encore Grafana dashboards.          |
| 3  | Tests                        | 92/100  | 514 tests, E2E Docker, circuit breaker. -8 : pas de tests       |
|    |                              |         | Python, pas de tests de charge realistes.                        |
| 4  | Architecture                 | 90/100  | Split propre, constants centralisees, interfaces Channel.        |
|    |                              |         | -10 : quelques `any` restants, couplage state global.           |
| 5  | Operations                   | 93/100  | create-agent.sh, deploy.sh, backup GCS, log rotation,           |
|    |                              |         | watchdog. -7 : pas de rollback automatique, pas de canary.      |
| 6  | Documentation                | 90/100  | ARCHITECTURE.md, TROUBLESHOOTING.md, TECHNICAL-OVERVIEW.md,     |
|    |                              |         | CHANGELOG.md. -10 : pas de doc API (endpoints proxy/gateway).   |
| 7  | Maintenabilite               | 88/100  | Code lisible, <14k lignes, TypeScript strict. -12 : dependance  |
|    |                              |         | sur un seul mainteneur, pas de CI/CD automatise.                 |
| 8  | Fiabilite                    | 85/100  | Graceful shutdown, recovery au demarrage, circuit breaker.       |
|    |                              |         | -15 : pas de HA, single point of failure (Mac Mini).             |
| 9  | Performance                  | 87/100  | Polling leger, GroupQueue concurrence, cache TTL.                |
|    |                              |         | -13 : pas de metriques de latence end-to-end.                    |
| 10 | Scalabilite                  | 70/100  | 4 agents OK, 10+ agents necessiterait du refactoring.            |
|    |                              |         | -30 : pas de distribution multi-machine, polling lineaire.       |
| 11 | Conformite                   | 95/100  | Licence proprietaire, copyright headers, redaction des secrets.  |
|    |                              |         | -5 : pas d'audit RGPD formel sur les donnees stockees.          |
|    |                              |         |                                                                  |
|    | **Moyenne**                  | **88/100** |                                                               |

---

# 15. Configuration

## 15.1 Variables d'environnement

Toutes les variables reconnues, validees par Zod au demarrage :

### Requises

| Variable              | Type   | Description                                      |
|----------------------|--------|--------------------------------------------------|
| `ANTHROPIC_API_KEY`  | string | Cle API Anthropic (REQUISE)                      |

### Identite

| Variable                   | Type   | Defaut     | Description                     |
|---------------------------|--------|------------|---------------------------------|
| `ASSISTANT_NAME`          | string | `Andy`     | Nom de l'agent (pour triggers)  |
| `ASSISTANT_HAS_OWN_NUMBER`| bool  | `false`    | Agent a son propre numero WA    |

### Modele IA

| Variable        | Type   | Defaut               | Description                     |
|----------------|--------|----------------------|---------------------------------|
| `CLAUDE_MODEL` | string | `claude-sonnet-4-6`  | Modele Claude pour les agents   |

### Controle des couts

| Variable              | Type   | Defaut | Description                          |
|----------------------|--------|--------|--------------------------------------|
| `DAILY_API_LIMIT_USD`| number | `20`   | Limite de depense quotidienne (USD)  |

### Container

| Variable                     | Type   | Defaut               | Description                     |
|-----------------------------|--------|----------------------|---------------------------------|
| `CONTAINER_PREFIX`          | string | `nanoclaw`           | Prefixe des noms de containers  |
| `CONTAINER_IMAGE`           | string | `nanoclaw-agent:latest` | Image Docker                 |
| `CONTAINER_TIMEOUT`         | number | `1800000`            | Timeout hard (30min) en ms      |
| `CONTAINER_MAX_OUTPUT_SIZE` | number | `10485760`           | Taille max output (10MB)        |
| `IDLE_TIMEOUT`              | number | `1800000`            | Timeout idle (30min) en ms      |
| `MAX_CONCURRENT_CONTAINERS` | number | `5`                  | Max containers en parallele     |

### Reseau

| Variable                 | Type   | Defaut    | Description                          |
|-------------------------|--------|-----------|--------------------------------------|
| `CREDENTIAL_PROXY_PORT` | number | `3001`    | Port du credential proxy             |
| `CREDENTIAL_PROXY_HOST` | string | auto      | Adresse de bind du proxy             |

### Polling

| Variable                  | Type   | Defaut  | Description                           |
|--------------------------|--------|---------|---------------------------------------|
| `POLL_INTERVAL`          | number | `2000`  | Intervalle poll messages (ms)         |
| `SCHEDULER_POLL_INTERVAL`| number | `60000` | Intervalle poll taches planifiees     |
| `IPC_POLL_INTERVAL`      | number | `1000`  | Intervalle poll IPC (ms)              |

### Google Chat

| Variable                          | Type   | Defaut     | Description                     |
|----------------------------------|--------|------------|---------------------------------|
| `GOOGLE_CHAT_ENABLED`           | bool   | `false`    | Active le canal Google Chat     |
| `GOOGLE_CHAT_AGENT_NAME`        | string | `nanoclaw` | Nom agent dans Firestore        |
| `GOOGLE_APPLICATION_CREDENTIALS`| string | -          | Chemin service account JSON     |
| `GOOGLE_CHAT_BOT_SA`            | string | -          | Service account Chat Bot        |

### Gmail

| Variable                      | Type   | Defaut  | Description                          |
|------------------------------|--------|---------|--------------------------------------|
| `GMAIL_WEBHOOK_ENABLED`     | bool   | `false` | Active le webhook Gmail Firestore    |
| `GMAIL_MCP_DIR`             | string | -       | Chemin credentials Gmail             |
| `GMAIL_DIRECT_SEND_ALLOWLIST`| string | -      | Emails envoi direct (comma-sep)      |
| `GMAIL_NOTIFY_EMAIL`        | string | -       | Email de notification brouillons     |
| `GMAIL_CC_EMAIL`            | string | -       | CC automatique emails sortants       |

### Remote Control

| Variable              | Type   | Defaut | Description                          |
|----------------------|--------|--------|--------------------------------------|
| `REMOTE_CONTROL_PIN` | string | -      | PIN auth (min 4 chars, disabled si vide) |

### Voice

| Variable       | Type   | Defaut        | Description                           |
|---------------|--------|---------------|---------------------------------------|
| `WHISPER_BIN` | string | `whisper-cli` | Chemin vers le binaire whisper        |
| `WHISPER_MODEL`| string | -            | Chemin vers le modele whisper         |

### Logging

| Variable    | Type   | Defaut | Description                                   |
|------------|--------|--------|-----------------------------------------------|
| `LOG_LEVEL`| enum   | `info` | trace, debug, info, warn, error, fatal        |

### Timezone

| Variable | Type   | Defaut   | Description                                   |
|---------|--------|----------|-----------------------------------------------|
| `TZ`    | string | systeme  | Timezone pour les taches planifiees            |

### Validation Zod au demarrage

Au demarrage, `validateEnv()` valide toutes les variables d'environnement via un schema Zod :

- **ANTHROPIC_API_KEY absente** : Erreur fatale, arret du processus
- **Variable optionnelle invalide** : Warning dans les logs, le systeme continue avec le defaut
- **Variable inconnue** : Ignoree (pas de rejet)

Le schema coerce automatiquement les types (`z.coerce.number()` pour les entiers passes
en string depuis `.env`).

### Sequence de demarrage

L'ordre de demarrage dans `main()` est critique :

```
1. validateEnv()              -- Verifier les variables d'environnement
2. ensureContainerRunning()   -- Verifier Docker + nettoyer les orphelins
3. initDatabase()             -- Ouvrir/creer SQLite
4. loadState()                -- Charger curseurs et sessions depuis SQLite
5. startCredentialProxy()     -- Demarrer le proxy HTTP (port 3001-3004)
6. setHealthDeps()            -- Connecter le /health au contexte
7. initChannels()             -- Initialiser WhatsApp, Gmail, Google Chat
8. startSchedulerLoop()       -- Demarrer le polling des taches planifiees
9. startIpcWatcher()          -- Demarrer le watcher IPC
10. recoverPendingMessages()  -- Verifier les messages non traites
11. startMessageLoop()        -- Demarrer la boucle de polling principale
```

Le shutdown graceful est dans l'ordre inverse :
1. Fermer le proxy HTTP
2. Attendre la GroupQueue (10s max)
3. Deconnecter tous les canaux
4. exit(0)

## 15.2 Ports

| Port | Service                          | Instance          |
|------|----------------------------------|-------------------|
| 3001 | Credential proxy + health/metrics| Botti             |
| 3002 | Credential proxy + health/metrics| Thais             |
| 3003 | Credential proxy + health/metrics| Sam               |
| 3004 | Credential proxy + health/metrics| Alan              |
| 3100 | Dashboard monitoring             | Global            |

## 15.3 Fichiers de configuration de securite

Tous dans `~/.config/nanoclaw/` (hors du projet, jamais montes dans les containers) :

| Fichier                     | Format | Role                                     |
|----------------------------|--------|------------------------------------------|
| `mount-allowlist.json`     | JSON   | Chemins autorises pour les mounts extra  |
| `sender-allowlist.json`    | JSON   | Qui peut trigger les agents              |
| `gmail-send-allowlist.json`| JSON   | Qui les agents peuvent emailer           |
| `watchdog-state.json`      | JSON   | Etat du watchdog (dernieres alertes)     |

## 15.4 Collections Firestore

| Collection            | Document / Sous-collection              | Usage                |
|----------------------|------------------------------------------|----------------------|
| `nanoclaw-messages`  | `{agent}/google-chat` (sous-coll docs)  | Messages Chat        |
| `nanoclaw-signals`   | `{instance}/gmail-webhook` (doc)         | Signaux Gmail        |
| `chat-config`        | `space-mapping` (doc)                    | Mapping space->agent |

---

# 16. Roadmap

## 16.1 Ce qui est fait (v2.0.0)

- [x] Multi-agent (4 instances)
- [x] Google Chat integration (Chat App + Gateway + Firestore)
- [x] Gmail webhook (Pub/Sub + Botti Voice + Firestore)
- [x] Email filtering (newsletters, marketing, noreply)
- [x] Botti Voice (Gemini Live, agent selector, memoire unifiee)
- [x] Dashboard monitoring (port 3100)
- [x] create-agent.sh (creation automatisee)
- [x] deploy.sh (build + distribution)
- [x] Health endpoints (/health, /metrics)
- [x] Prometheus metrics (counters, gauges, histograms)
- [x] Circuit breaker sur le proxy
- [x] IPC rate limiting
- [x] Zod environment validation
- [x] Rotation des logs
- [x] Backup GCS quotidien
- [x] Watchdog alerting WhatsApp
- [x] Gmail send safety (brouillon + notification)
- [x] Split index.ts en modules
- [x] constants.ts centralise
- [x] dist/ isole par instance
- [x] 514 tests
- [x] Documentation technique complete
- [x] Licence proprietaire Botler 360

## 16.2 Prochaines etapes (v2.1+)

- [ ] **Grafana dashboards** : Visualisation des metriques Prometheus
- [ ] **Gemini 3.1** : Mise a jour du modele audio quand disponible
- [ ] **Plus d'agents** : Facilite par create-agent.sh
- [ ] **Tests Python** : Suite de tests pour Botti Voice et Chat Gateway
- [ ] **CI/CD** : Pipeline GitHub Actions pour build, test, deploy
- [ ] **WAF Cloud Run** : Protection supplementaire des endpoints publics
- [ ] **Chiffrement SQLite** : sqlcipher pour les donnees at rest
- [ ] **Audit RGPD** : Revue formelle des donnees personnelles stockees
- [ ] **Multi-machine** : Distribution des agents sur plusieurs machines
- [ ] **Grafana alerting** : Remplacement du watchdog bash par Grafana alerts
- [ ] **Google Chat webhook direct** : Eliminer le polling si possible
- [ ] **Tests de charge** : Simulation de 100+ messages simultanes

---

# 17. Comment creer un nouvel agent

## 17.1 Prerequis

- Le Mac Mini est operationnel avec au moins un agent (Botti)
- Docker Desktop est lance
- L'API key Anthropic est dans le `.env` de l'instance principale
- Les credentials Firebase sont en place (`~/.firebase-mcp/adp-service-account.json`)
- Un compte Google Workspace existe pour l'agent (email @bestoftours.co.uk)

## 17.2 Procedure

### Etape 1 : Lancer le script

```bash
cd ~/nanoclaw
./create-agent.sh <nom> <email> [--port PORT] [--model MODEL]
```

Exemples :
```bash
./create-agent.sh marie marie@bestoftours.co.uk
./create-agent.sh ahmed ahmed@bestoftours.co.uk --port 3005 --model claude-sonnet-4-6
```

### Etape 2 : Authentification Gmail

Le script ouvre un navigateur pour l'authentification OAuth2. Se connecter avec le
compte Google de l'agent. Les scopes demandes sont :
- `https://mail.google.com/` (Gmail complet)
- `https://www.googleapis.com/auth/calendar` (Calendrier)
- `https://www.googleapis.com/auth/drive.readonly` (Drive lecture)

### Etape 3 : Configurer le Chat Gateway

Apres la creation, le script rappelle d'ajouter l'agent au Chat Gateway :
1. Aller dans le code du Chat Gateway (`chat-gateway/server.py`)
2. Ajouter le nom au set `VALID_AGENTS`
3. Redeployer sur Cloud Run
4. Ajouter le mapping space->agent dans Firestore (`chat-config/space-mapping`)

### Etape 4 : Verifier

```bash
# Verifier le service
launchctl list | grep nanoclaw.<nom>

# Health check
curl http://localhost:<port>/health

# Logs
tail -f ~/nanoclaw-<nom>/logs/nanoclaw.log | jq .
```

### Etape 5 : Personnaliser

Editer le fichier `~/nanoclaw-<nom>/groups/gmail_main/CLAUDE.md` pour personnaliser
le comportement de l'agent (role, regles, connaissances).

## 17.3 En cas de probleme

Voir `docs/TROUBLESHOOTING.md` pour les problemes courants :
- Token OAuth expire (#4)
- Port deja utilise (#11)
- Agent ne recoit pas les emails (#5)
- Google Chat ne repond pas (#7)

---

# 18. Annexes

## 18.1 Arborescence des fichiers source

```
src/
  index.ts                  -- Orchestrateur principal (startup, wiring, shutdown)
  state.ts                  -- Gestion etat (timestamps, sessions, groupes)
  message-processor.ts      -- Traitement messages, spawn containers, anti-spam
  channel-manager.ts        -- Init canaux, callbacks, remote control
  config.ts                 -- Configuration depuis .env (non-secrets)
  constants.ts              -- Constantes centralisees par domaine
  types.ts                  -- Interfaces TypeScript (Channel, Message, Task, etc.)
  db.ts                     -- Operations SQLite (better-sqlite3)
  env.ts                    -- Lecture fichier .env
  env-validation.ts         -- Validation Zod au demarrage
  logger.ts                 -- Pino structured logging + redaction
  metrics.ts                -- Registre Prometheus (counters, gauges, histograms)
  router.ts                 -- Formatage messages + routage sortant
  credential-proxy.ts       -- Proxy HTTP, circuit breaker, daily spend
  container-runner.ts       -- Spawn containers, mounts, output parsing
  container-runtime.ts      -- Detection runtime (Docker/Apple), orphan cleanup
  mount-security.ts         -- Validation des mounts additionnels
  group-folder.ts           -- Validation noms de dossiers groupes
  group-queue.ts            -- File d'attente concurrence containers
  message-loop.ts           -- Boucle de polling messages
  task-scheduler.ts         -- Execution taches planifiees (cron/interval/once)
  ipc.ts                    -- Watcher IPC file-based
  anti-spam.ts              -- Detection rate limit, cooldown notifications
  backoff.ts                -- Calcul backoff exponentiel (partage)
  sender-allowlist.ts       -- Allowlist expediteurs par chat
  remote-control.ts         -- Remote Control Claude Code via WhatsApp
  media-download.ts         -- Telechargement medias WhatsApp
  transcription.ts          -- Transcription vocale (Whisper)
  timezone.ts               -- Injection timezone
  whatsapp-auth.ts          -- Authentification WhatsApp standalone
  channels/
    index.ts                -- Barrel import (auto-enregistrement)
    registry.ts             -- Registre de canaux (pattern factory)
    whatsapp.ts             -- Canal WhatsApp (Baileys)
    gmail.ts                -- Canal Gmail (OAuth2 + Firestore)
    google-chat.ts          -- Canal Google Chat (Firestore + Chat API)
  e2e/
    container-e2e.test.ts   -- Tests E2E Docker (isolation, env, tools)
  integration/
    *.test.ts               -- Tests d'integration
  *.test.ts                 -- Tests unitaires (meme niveau que les modules)
```

## 18.2 Schema de base de donnees

```sql
-- ===================================================
-- NanoClaw SQLite Schema (store/messages.db)
-- ===================================================

-- Metadonnees des conversations
CREATE TABLE chats (
  jid TEXT PRIMARY KEY,               -- Identifiant unique du chat
  name TEXT,                           -- Nom affiche
  last_message_time TEXT,              -- Dernier message (ISO 8601)
  channel TEXT,                        -- Canal ('whatsapp', 'gmail', 'google-chat')
  is_group INTEGER DEFAULT 0           -- 1 = groupe, 0 = conversation privee
);

-- Messages recus et envoyes
CREATE TABLE messages (
  id TEXT,                             -- ID unique du message
  chat_jid TEXT,                       -- Reference au chat
  sender TEXT,                         -- ID de l'expediteur
  sender_name TEXT,                    -- Nom affiche de l'expediteur
  content TEXT,                        -- Contenu du message
  timestamp TEXT,                      -- Horodatage (ISO 8601)
  is_from_me INTEGER,                  -- 1 = envoye par l'agent
  is_bot_message INTEGER DEFAULT 0,    -- 1 = message du bot
  PRIMARY KEY (id, chat_jid),
  FOREIGN KEY (chat_jid) REFERENCES chats(jid)
);
CREATE INDEX idx_timestamp ON messages(timestamp);

-- Taches planifiees
CREATE TABLE scheduled_tasks (
  id TEXT PRIMARY KEY,                 -- UUID
  group_folder TEXT NOT NULL,          -- Dossier du groupe
  chat_jid TEXT NOT NULL,              -- Chat cible pour la reponse
  prompt TEXT NOT NULL,                -- Prompt a executer
  schedule_type TEXT NOT NULL,         -- 'cron', 'interval', 'once'
  schedule_value TEXT NOT NULL,        -- Expression cron, interval ms, ISO date
  next_run TEXT,                       -- Prochaine execution (ISO 8601)
  last_run TEXT,                       -- Derniere execution
  last_result TEXT,                    -- Dernier resultat
  status TEXT DEFAULT 'active',        -- 'active', 'paused', 'completed'
  created_at TEXT NOT NULL,            -- Date de creation
  context_mode TEXT DEFAULT 'isolated' -- 'group' = contexte du groupe, 'isolated' = fresh
);
CREATE INDEX idx_next_run ON scheduled_tasks(next_run);
CREATE INDEX idx_status ON scheduled_tasks(status);

-- Historique d'execution des taches
CREATE TABLE task_run_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,               -- Reference a scheduled_tasks
  run_at TEXT NOT NULL,                -- Horodatage de l'execution
  duration_ms INTEGER NOT NULL,        -- Duree en ms
  status TEXT NOT NULL,                -- 'success', 'error'
  result TEXT,                         -- Resultat (tronque)
  error TEXT,                          -- Message d'erreur
  FOREIGN KEY (task_id) REFERENCES scheduled_tasks(id)
);
CREATE INDEX idx_task_run_logs ON task_run_logs(task_id, run_at);

-- Etat du routeur (curseurs de lecture, timestamps)
CREATE TABLE router_state (
  key TEXT PRIMARY KEY,                -- Cle (ex: 'last_timestamp')
  value TEXT NOT NULL                  -- Valeur serialisee
);

-- Sessions Claude par groupe
CREATE TABLE sessions (
  group_folder TEXT PRIMARY KEY,       -- Dossier du groupe
  session_id TEXT NOT NULL             -- ID de session Claude
);

-- Groupes enregistres
CREATE TABLE registered_groups (
  jid TEXT PRIMARY KEY,                -- JID du chat
  name TEXT NOT NULL,                  -- Nom affiche
  folder TEXT NOT NULL UNIQUE,         -- Dossier sur le disque
  trigger_pattern TEXT NOT NULL,       -- Pattern de declenchement (@NomAgent)
  added_at TEXT NOT NULL,              -- Date d'ajout
  container_config TEXT,               -- Config container JSON (mounts, timeout)
  requires_trigger INTEGER DEFAULT 1,  -- 1 = trigger requis, 0 = auto
  is_main INTEGER DEFAULT 0            -- 1 = groupe principal
);
```

## 18.3 Diagramme de sequence : message WhatsApp

```
Utilisateur      WhatsApp     Baileys      ChannelMgr    SQLite     MsgLoop    GroupQueue   MsgProcessor  ContainerRunner   Docker      CredProxy    Anthropic
    |               |            |             |            |          |            |              |              |            |             |            |
    |--message----->|            |             |            |          |            |              |              |            |             |            |
    |               |--WS push-->|             |            |          |            |              |              |            |             |            |
    |               |            |--onMessage->|            |          |            |              |              |            |             |            |
    |               |            |             |--store---->|          |            |              |              |            |             |            |
    |               |            |             |            |          |            |              |              |            |             |            |
    |               |            |             |            |<--poll---|            |              |              |            |             |            |
    |               |            |             |            |--msgs--->|            |              |              |            |             |            |
    |               |            |             |            |          |--enqueue-->|              |              |            |             |            |
    |               |            |             |            |          |            |--process---->|              |              |            |             |            |
    |               |            |             |            |          |            |              |--spawn------>|              |            |             |            |
    |               |            |             |            |          |            |              |              |--docker run->|             |            |
    |               |            |             |            |          |            |              |              |            |--API call-->|             |
    |               |            |             |            |          |            |              |              |            |             |--inject key->|
    |               |            |             |            |          |            |              |              |            |             |<--response--|
    |               |            |             |            |          |            |              |              |            |<--response--|             |
    |               |            |             |            |          |            |              |              |<--stdout----|             |            |
    |               |            |             |            |          |            |              |<--output------|              |            |             |            |
    |               |            |             |<---send----|----------|------------|--------------|              |            |             |            |
    |               |<--WS send--|             |            |          |            |              |              |            |             |            |
    |<--message-----|            |             |            |          |            |              |              |            |             |            |
```

## 18.4 Diagramme de sequence : message Gmail avec webhook

```
Expediteur    Gmail API    Pub/Sub     BottiVoice   Firestore    NanoClaw    Gmail API    Container    CredProxy
    |            |            |            |            |            |            |            |            |
    |--email---->|            |            |            |            |            |            |            |
    |            |--push----->|            |            |            |            |            |            |
    |            |            |--webhook-->|            |            |            |            |            |
    |            |            |            |--signal--->|            |            |            |            |
    |            |            |            |            |<--poll(5s)-|            |            |            |
    |            |            |            |            |--signal--->|            |            |            |
    |            |            |            |            |            |--get msg-->|            |            |
    |            |            |            |            |            |<--email----|            |            |
    |            |            |            |            |            |--filter--->|            |            |
    |            |            |            |            |            |  (auto?)   |            |            |
    |            |            |            |            |            |--spawn-----|----------->|            |
    |            |            |            |            |            |            |            |--API------>|
    |            |            |            |            |            |            |            |<--response-|
    |            |            |            |            |            |<--output---|------------|            |
    |            |            |            |            |            |--reply via gws--------->|            |
```

## 18.5 Diagramme de sequence : message Google Chat

```
Utilisateur   GoogleChat   ChatGateway   Firestore    NanoClaw    ChatAPI     Container    CredProxy
    |            |             |             |            |            |            |            |
    |--message-->|             |             |            |            |            |            |
    |            |--webhook--->|             |            |            |            |            |
    |            |             |--verify tok-|            |            |            |            |
    |            |             |--rate check-|            |            |            |            |
    |            |             |--route----->|            |            |            |            |
    |            |             |  (space->   |            |            |            |            |
    |            |             |   agent)    |            |            |            |            |
    |            |             |--write----->|            |            |            |            |
    |            |             |             |<--poll(5s)-|            |            |            |
    |            |             |             |--msg------>|            |            |            |
    |            |             |             |            |--spawn---->|----------->|            |
    |            |             |             |            |            |            |--API------>|
    |            |             |             |            |            |            |<--resp.----|
    |            |             |             |            |<--output---|------------|            |
    |            |             |             |            |--send----->|            |            |
    |<--reponse--|-------------|-------------|------------|            |            |            |
```

## 18.6 Glossaire

| Terme                    | Definition                                                      |
|-------------------------|------------------------------------------------------------------|
| **Agent**               | Instance NanoClaw avec son propre email, memoire, canaux        |
| **Canal / Channel**     | Module de communication (WhatsApp, Gmail, Google Chat)          |
| **Container**           | Environnement Docker isole ou tourne Claude Agent SDK           |
| **Credential Proxy**    | Serveur HTTP local qui injecte les API keys dans les requetes   |
| **Circuit Breaker**     | Pattern qui coupe les requetes apres N echecs consecutifs       |
| **CLAUDE.md**           | Fichier de memoire/instructions de l'agent                      |
| **Group**               | Conversation enregistree (chat WhatsApp, inbox Gmail, etc.)     |
| **Group Queue**         | File d'attente qui limite les containers en parallele           |
| **IPC**                 | Communication inter-processus (host <-> container) via fichiers |
| **JID**                 | Identifiant unique d'un chat (ex: `gmail:main`, `gchat:spaces/X`) |
| **Main Group**          | Groupe principal d'un agent (privileges eleves, pas de trigger) |
| **Message Loop**        | Boucle de polling qui detecte les nouveaux messages             |
| **Mount**               | Volume Docker monte dans le container                           |
| **Polling**             | Interrogation periodique d'une source de donnees                |
| **Sender Allowlist**    | Liste des expediteurs autorises a declencher l'agent            |
| **Session**             | Session Claude persistante (contexte entre conversations)       |
| **Skill**               | Modification du code via un script (ex: `/add-telegram`)        |
| **Trigger**             | Pattern qui active l'agent (ex: `@Botti question`)             |
| **Watchdog**            | Script de surveillance qui alerte en cas de panne               |
| **Webhook**             | Notification push d'un service externe (Gmail, Google Chat)     |
| **gws CLI**             | CLI Google Workspace (Gmail, Calendar, Drive, Sheets, Docs)     |
| **Botti Voice**         | Application web vocale utilisant Gemini Live                    |
| **Chat Gateway**        | Service Cloud Run qui recoit les webhooks Google Chat           |
| **Firestore**           | Base de donnees NoSQL GCP utilisee comme bus de messages        |
| **Pub/Sub**             | Service de messaging GCP pour les notifications Gmail           |
| **GCS**                 | Google Cloud Storage (pour les backups)                         |
| **Plist**               | Fichier de configuration launchd (macOS)                        |
| **launchd**             | Gestionnaire de processus natif macOS                           |
| **Pino**                | Bibliotheque de logging structure JSON pour Node.js             |
| **Prometheus**          | Format standard de metriques (text exposition format)           |
| **Zod**                 | Bibliotheque de validation de schema TypeScript                 |
| **Baileys**             | Bibliotheque non-officielle pour l'API WhatsApp Web             |

---

## 18.7 Format de l'allowlist mount

Exemple complet de `~/.config/nanoclaw/mount-allowlist.json` :

```json
{
  "allowedRoots": [
    {
      "path": "~/projects",
      "allowReadWrite": true,
      "description": "Development projects"
    },
    {
      "path": "~/repos",
      "allowReadWrite": true,
      "description": "Git repositories"
    },
    {
      "path": "~/Documents/work",
      "allowReadWrite": false,
      "description": "Work documents (read-only)"
    }
  ],
  "blockedPatterns": [
    "password",
    "secret",
    "token"
  ],
  "nonMainReadOnly": true
}
```

## 18.8 Format de l'allowlist sender

Exemple complet de `~/.config/nanoclaw/sender-allowlist.json` :

```json
{
  "logDenied": true,
  "rules": {
    "group-jid-1@g.us": {
      "mode": "trigger",
      "allowed": ["33612345678@s.whatsapp.net", "33698765432@s.whatsapp.net"]
    },
    "group-jid-2@g.us": {
      "mode": "drop",
      "allowed": ["*"]
    },
    "gmail:main": {
      "mode": "trigger",
      "allowed": ["*"]
    }
  }
}
```

**Modes** :
- `trigger` : Le message est stocke dans SQLite mais ne declenche pas l'agent
  sauf si l'expediteur est dans la liste `allowed`
- `drop` : Le message est completement ignore (ni stocke, ni traite)

**Wildcards** :
- `*` : Tous les expediteurs sont autorises
- Si un JID n'a pas de regle, le comportement par defaut est `trigger` avec `["*"]`

## 18.9 Format de l'allowlist Gmail send

Exemple complet de `~/.config/nanoclaw/gmail-send-allowlist.json` :

```json
{
  "direct_send": [
    "yacine@bestoftours.co.uk",
    "eline@bestoftours.co.uk",
    "ahmed@bestoftours.co.uk",
    "bakoucheyacine@gmail.com"
  ],
  "notify_email": "yacine@bestoftours.co.uk",
  "cc_email": ""
}
```

**Logique d'envoi** :
1. L'agent veut envoyer un email a `destinataire@example.com`
2. Si `destinataire@example.com` est dans `direct_send` -> envoi direct
3. Sinon -> creation d'un brouillon + envoi de notification a `notify_email`
4. Si `cc_email` est configure -> CC automatique sur tous les emails sortants

## 18.10 Exemple de message Prometheus /metrics

```
# HELP nanoclaw_messages_received_total Total messages received from channels
# TYPE nanoclaw_messages_received_total counter
nanoclaw_messages_received_total{channel="whatsapp"} 142
nanoclaw_messages_received_total{channel="gmail"} 38
nanoclaw_messages_received_total{channel="google-chat"} 25

# HELP nanoclaw_messages_processed_total Total messages processed per group
# TYPE nanoclaw_messages_processed_total counter
nanoclaw_messages_processed_total{group="whatsapp_main"} 120
nanoclaw_messages_processed_total{group="gmail_main"} 38

# HELP nanoclaw_containers_spawned_total Total agent containers spawned
# TYPE nanoclaw_containers_spawned_total counter
nanoclaw_containers_spawned_total 158

# HELP nanoclaw_container_errors_total Total container agent errors
# TYPE nanoclaw_container_errors_total counter
nanoclaw_container_errors_total 3

# HELP nanoclaw_active_containers Number of currently running containers
# TYPE nanoclaw_active_containers gauge
nanoclaw_active_containers 2

# HELP nanoclaw_registered_groups Number of registered groups
# TYPE nanoclaw_registered_groups gauge
nanoclaw_registered_groups 3

# HELP nanoclaw_uptime_seconds Process uptime in seconds
# TYPE nanoclaw_uptime_seconds gauge
nanoclaw_uptime_seconds 86400

# HELP nanoclaw_circuit_breaker_state Circuit breaker state
# TYPE nanoclaw_circuit_breaker_state gauge
nanoclaw_circuit_breaker_state{state="closed"} 1
nanoclaw_circuit_breaker_state{state="open"} 0

# HELP nanoclaw_container_duration_seconds Time spent running agent containers
# TYPE nanoclaw_container_duration_seconds histogram
nanoclaw_container_duration_seconds_bucket{le="1"} 5
nanoclaw_container_duration_seconds_bucket{le="5"} 20
nanoclaw_container_duration_seconds_bucket{le="10"} 45
nanoclaw_container_duration_seconds_bucket{le="30"} 100
nanoclaw_container_duration_seconds_bucket{le="60"} 140
nanoclaw_container_duration_seconds_bucket{le="120"} 155
nanoclaw_container_duration_seconds_bucket{le="300"} 157
nanoclaw_container_duration_seconds_bucket{le="600"} 158
nanoclaw_container_duration_seconds_bucket{le="1800"} 158
nanoclaw_container_duration_seconds_bucket{le="+Inf"} 158
nanoclaw_container_duration_seconds_sum 3240.5
nanoclaw_container_duration_seconds_count 158

# HELP nanoclaw_api_request_duration_seconds API proxy upstream request latency
# TYPE nanoclaw_api_request_duration_seconds histogram
nanoclaw_api_request_duration_seconds_bucket{le="0.1"} 10
nanoclaw_api_request_duration_seconds_bucket{le="0.25"} 50
nanoclaw_api_request_duration_seconds_bucket{le="0.5"} 200
nanoclaw_api_request_duration_seconds_bucket{le="1"} 500
nanoclaw_api_request_duration_seconds_bucket{le="2.5"} 800
nanoclaw_api_request_duration_seconds_bucket{le="5"} 950
nanoclaw_api_request_duration_seconds_bucket{le="10"} 990
nanoclaw_api_request_duration_seconds_bucket{le="30"} 1000
nanoclaw_api_request_duration_seconds_bucket{le="+Inf"} 1000
nanoclaw_api_request_duration_seconds_sum 1500.2
nanoclaw_api_request_duration_seconds_count 1000
```

## 18.11 Exemple de reponse /health

```json
{
  "status": "ok",
  "assistant": "Botti",
  "uptime": 86400,
  "channels": [
    { "name": "whatsapp", "connected": true },
    { "name": "gmail", "connected": true },
    { "name": "google-chat", "connected": true }
  ],
  "groups": {
    "total": 3,
    "registered": ["whatsapp_main", "gmail_main", "gchat_main"]
  },
  "containers": {
    "active": 2,
    "maxConcurrent": 5
  },
  "circuitBreaker": {
    "state": "closed",
    "failures": 0
  }
}
```

## 18.12 Exemple de launchd plist

Exemple complet du plist pour l'agent Sam (`com.nanoclaw.sam.plist`) :

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
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/boty</string>
        <key>CREDENTIAL_PROXY_PORT</key>
        <string>3003</string>
        <key>GMAIL_MCP_DIR</key>
        <string>/Users/boty/.gmail-mcp-sam</string>
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

**Points importants** :
- `WorkingDirectory` pointe vers le dossier de l'instance, pas le dossier principal
- `ProgramArguments` utilise le `dist/index.js` du dossier principal (partage via symlink ou copie)
- `KeepAlive` = true : launchd relance le processus automatiquement en cas de crash
- `RunAtLoad` = true : demarre au login de l'utilisateur
- Les variables d'environnement dans le plist **ecrasent** celles du `.env`

## 18.13 Chat Gateway -- API endpoints

Le Chat Gateway (Cloud Run) expose les endpoints suivants :

| Methode | Endpoint           | Auth                      | Description                       |
|---------|-------------------|---------------------------|-----------------------------------|
| POST    | `/`               | CHAT_VERIFICATION_TOKEN   | Webhook Google Chat               |
| POST    | `/admin/mapping`  | ADMIN_API_KEY             | Modifier le mapping space->agent  |
| GET     | `/admin/mapping`  | ADMIN_API_KEY             | Lire le mapping space->agent      |
| GET     | `/health`         | None                      | Health check                      |

### Webhook Google Chat (POST /)

Le gateway recoit les evenements suivants de Google Chat :
- `ADDED_TO_SPACE` : Le bot est ajoute a un space
- `REMOVED_FROM_SPACE` : Le bot est retire d'un space
- `MESSAGE` : Un message est envoye dans un space ou le bot est present
- `CARD_CLICKED` : Un bouton de carte est clique (non utilise actuellement)

Pour les messages `MESSAGE`, le gateway :
1. Verifie le token de verification
2. Extrait le texte, l'expediteur, le space
3. Determine l'agent cible via le mapping Firestore
4. Ecrit le message dans Firestore
5. Retourne une reponse vide (200) a Google Chat

## 18.14 Botti Voice -- Architecture Python

```
botti-voice/
  web/
    __init__.py
    config.py           -- Configuration (Gemini API, memoire NanoClaw)
    gemini_bridge.py    -- Pont WebSocket <-> Gemini Live API
    workspace.py        -- Client Google Workspace (Gmail, Calendar)
    routes.py           -- Routes FastAPI (WebSocket, health)
    static/             -- Frontend HTML/CSS/JS
  Dockerfile
  requirements.txt
```

### Flux audio

1. Le navigateur capture l'audio du microphone via WebAudio API
2. L'audio est encode en PCM 16-bit et envoye via WebSocket
3. Le serveur `GeminiBridge` transmet l'audio a Gemini Live API
4. Gemini genere une reponse audio
5. L'audio de reponse est streame au navigateur via WebSocket
6. Le navigateur decode et joue l'audio via WebAudio API

### Selection de l'agent

A la connexion, le client peut specifier quel agent utiliser :
- `botti` (defaut), `sam`, `thais`
- Le prompt systeme est charge depuis le CLAUDE.md de l'agent selectionne
- Cela permet a Yacine de "parler" avec n'importe quel agent via la voix

## 18.15 Outils de développement installés (Mac Mini)

En plus du stack NanoClaw, les outils suivants sont installés sur le Mac Mini pour le développement et l'intégration :

| Outil | Version | Usage |
|-------|---------|-------|
| `gh` | CLI GitHub | Gestion repos, PRs, issues, auth |
| `supabase` | CLI Supabase | Base de données, auth, edge functions (futur) |
| `get-shit-done-cc` | Plugin Claude Code | Hooks de session, commit validation, phase detection |
| `firecrawl-mcp` | MCP Server | Web scraping/crawling via Claude Code (API key configurée) |
| `notebooklm-py` | Python | Intégration NotebookLM (avec browser Playwright) |
| `playwright` | Chromium headless | Automatisation browser, screenshots, tests E2E web |

### Configuration MCP (Claude Code)

Firecrawl est configuré comme serveur MCP dans `~/.claude/settings.json` :
```json
{
  "mcpServers": {
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": { "FIRECRAWL_API_KEY": "fc-..." }
    }
  }
}
```

Cela permet à Claude Code d'accéder directement au web crawling via les outils MCP (scrape, crawl, map, search).

### Supabase

Authentifié via token d'accès. Prêt pour :
- Hébergement de bases de données PostgreSQL
- Auth utilisateurs (si besoin d'un portail web pour les agents)
- Edge Functions (serverless, alternative à Cloud Run)
- Realtime subscriptions (alternative à Firestore pour le polling)

## 18.16 Historique des versions

| Version  | Date       | Changements majeurs                                    |
|---------|------------|--------------------------------------------------------|
| 1.0.0   | Oct 2025   | Version initiale, WhatsApp + containers                |
| 1.1.0   | Nov 2025   | Skills engine, multi-channel, Qodo integration         |
| 1.2.x   | Dec 2025-  | Reactions, vision, PDF, OAuth, remote control,         |
|         | Mars 2026  | credential proxy, media download, Gmail webhooks       |
| 2.0.0   | 4 Avr 2026 | Multi-agent (4), Google Chat, dashboard, tests 514,    |
|         |            | create-agent.sh, deploy.sh, circuit breaker,           |
|         |            | Prometheus metrics, watchdog, backup GCS, index split  |

---

*Document genere le 4 avril 2026 par Claude Code pour Botler 360 SAS.*
*Version du systeme : NanoClaw v2.0.0*
