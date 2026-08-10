import type {
  ConversationLifecycle,
  LocalConversation,
  LocalMessage,
  MessageLifecycle,
} from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { lifecycleFilter } from './mapping';
import { claimMutation } from './mutationReceipt';

interface ConversationRow {
  id: string;
  title: string | null;
  lifecycle: ConversationLifecycle;
  created_at: string;
  updated_at: string;
  archived_at: string | null;
}

interface MessageRow {
  id: string;
  conversation_id: string;
  parent_message_id: string | null;
  role: LocalMessage['role'];
  content: string;
  lifecycle: MessageLifecycle;
  request_id: string | null;
  created_at: string;
  updated_at: string;
}

const CONVERSATION_COLUMNS = 'id, title, lifecycle, created_at, updated_at, archived_at';
const MESSAGE_COLUMNS = `id, conversation_id, parent_message_id, role, content, lifecycle,
  request_id, created_at, updated_at`;

function mapConversation(row: ConversationRow): LocalConversation {
  return {
    id: row.id,
    title: row.title,
    lifecycle: row.lifecycle,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    archivedAt: row.archived_at,
  };
}

function mapMessage(row: MessageRow): LocalMessage {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    parentMessageId: row.parent_message_id,
    role: row.role,
    content: row.content,
    lifecycle: row.lifecycle,
    requestId: row.request_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function insertConversation(
  transaction: RepositoryTransaction,
  conversation: LocalConversation,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'conversation', conversation.id, 'insert'))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO conversations
       (id, title, lifecycle, created_at, updated_at, archived_at, idempotency_key)
     VALUES ($id, $title, $lifecycle, $createdAt, $updatedAt, $archivedAt, $idempotencyId)`,
    {
      $id: conversation.id,
      $title: conversation.title,
      $lifecycle: conversation.lifecycle,
      $createdAt: conversation.createdAt,
      $updatedAt: conversation.updatedAt,
      $archivedAt: conversation.archivedAt,
      $idempotencyId: idempotencyId,
    },
  );
}

export async function getConversation(
  database: RepositoryConnection,
  id: string,
): Promise<LocalConversation | null> {
  const row = await database.getFirstAsync<ConversationRow>(
    `SELECT ${CONVERSATION_COLUMNS} FROM conversations WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapConversation(row);
}

export async function updateConversation(
  transaction: RepositoryTransaction,
  conversation: LocalConversation,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'conversation', conversation.id, 'update'))) {
    return;
  }
  await transaction.runAsync(
    `UPDATE conversations SET title = $title, lifecycle = $lifecycle,
       created_at = $createdAt, updated_at = $updatedAt, archived_at = $archivedAt
     WHERE id = $id`,
    {
      $id: conversation.id,
      $title: conversation.title,
      $lifecycle: conversation.lifecycle,
      $createdAt: conversation.createdAt,
      $updatedAt: conversation.updatedAt,
      $archivedAt: conversation.archivedAt,
    },
  );
}

export async function listConversations(
  database: RepositoryConnection,
  lifecycles?: readonly ConversationLifecycle[],
): Promise<LocalConversation[]> {
  const filter = lifecycleFilter('lifecycle', lifecycles);
  const rows = await database.getAllAsync<ConversationRow>(
    `SELECT ${CONVERSATION_COLUMNS} FROM conversations${filter.clause}
     ORDER BY updated_at DESC, id`,
    filter.params,
  );
  return rows.map(mapConversation);
}

export async function deleteConversation(
  transaction: RepositoryTransaction,
  id: string,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'conversation', id, 'delete'))) {
    return;
  }
  await transaction.runAsync('DELETE FROM conversations WHERE id = $id', { $id: id });
}

export async function insertMessage(
  transaction: RepositoryTransaction,
  message: LocalMessage,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'message', message.id, 'insert'))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO messages
       (id, conversation_id, parent_message_id, role, content, lifecycle, request_id, created_at, updated_at)
     VALUES ($id, $conversationId, $parentMessageId, $role, $content, $lifecycle,
       $requestId, $createdAt, $updatedAt)`,
    {
      $id: message.id,
      $conversationId: message.conversationId,
      $parentMessageId: message.parentMessageId,
      $role: message.role,
      $content: message.content,
      $lifecycle: message.lifecycle,
      $requestId: message.requestId,
      $createdAt: message.createdAt,
      $updatedAt: message.updatedAt,
    },
  );
}

export async function getMessage(
  database: RepositoryConnection,
  id: string,
): Promise<LocalMessage | null> {
  const row = await database.getFirstAsync<MessageRow>(
    `SELECT ${MESSAGE_COLUMNS} FROM messages WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapMessage(row);
}

export async function updateMessage(
  transaction: RepositoryTransaction,
  message: LocalMessage,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'message', message.id, 'update'))) {
    return;
  }
  await transaction.runAsync(
    `UPDATE messages SET conversation_id = $conversationId, parent_message_id = $parentMessageId,
       role = $role, content = $content, lifecycle = $lifecycle, request_id = $requestId,
       created_at = $createdAt, updated_at = $updatedAt
     WHERE id = $id`,
    {
      $id: message.id,
      $conversationId: message.conversationId,
      $parentMessageId: message.parentMessageId,
      $role: message.role,
      $content: message.content,
      $lifecycle: message.lifecycle,
      $requestId: message.requestId,
      $createdAt: message.createdAt,
      $updatedAt: message.updatedAt,
    },
  );
}

export async function listMessages(
  database: RepositoryConnection,
  conversationId: string,
  lifecycles?: readonly MessageLifecycle[],
): Promise<LocalMessage[]> {
  const filter = lifecycleFilter('lifecycle', lifecycles);
  const lifecycleClause = filter.clause.replace(/^ WHERE /, ' AND ');
  const params = Array.isArray(filter.params)
    ? { $conversationId: conversationId }
    : { ...filter.params, $conversationId: conversationId };
  const rows = await database.getAllAsync<MessageRow>(
    `SELECT ${MESSAGE_COLUMNS} FROM messages
     WHERE conversation_id = $conversationId${lifecycleClause}
     ORDER BY created_at, id`,
    params,
  );
  return rows.map(mapMessage);
}

export async function searchMessages(
  database: RepositoryConnection,
  query: string,
  limit = 50,
): Promise<LocalMessage[]> {
  const rows = await database.getAllAsync<MessageRow>(
    `SELECT m.id, m.conversation_id, m.parent_message_id, m.role, m.content, m.lifecycle,
            m.request_id, m.created_at, m.updated_at
       FROM message_search
       JOIN messages m ON m.rowid = message_search.rowid
      WHERE message_search MATCH $query
      ORDER BY bm25(message_search), m.created_at DESC, m.id
      LIMIT $limit`,
    { $query: query, $limit: limit },
  );
  return rows.map(mapMessage);
}
