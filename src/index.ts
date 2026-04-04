// Copyright (c) 2026 Botler 360 SAS. All rights reserved.
// See LICENSE.md for license terms.

import { ASSISTANT_NAME, CREDENTIAL_PROXY_PORT } from './config.js';
import { channels, initChannels } from './channel-manager.js';
import { setHealthDeps, startCredentialProxy } from './credential-proxy.js';
import { validateEnv } from './env-validation.js';
import {
  cleanupOrphans,
  ensureContainerRuntimeRunning,
  PROXY_BIND_HOST,
} from './container-runtime.js';
import { writeGroupsSnapshot } from './container-runner.js';
import { getMessagesSince, initDatabase } from './db.js';
import { GroupQueue } from './group-queue.js';
import { startIpcWatcher } from './ipc.js';
import { findChannel, formatOutbound } from './router.js';
import { startMessageLoop } from './message-loop.js';
import { processGroupMessages } from './message-processor.js';
import {
  getAvailableGroups,
  lastAgentTimestamp,
  loadState,
  registerGroup,
  registeredGroups,
  lastTimestamp,
  sessions,
  saveState,
  setLastTimestamp,
  setLastAgentTimestamp,
} from './state.js';
import { startSchedulerLoop } from './task-scheduler.js';
import { logger } from './logger.js';

// Re-export for backwards compatibility
export { escapeXml, formatMessages } from './router.js';
export { getAvailableGroups, _setRegisteredGroups } from './state.js';

const queue = new GroupQueue();

function createMessageLoopDeps() {
  return {
    channels,
    queue,
    getRegisteredGroups: () => registeredGroups,
    getLastTimestamp: () => lastTimestamp,
    setLastTimestamp,
    getLastAgentTimestamp: () => lastAgentTimestamp,
    setLastAgentTimestamp,
    saveState,
  };
}

/**
 * Startup recovery: check for unprocessed messages in registered groups.
 * Handles crash between advancing lastTimestamp and processing messages.
 */
function recoverPendingMessages(): void {
  for (const [chatJid, group] of Object.entries(registeredGroups)) {
    const sinceTimestamp = lastAgentTimestamp[chatJid] || '';
    const pending = getMessagesSince(chatJid, sinceTimestamp, ASSISTANT_NAME);
    if (pending.length > 0) {
      logger.info(
        { group: group.name, pendingCount: pending.length },
        'Recovery: found unprocessed messages',
      );
      queue.enqueueMessageCheck(chatJid);
    }
  }
}

function ensureContainerSystemRunning(): void {
  ensureContainerRuntimeRunning();
  cleanupOrphans();
}

async function main(): Promise<void> {
  validateEnv();
  ensureContainerSystemRunning();
  initDatabase();
  logger.info('Database initialized');
  loadState();

  // Remote control PIN guard
  const REMOTE_CONTROL_PIN = process.env.REMOTE_CONTROL_PIN || '';
  if (!REMOTE_CONTROL_PIN) {
    logger.warn('REMOTE_CONTROL_PIN not set — remote control is disabled');
  }

  // Start credential proxy (containers route API calls through this)
  const proxyServer = await startCredentialProxy(
    CREDENTIAL_PROXY_PORT,
    PROXY_BIND_HOST,
  );

  // Wire up health endpoint dependencies
  setHealthDeps({
    getChannels: () => channels,
    getRegisteredGroups: () => registeredGroups,
    assistantName: ASSISTANT_NAME,
  });

  // Graceful shutdown handlers
  const shutdown = async (signal: string) => {
    logger.info({ signal }, 'Shutdown signal received');
    proxyServer.close();
    await queue.shutdown(10000);
    for (const ch of channels) await ch.disconnect();
    process.exit(0);
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  // Initialize and connect all channels
  await initChannels(REMOTE_CONTROL_PIN);

  // Start subsystems (independently of connection handler)
  startSchedulerLoop({
    registeredGroups: () => registeredGroups,
    getSessions: () => sessions,
    queue,
    onProcess: (groupJid, proc, containerName, groupFolder) =>
      queue.registerProcess(groupJid, proc, containerName, groupFolder),
    sendMessage: async (jid, rawText) => {
      const channel = findChannel(channels, jid);
      if (!channel) {
        logger.warn({ jid }, 'No channel owns JID, cannot send message');
        return;
      }
      const text = formatOutbound(rawText);
      if (text) await channel.sendMessage(jid, text);
    },
  });
  startIpcWatcher({
    sendMessage: (jid, text) => {
      const channel = findChannel(channels, jid);
      if (!channel) throw new Error(`No channel for JID: ${jid}`);
      return channel.sendMessage(jid, text);
    },
    registeredGroups: () => registeredGroups,
    registerGroup,
    syncGroups: async (force: boolean) => {
      await Promise.all(
        channels
          .filter((ch) => ch.syncGroups)
          .map((ch) => ch.syncGroups!(force)),
      );
    },
    getAvailableGroups,
    writeGroupsSnapshot: (gf, im, ag, rj) =>
      writeGroupsSnapshot(gf, im, ag, rj),
  });
  queue.setProcessMessagesFn((chatJid) =>
    processGroupMessages(chatJid, channels, queue),
  );
  recoverPendingMessages();
  startMessageLoop(createMessageLoopDeps()).catch((err) => {
    logger.fatal({ err }, 'Message loop crashed unexpectedly');
    process.exit(1);
  });
}

// Guard: only run when executed directly, not when imported by tests
const isDirectRun =
  process.argv[1] &&
  new URL(import.meta.url).pathname ===
    new URL(`file://${process.argv[1]}`).pathname;

if (isDirectRun) {
  main().catch((err) => {
    logger.error({ err }, 'Failed to start NanoClaw');
    process.exit(1);
  });
}
