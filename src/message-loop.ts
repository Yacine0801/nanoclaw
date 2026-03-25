/**
 * Message polling loop for NanoClaw.
 * Polls DB for new messages and dispatches to the group queue.
 */
import {
  ASSISTANT_NAME,
  POLL_INTERVAL,
  TIMEZONE,
  TRIGGER_PATTERN,
} from './config.js';
import { getMessagesSince, getNewMessages } from './db.js';
import { GroupQueue } from './group-queue.js';
import { logger } from './logger.js';
import { findChannel, formatMessages } from './router.js';
import {
  isTriggerAllowed,
  loadSenderAllowlist,
} from './sender-allowlist.js';
import { Channel, NewMessage, RegisteredGroup } from './types.js';

export interface MessageLoopDeps {
  channels: Channel[];
  queue: GroupQueue;
  getRegisteredGroups: () => Record<string, RegisteredGroup>;
  getLastTimestamp: () => string;
  setLastTimestamp: (ts: string) => void;
  getLastAgentTimestamp: () => Record<string, string>;
  setLastAgentTimestamp: (chatJid: string, ts: string) => void;
  saveState: () => void;
}

let running = false;

export async function startMessageLoop(deps: MessageLoopDeps): Promise<void> {
  if (running) {
    logger.debug('Message loop already running, skipping duplicate start');
    return;
  }
  running = true;

  logger.info(`NanoClaw running (trigger: @${ASSISTANT_NAME})`);

  while (true) {
    try {
      const registeredGroups = deps.getRegisteredGroups();
      const jids = Object.keys(registeredGroups);
      const { messages, newTimestamp } = getNewMessages(
        jids,
        deps.getLastTimestamp(),
        ASSISTANT_NAME,
      );

      if (messages.length > 0) {
        logger.info({ count: messages.length }, 'New messages');

        deps.setLastTimestamp(newTimestamp);
        deps.saveState();

        // Deduplicate by group
        const messagesByGroup = new Map<string, NewMessage[]>();
        for (const msg of messages) {
          const existing = messagesByGroup.get(msg.chat_jid);
          if (existing) {
            existing.push(msg);
          } else {
            messagesByGroup.set(msg.chat_jid, [msg]);
          }
        }

        for (const [chatJid, groupMessages] of messagesByGroup) {
          const group = registeredGroups[chatJid];
          if (!group) continue;

          const channel = findChannel(deps.channels, chatJid);
          if (!channel) {
            logger.warn(
              { chatJid },
              'No channel owns JID, skipping messages',
            );
            continue;
          }

          const isMainGroup = group.isMain === true;
          const needsTrigger =
            !isMainGroup && group.requiresTrigger !== false;

          if (needsTrigger) {
            const allowlistCfg = loadSenderAllowlist();
            const hasTrigger = groupMessages.some(
              (m) =>
                TRIGGER_PATTERN.test(m.content.trim()) &&
                (m.is_from_me ||
                  isTriggerAllowed(chatJid, m.sender, allowlistCfg)),
            );
            if (!hasTrigger) continue;
          }

          const lastAgentTs = deps.getLastAgentTimestamp();
          const allPending = getMessagesSince(
            chatJid,
            lastAgentTs[chatJid] || '',
            ASSISTANT_NAME,
          );
          const messagesToSend =
            allPending.length > 0 ? allPending : groupMessages;
          const formatted = formatMessages(messagesToSend, TIMEZONE);

          if (deps.queue.sendMessage(chatJid, formatted)) {
            logger.debug(
              { chatJid, count: messagesToSend.length },
              'Piped messages to active container',
            );
            deps.setLastAgentTimestamp(
              chatJid,
              messagesToSend[messagesToSend.length - 1].timestamp,
            );
            deps.saveState();
            channel
              .setTyping?.(chatJid, true)
              ?.catch((err) =>
                logger.warn(
                  { chatJid, err },
                  'Failed to set typing indicator',
                ),
              );
          } else {
            deps.queue.enqueueMessageCheck(chatJid);
          }
        }
      }
    } catch (err) {
      logger.error({ err }, 'Error in message loop');
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL));
  }
}
