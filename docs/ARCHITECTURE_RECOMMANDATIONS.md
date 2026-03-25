# Recommandations Architecture — Scaling Multi-Agents NanoClaw

**Date** : 2026-03-25
**Contexte** : NanoClaw + Agent Hub pour Best of Tours
**Agents actuels** : Botti (Sam), Thaïs, Alan (en cours)
**Objectif** : Passer à 10-20+ agents pour différents clients/verticaux

---

## 1. Ce qui empêche ou ralentit le scaling multi-agents

### 1.1 ASSISTANT_NAME est un singleton global

Le problème le plus structurel.

`src/config.ts:11` :
```typescript
export const ASSISTANT_NAME = process.env.ASSISTANT_NAME || envConfig.ASSISTANT_NAME || 'Andy';
```

Ce nom unique est utilisé partout :
- **Trigger pattern** (`config.ts:59`) : `@${ASSISTANT_NAME}` est le déclencheur global
- **Filtrage des messages bot** (`db.ts:104`, `whatsapp.ts:224`) : identifiés par le préfixe `ASSISTANT_NAME:`
- **Préfixe des messages sortants** (`whatsapp.ts:297`) : `${ASSISTANT_NAME}: ${text}`
- **Requêtes SQL** (`db.ts:296, 334`) : `content NOT LIKE '${botPrefix}:%'`

**Conséquence** : un processus NanoClaw = un seul agent. 10 agents = 10 processus (ou refactoring majeur).

### 1.2 Processus unique, DB unique, credential proxy unique

- **SQLite singleton** (`db.ts:15`) : une seule instance, un seul fichier `store/messages.db`
- **Credential proxy** (`credential-proxy.ts:127`) : un seul port (3001), une seule API key. Tous les containers partagent le même credential
- **GroupQueue** (`index.ts:78`) : `MAX_CONCURRENT_CONTAINERS = 5` par défaut. À 10+ agents avec plusieurs groupes chacun, c'est insuffisant
- **Daily spend limit unique** (`credential-proxy.ts:24`) : $20 pour TOUS les agents combinés. Pas de budget par agent

### 1.3 Le modèle de channels est 1:1 avec les credentials

- **WhatsApp** (`whatsapp.ts`) : une seule session Baileys, un seul numéro, un seul `store/auth/`. Impossible d'avoir 2 numéros dans le même processus
- **Gmail** (`gmail.ts`) : une seule paire OAuth (`~/.gmail-mcp/`). Un seul compte email
- **Le barrel import** (`channels/index.ts`) charge tous les channels au démarrage sans notion d'agent owner

### 1.4 Le groupe "main" est un concept rigide

`index.ts:164-166` : un seul main group avec privilèges spéciaux (pas de trigger, accès projet, registration). Si on a 10 agents, chacun a besoin de son propre "main".

### 1.5 Agent Hub et NanoClaw sont des systèmes parallèles non intégrés

- **Double polling Gmail** : NanoClaw via googleapis, Agent Hub via `gws` CLI — mêmes boîtes mail, deux chemins
- **Double cost tracking** : NanoClaw dans `credential-proxy.ts` (Anthropic), Agent Hub dans `cost_tracker.py` (Gemini + Anthropic)
- **Double processed_ids** : NanoClaw en mémoire (`gmail.ts:39`), Agent Hub en fichiers JSON
- **Pas de bridge IPC** : Agent Hub écrit des fichiers IPC que NanoClaw ne lit pas

### 1.6 Limites hardware

Docker sur Mac mini : 5 containers concurrents est déjà agressif pour Opus. 20 agents = 20+ containers simultanés en heure de pointe. Un serveur Linux avec plus de RAM serait nécessaire.

---

## 2. Comment rendre la création d'un agent "5 minutes"

### 2.1 Format idéal de définition d'agent

Le format `agent-hub/agents/botti.json` est proche. Ce qui manque pour un format unifié :

```json
{
  "name": "botti",
  "display_name": "Botti",
  "trigger": "@Botti",
  "model": "claude-opus-4-6",
  "daily_budget_usd": 5.0,
  "channels": {
    "whatsapp": { "auth_dir": "store/auth/botti/" },
    "gmail": { "creds_dir": "~/.gmail-mcp/botti/" }
  },
  "main_group_jid": "120363...@g.us",
  "claude_md": "agents/botti/CLAUDE.md",
  "max_concurrent_containers": 2,
  "external_comms": "supervised"
}
```

### 2.2 Provisioning à automatiser

Aujourd'hui créer un agent requiert :
1. Configurer des credentials GWS (OAuth consent) — **ne peut pas être automatisé**
2. Créer un CLAUDE.md — **semi-automatisable** via template
3. Enregistrer des groupes dans la DB — **automatisable**
4. Créer les dossiers `groups/` — **automatisable**
5. Configurer le sender-allowlist — **automatisable**
6. Créer un plist launchd — **automatisable**
7. Redémarrer — **devrait devenir un hot reload**

Cible :
```bash
nanoclaw add-agent --config agents/new-agent.json
# Auto: crée dossiers, DB, CLAUDE.md template, plist launchd
# Manuel: OAuth pour les comptes GWS
```

### 2.3 Isolation per-agent recommandée

**Processus séparés par agent.** Cela :
- Préserve la simplicité du design (REQUIREMENTS.md : "small enough to understand")
- Évite un refactoring massif des singletons
- Donne une isolation naturelle (un crash n'affecte pas les autres)
- Correspond déjà au pattern Thaïs (`com.nanoclaw.thais` sur port 3002)

---

## 3. Abstractions manquantes et couplages trop serrés

### 3.1 Il manque une abstraction "Agent"

`index.ts` (593 lignes) gère encore : state machine, processing, agent launch, remote control, channel callbacks, démarrage. Il manque une classe ou module "Agent" qui encapsule `{name, trigger, channels[], groups[], credentialProxy, queue}`. Aujourd'hui l'agent est implicite — c'est le processus lui-même.

### 3.2 Le modèle group/folder est correct mais sous-spécifié

- Pas de concept d'ownership : quel agent possède quel groupe ?
- `groups/global/CLAUDE.md` est partagé par tous les agents — à 10 agents, ça n'a plus de sens (Botti voyage et Thaïs compta ne partagent pas de contexte)
- Convention de nommage `whatsapp_family-chat` est par channel, pas par agent. Il faudrait `botti/whatsapp_family-chat`

### 3.3 La personnalité est mêlée à l'infrastructure

Le CLAUDE.md du main group mélange :
- Instructions de personnalité ("You are Andy...")
- Documentation d'infrastructure ("Container Mounts", "Managing Groups")
- Règles de formatage ("NEVER use markdown")
- Tutorials ("Scheduling for Other Groups")

Pour le multi-agent, séparer :
1. **Agent persona** : qui, ton, compétences (par agent)
2. **Infrastructure docs** : IPC, mounts, DB (commun, injecté automatiquement)
3. **Channel formatting** : règles WhatsApp vs Telegram (par channel)

### 3.4 Le container-runner hardcode trop de chemins

`container-runner.ts` buildVolumeMounts hardcode :
- `~/.gmail-mcp` (ligne 169) — pas paramétrique par agent
- `~/.firebase-mcp` (ligne 179) — global
- `~/.config/gws` (ligne 189) — global

Pour le multi-agent, ces chemins doivent venir du JSON de config de l'agent.

---

## 4. Agent Hub Python vs NanoClaw : quelle stratégie ?

### 4.1 Ce que fait chaque système

| Capacité | NanoClaw | Agent Hub |
|----------|----------|-----------|
| WhatsApp | Oui (Baileys) | Non |
| Gmail (OAuth direct) | Oui (googleapis) | Non (gws CLI) |
| Claude containers | Oui | Non |
| Triage Gemini Flash | Non | Oui |
| Chat Google Workspace | Non | Oui (gws CLI) |
| Calendar webhooks | Non | Oui |
| External comms policy | Non | Oui |
| Scheduled tasks | Oui | Non |
| Shadow mode | Non | Oui |
| Multi-agent routing | Non (1 agent = 1 process) | Oui (N agents, 1 process) |
| Container isolation | Oui (Docker) | Non |
| Token health monitoring | Non | Oui |

### 4.2 Recommandation

**Court terme (maintenant)** : Option B — Agent Hub reste le "tier léger" (triage Gemini à $0.002/appel), NanoClaw le "tier lourd" (escalades Claude à $1-5/appel). Bridge IPC pour connecter les deux.

**Moyen terme (3-6 mois)** : Option A — NanoClaw absorbe Agent Hub. Le triage Gemini devient un channel preprocessing. Les channels GWS deviennent `channels/gchat.ts`, `channels/gcalendar.ts`. Un seul système à maintenir.

**Arguments** :
- Maintenir deux systèmes à 10+ agents est un fardeau opérationnel
- Le code Python a prouvé le concept du triage, mais la valeur est dans la logique, pas dans le runtime
- NanoClaw a la meilleure isolation (containers) et le meilleur deployment (launchd)

---

## 5. Points de défaillance uniques (SPOF)

### 5.1 Reboot machine

| Composant | Récupère automatiquement ? |
|-----------|---------------------------|
| NanoClaw (launchd plist) | Oui |
| Docker Desktop | Oui (si auto-start) |
| WhatsApp reconnection | Oui (`shouldReconnect`) |
| Messages pendants | Oui (`recoverPendingMessages()`) |
| Agent Hub Python | **Non** — pas de plist launchd |
| Containers en cours | Non — tués, nettoyés par `cleanupOrphans()` |

### 5.2 Docker crash mid-conversation

- Si output déjà envoyé → `status: 'success'` (container-runner.ts:497). Correct.
- Si pas d'output → erreur + rollback curseur (index.ts:268-286). Retry au prochain cycle.
- Orphan cleanup au restart. Design solide.

### 5.3 Token expiry

| Token | Recovery |
|-------|----------|
| Anthropic API key | Pas d'expiration. Si révoquée → 401 sur tous les containers. **Pas d'alerte.** |
| Gmail OAuth | Refresh auto (`gmail.ts:76-85`). Si refresh token expire (90j) → backoff silencieux. **Pas d'alerte.** |
| WhatsApp Baileys | QR code requis → `process.exit(1)` (whatsapp.ts:95). Launchd relance, mais boucle infinie sans scan humain. **Pas d'alerte.** |
| Agent Hub GWS | `token_manager.py` vérifie toutes les heures, écrit dans `/tmp/`. **Personne ne lit ces fichiers.** |

### 5.4 Anthropic API down

- Le SDK gère ses propres retries dans le container
- `isRateLimitError()` dans `anti-spam.ts` envoie un message "indisponible" avec cooldown
- **Il manque** : un circuit breaker global. Si l'API est down 30 min, chaque container retry indépendamment, consommant des slots inutilement.

### 5.5 SQLite corruption

- **Pas de backups automatiques.** `store/messages.db` est le seul point de vérité (sessions, groupes, tasks, curseurs)
- **Pas de WAL mode** (`db.ts` ne fait pas `PRAGMA journal_mode=WAL`). Les écritures concurrentes (message-loop + IPC + scheduler) peuvent bloquer
- **Impact** : perte de tout l'état. Reconfiguration manuelle complète.

### 5.6 Ce qui manque en monitoring

- Aucune alerte proactive (WhatsApp/email quand ça casse)
- Pas de healthcheck endpoint NanoClaw
- Pas de métriques (uptime, messages/heure, latence container, coût/agent/jour)
- Pas de backup SQLite automatique
- Pas de dashboard (même un `status.json` lu par le main group)

---

## 6. Plan d'action recommandé

### Phase 1 — Fondations (2-4 semaines)

1. **Paramétrer ASSISTANT_NAME par agent** : extraire du config global vers la config par-agent. Débloque le multi-processus.
2. **Script multi-instance** : un `nanoclaw spawn-agent` qui crée le plist launchd, les dossiers, et la DB. Étendre le pattern Thaïs (`com.nanoclaw.thais`).
3. **Budget par agent** : étendre `daily-spend.json` avec un breakdown par agent.
4. **Backup SQLite cron** : copie quotidienne de `store/messages.db`.
5. **WAL mode** : `PRAGMA journal_mode=WAL` dans `db.ts` pour les écritures concurrentes.

### Phase 2 — Unification Agent Hub (4-8 semaines)

6. **Bridge IPC Agent Hub → NanoClaw** : Agent Hub écrit les escalades dans le format IPC de NanoClaw.
7. **Porter le triage Gemini** en module NanoClaw (ou le garder comme satellite avec API).
8. **Channels GWS** : `channels/gchat.ts` et `channels/gcalendar.ts`.
9. **Token health alerting** : le token_manager envoie une alerte WhatsApp au main group quand un token expire.

### Phase 3 — Opérationnel 10+ agents (8-12 semaines)

10. **CLI `nanoclaw add-agent`** : provisioning automatisé complet.
11. **Monitoring** : healthcheck endpoint + alertes WhatsApp + dashboard status.json.
12. **Scaling infra** : Linux avec plus de RAM, ou répartition multi-machines.

---

## Fichiers critiques pour l'implémentation

| Fichier | Pourquoi |
|---------|----------|
| `src/config.ts` | Le singleton ASSISTANT_NAME est LE premier blocage à éliminer |
| `src/index.ts` | L'orchestrateur qui mélange state, processing et startup — doit devenir un "agent runtime" instanciable |
| `src/container-runner.ts` | Les volume mounts hardcodés doivent devenir paramétriques par agent |
| `src/credential-proxy.ts` | Un seul port, un seul credential — doit supporter N credential sets |
| `src/db.ts` | Pas de WAL, pas de backup — risque de corruption sous charge |
| `agent-hub/orchestrator.py` | Le système parallèle à absorber ou bridger proprement |
