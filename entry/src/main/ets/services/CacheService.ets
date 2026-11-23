import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ChatMessage,
  ConversationSummary,
  FriendItem,
  MomentItem
} from '../models/LocketModels';

const CACHE_PREF_NAME = 'locket_data_cache';
const KEY_MOMENTS = 'cache_moments_json';
const KEY_FRIENDS = 'cache_friends_json';
const KEY_CONVERSATIONS = 'cache_conversations_json';
const KEY_MESSAGE_UIDS = 'cache_message_uids_json';
const KEY_MESSAGES_PREFIX = 'cache_messages_';

const MAX_CACHED_MOMENTS = 30;
const MAX_CACHED_MESSAGES_PER_FRIEND = 50;

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CacheService';

export class CacheService {
  private static instance: CacheService | null = null;
  private pref: preferences.Preferences | null = null;
  private cachedMoments: MomentItem[] = [];
  private cachedFriends: FriendItem[] = [];
  private cachedConversations: ConversationSummary[] = [];
  private cachedMessagesMap: Map<string, ChatMessage[]> = new Map();
  private trackedMessageUids: string[] = [];

  public static getInstance(): CacheService {
    if (CacheService.instance === null) {
      CacheService.instance = new CacheService();
    }
    return CacheService.instance;
  }

  private getMessagesKey(friendUid: string): string {
    return `${KEY_MESSAGES_PREFIX}${friendUid}`;
  }

  public async init(context: common.Context): Promise<void> {
    try {
      if (this.pref === null) {
        this.pref = await preferences.getPreferences(context, CACHE_PREF_NAME);
      }
      await this.hydrateMemoryFromPref();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'CacheService init failed: %{public}s', msg);
    }
  }

  private async hydrateMemoryFromPref(): Promise<void> {
    if (this.pref === null) {
      return;
    }
    try {
      const rawMoments = await this.pref.get(KEY_MOMENTS, '') as string;
      if (rawMoments.length > 0) {
        const parsed = JSON.parse(rawMoments) as MomentItem[];
        if (Array.isArray(parsed)) {
          this.cachedMoments = parsed.slice(0, MAX_CACHED_MOMENTS);
        }
      }
    } catch (_err) {
      this.cachedMoments = [];
    }

    try {
      const rawFriends = await this.pref.get(KEY_FRIENDS, '') as string;
      if (rawFriends.length > 0) {
        const parsed = JSON.parse(rawFriends) as FriendItem[];
        if (Array.isArray(parsed)) {
          this.cachedFriends = parsed;
        }
      }
    } catch (_err) {
      this.cachedFriends = [];
    }

    try {
      const rawConvs = await this.pref.get(KEY_CONVERSATIONS, '') as string;
      if (rawConvs.length > 0) {
        const parsed = JSON.parse(rawConvs) as ConversationSummary[];
        if (Array.isArray(parsed)) {
          this.cachedConversations = parsed;
        }
      }
    } catch (_err) {
      this.cachedConversations = [];
    }

    try {
      const rawUids = await this.pref.get(KEY_MESSAGE_UIDS, '') as string;
      if (rawUids.length > 0) {
        const parsedUids = JSON.parse(rawUids) as string[];
        if (Array.isArray(parsedUids)) {
          this.trackedMessageUids = parsedUids.filter((u: string) => typeof u === 'string' && u.length > 0);
        }
      }
      for (let i = 0; i < this.trackedMessageUids.length; i++) {
        const uid = this.trackedMessageUids[i];
        try {
          const rawMsgs = await this.pref.get(this.getMessagesKey(uid), '') as string;
          if (rawMsgs.length > 0) {
            const parsedMsgs = JSON.parse(rawMsgs) as ChatMessage[];
            if (Array.isArray(parsedMsgs)) {
              const trimmed = parsedMsgs.length > MAX_CACHED_MESSAGES_PER_FRIEND
                ? parsedMsgs.slice(parsedMsgs.length - MAX_CACHED_MESSAGES_PER_FRIEND)
                : parsedMsgs;
              this.cachedMessagesMap.set(uid, trimmed);
            }
          }
        } catch (_msgErr) {
          // Skip malformed message cache entry
        }
      }
    } catch (_err) {
      this.trackedMessageUids = [];
    }
  }

  public getCachedMoments(): MomentItem[] {
    try {
      return [...this.cachedMoments];
    } catch (_err) {
      return [];
    }
  }

  public async saveMoments(moments: MomentItem[]): Promise<void> {
    try {
      const trimmed = moments.slice(0, MAX_CACHED_MOMENTS);
      this.cachedMoments = [...trimmed];
      if (this.pref !== null) {
        await this.pref.put(KEY_MOMENTS, JSON.stringify(trimmed));
        await this.pref.flush();
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'saveMoments failed: %{public}s', msg);
    }
  }

  public getCachedFriends(): FriendItem[] {
    try {
      return [...this.cachedFriends];
    } catch (_err) {
      return [];
    }
  }

  public async saveFriends(friends: FriendItem[]): Promise<void> {
    try {
      this.cachedFriends = [...friends];
      if (this.pref !== null) {
        await this.pref.put(KEY_FRIENDS, JSON.stringify(friends));
        await this.pref.flush();
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'saveFriends failed: %{public}s', msg);
    }
  }

  public getCachedConversations(): ConversationSummary[] {
    try {
      return [...this.cachedConversations];
    } catch (_err) {
      return [];
    }
  }

  public async saveConversations(convs: ConversationSummary[]): Promise<void> {
    try {
      this.cachedConversations = [...convs];
      if (this.pref !== null) {
        await this.pref.put(KEY_CONVERSATIONS, JSON.stringify(convs));
        await this.pref.flush();
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'saveConversations failed: %{public}s', msg);
    }
  }

  public getCachedMessages(friendUid: string): ChatMessage[] {
    try {
      if (friendUid.length === 0) {
        return [];
      }
      const inMemory = this.cachedMessagesMap.get(friendUid);
      if (inMemory !== undefined) {
        return [...inMemory];
      }
      if (this.pref !== null) {
        const raw = this.pref.getSync(this.getMessagesKey(friendUid), '') as string;
        if (raw.length > 0) {
          const parsed = JSON.parse(raw) as ChatMessage[];
          if (Array.isArray(parsed)) {
            const trimmed = parsed.length > MAX_CACHED_MESSAGES_PER_FRIEND
              ? parsed.slice(parsed.length - MAX_CACHED_MESSAGES_PER_FRIEND)
              : parsed;
            this.cachedMessagesMap.set(friendUid, trimmed);
            return [...trimmed];
          }
        }
      }
      return [];
    } catch (_err) {
      return [];
    }
  }

  public async saveMessages(friendUid: string, msgs: ChatMessage[]): Promise<void> {
    try {
      if (friendUid.length === 0) {
        return;
      }
      const trimmed = msgs.length > MAX_CACHED_MESSAGES_PER_FRIEND
        ? msgs.slice(msgs.length - MAX_CACHED_MESSAGES_PER_FRIEND)
        : [...msgs];
      this.cachedMessagesMap.set(friendUid, trimmed);
      if (!this.trackedMessageUids.includes(friendUid)) {
        this.trackedMessageUids = [...this.trackedMessageUids, friendUid];
      }
      if (this.pref !== null) {
        await this.pref.put(this.getMessagesKey(friendUid), JSON.stringify(trimmed));
        await this.pref.put(KEY_MESSAGE_UIDS, JSON.stringify(this.trackedMessageUids));
        await this.pref.flush();
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'saveMessages failed: %{public}s', msg);
    }
  }

  public async clearAll(): Promise<void> {
    try {
      this.cachedMoments = [];
      this.cachedFriends = [];
      this.cachedConversations = [];
      this.cachedMessagesMap.clear();
      this.trackedMessageUids = [];
      if (this.pref !== null) {
        await this.pref.clear();
        await this.pref.flush();
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'clearAll failed: %{public}s', msg);
    }
  }
}
