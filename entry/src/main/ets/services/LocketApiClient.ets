import { http } from '@kit.NetworkKit';
import {
  AuthSession,
  ChatMessage,
  ConversationSummary,
  FriendItem,
  MomentItem,
  MomentsFeedResult,
  MomentTimestamp,
  UploadMomentOptions,
  UserProfile,
  WidgetMomentData
} from '../models/LocketModels';
import { SessionManager } from './SessionManager';

const FIREBASE_API_KEY = 'AIzaSyCQngaaXQIfJaH0aS2l7REgIjD7nL431So';
const FIREBASE_AUTH_URL = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;
const FIREBASE_REFRESH_URL = `https://securetoken.googleapis.com/v1/token?key=${FIREBASE_API_KEY}`;
const LOCKET_API_BASE = 'https://api.locketcamera.com';
const FIRESTORE_BASE = 'https://firestore.googleapis.com/v1/projects/locket-4252a/databases/(default)/documents';
const FIRESTORE_LOCKET_BASE = 'https://firestore.googleapis.com/v1/projects/locket-4252a/databases/locket/documents';
const FIREBASE_STORAGE_BASE = 'https://firebasestorage.googleapis.com/v0/b/locket-img/o';

interface FirebaseLoginPayload {
  email: string;
  password: string;
  returnSecureToken: boolean;
}

interface FirebaseLoginResponse {
  localId?: string;
  email?: string;
  displayName?: string;
  idToken?: string;
  refreshToken?: string;
  expiresIn?: string;
  error?: FirebaseErrorDetail;
}

interface FirebaseErrorDetail {
  message?: string;
}

interface FirebaseRefreshResponse {
  id_token?: string;
  refresh_token?: string;
  expires_in?: string;
  user_id?: string;
  error?: FirebaseErrorDetail;
}

interface FetchUserBodyData {
  user_uid: string;
}

interface FetchUserRequestBody {
  data: FetchUserBodyData;
}

interface RawUserData {
  uid?: string;
  first_name?: string;
  last_name?: string;
  username?: string;
  profile_picture_url?: string;
}

interface FetchUserResult {
  data?: RawUserData;
}

interface FetchUserResponse {
  result?: FetchUserResult;
}

interface FirestoreStringField {
  stringValue?: string;
}

interface FirestoreFriendFields {
  user?: FirestoreStringField;
}

interface FirestoreFriendDoc {
  fields?: FirestoreFriendFields;
}

interface FirestoreFriendsResponse {
  documents?: FirestoreFriendDoc[];
  nextPageToken?: string;
}

interface GetMomentsBodyData {
  excluded_users: string[];
  last_fetch: number;
  should_count_missed_moments: boolean;
  sync_token?: string;
}

interface GetMomentsRequestBody {
  data: GetMomentsBodyData;
}

interface RawMomentItem {
  canonical_uid?: string;
  user?: string;
  thumbnail_url?: string;
  video_url?: string | null;
  caption?: string;
  date?: MomentTimestamp;
}

interface GetMomentsResult {
  data?: RawMomentItem[];
  missed_moments_count?: number;
  sync_token?: string;
}

interface GetMomentsResponse {
  result?: GetMomentsResult;
}

interface ProtobufInt64Value {
  '@type': string;
  value: string;
}

interface ReactMomentBodyData {
  moment_uid: string;
  reaction: string;
  from_memory: boolean;
  intensity: ProtobufInt64Value;
}

interface ReactMomentRequestBody {
  data: ReactMomentBodyData;
}

interface MomentUidBodyData {
  moment_uid: string;
}

interface MomentUidRequestBody {
  data: MomentUidBodyData;
}

interface SendChatMessageBodyData {
  receiver_uid: string;
  msg: string;
  moment_uid: string | null;
  from_memory: boolean;
  intensity: ProtobufInt64Value;
  client_token: string;
}

interface SendChatMessageRequestBody {
  data: SendChatMessageBodyData;
}

interface GenericApiError {
  message?: string;
  status?: string;
}

interface GenericApiResult {
  status?: number;
  error?: GenericApiError;
}

interface GenericApiResponse {
  result?: GenericApiResult;
  error?: GenericApiError;
}

interface FirestoreTimestampField {
  timestampValue?: string;
}

interface FirestoreIntegerField {
  integerValue?: string;
}

interface FirestoreArrayValue {
  values?: FirestoreStringField[];
}

interface FirestoreArrayField {
  arrayValue?: FirestoreArrayValue;
}

interface FirestoreHistoryFields {
  canonical_uid?: FirestoreStringField;
  user?: FirestoreStringField;
  thumbnail_url?: FirestoreStringField;
  video_url?: FirestoreStringField;
  caption?: FirestoreStringField;
  date?: FirestoreTimestampField;
}

interface FirestoreHistoryDoc {
  name?: string;
  fields?: FirestoreHistoryFields;
}

interface FirestoreHistoryResponse {
  documents?: FirestoreHistoryDoc[];
  nextPageToken?: string;
}

interface FirestoreMessageFields {
  sender?: FirestoreStringField;
  sender_uid?: FirestoreStringField;
  body?: FirestoreStringField;
  msg?: FirestoreStringField;
  text?: FirestoreStringField;
  moment_uid?: FirestoreStringField;
  moment?: FirestoreStringField;
  reply_moment?: FirestoreStringField;
  thumbnail_url?: FirestoreStringField;
  created_at?: FirestoreTimestampField;
  create_time?: FirestoreTimestampField;
  date?: FirestoreIntegerField;
}

interface FirestoreMessageDoc {
  name?: string;
  createTime?: string;
  fields?: FirestoreMessageFields;
}

interface FirestoreMessagesResponse {
  documents?: FirestoreMessageDoc[];
}

interface FirestoreLatestMessageFields {
  body?: FirestoreStringField;
  msg?: FirestoreStringField;
  text?: FirestoreStringField;
  sender?: FirestoreStringField;
  sender_uid?: FirestoreStringField;
  thumbnail_url?: FirestoreStringField;
  reply_moment?: FirestoreStringField;
  moment_uid?: FirestoreStringField;
  moment?: FirestoreStringField;
  created_at?: FirestoreTimestampField;
  create_time?: FirestoreTimestampField;
}

interface FirestoreMapValue {
  fields?: FirestoreLatestMessageFields;
}

interface FirestoreLatestMessageField {
  stringValue?: string;
  mapValue?: FirestoreMapValue;
}

interface FirestoreConversationFields {
  uid?: FirestoreStringField;
  conversation_uid?: FirestoreStringField;
  other_user?: FirestoreStringField;
  user?: FirestoreStringField;
  members?: FirestoreArrayField;
  latest_message?: FirestoreLatestMessageField;
  last_message?: FirestoreLatestMessageField;
  last_updated?: FirestoreTimestampField;
  updated_at?: FirestoreTimestampField;
  last_updated_ms?: FirestoreIntegerField;
}

interface FirestoreConversationDoc {
  name?: string;
  updateTime?: string;
  fields?: FirestoreConversationFields;
}

interface FirestoreConversationsResponse {
  documents?: FirestoreConversationDoc[];
}

interface FirebaseStorageUploadResponse {
  name?: string;
  downloadTokens?: string;
}

interface ResumableUploadMetadata {
  creator: string;
  visibility: string;
}

interface ResumableUploadStartBody {
  name: string;
  contentType: string;
  bucket: string;
  metadata: ResumableUploadMetadata;
}

interface PostMomentOverlay {
  overlay_id: string;
}

interface PostMomentBodyData {
  thumbnail_url: string;
  overlays: PostMomentOverlay[];
  sent_to_self_only: boolean;
  sent_to_all: boolean;
  recipients: string[];
  md5: string;
  caption: string;
}

interface PostMomentRequestBody {
  data: PostMomentBodyData;
}

interface FetchUserByUsernameBodyData {
  username: string;
}

interface FetchUserByUsernameRequestBody {
  data: FetchUserByUsernameBodyData;
}

interface FetchUserByUsernameResult {
  data?: RawUserData;
  user?: RawUserData;
}

interface FetchUserByUsernameResponse {
  result?: FetchUserByUsernameResult;
}

interface FriendActionBodyData {
  user_uid: string;
}

interface FriendActionRequestBody {
  data: FriendActionBodyData;
}

export class LocketApiClient {
  private static instance: LocketApiClient | null = null;
  private userCache: Map<string, UserProfile> = new Map();
  private momentThumbnailCache: Map<string, string> = new Map();

  public static getInstance(): LocketApiClient {
    if (LocketApiClient.instance === null) {
      LocketApiClient.instance = new LocketApiClient();
    }
    return LocketApiClient.instance;
  }

  private buildHeaders(idToken?: string, contentType: string = 'application/json'): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': contentType,
      'Accept': 'application/json',
      'Accept-Language': 'en-US',
      'X-Ios-Bundle-Identifier': 'com.locket.Locket',
      'User-Agent': 'FirebaseAuth.iOS/10.23.1 com.locket.Locket/2.8.0 iPhone/18.0 hw/iPhone12_1',
      'X-Client-Version': 'iOS/FirebaseSDK/10.23.1/FirebaseCore-iOS',
      'X-Firebase-GMPID': '1:641029076083:ios:cc8eb46290d69b234fa606'
    };
    if (idToken !== undefined && idToken.length > 0) {
      headers['Authorization'] = `Bearer ${idToken}`;
    }
    return headers;
  }

  private async requestJson<T>(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body?: string
  ): Promise<T> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: method,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      const rawText = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}: ${rawText}`);
      }
      return JSON.parse(rawText) as T;
    } finally {
      httpRequest.destroy();
    }
  }

  public async login(email: string, password: string): Promise<AuthSession> {
    const payload: FirebaseLoginPayload = {
      email: email.trim(),
      password: password,
      returnSecureToken: true
    };
    const res = await this.requestJson<FirebaseLoginResponse>(
      FIREBASE_AUTH_URL,
      http.RequestMethod.POST,
      this.buildHeaders(),
      JSON.stringify(payload)
    );

    if (res.idToken === undefined || res.localId === undefined || res.refreshToken === undefined) {
      const errMsg = res.error?.message ?? 'Đăng nhập thất bại';
      throw new Error(errMsg);
    }

    const expiresInSec = Number(res.expiresIn ?? '3600');
    const session: AuthSession = {
      localId: res.localId,
      email: res.email ?? email.trim(),
      displayName: res.displayName ?? '',
      idToken: res.idToken,
      refreshToken: res.refreshToken,
      expiresAt: Date.now() + expiresInSec * 1000
    };
    await SessionManager.getInstance().saveSession(session);
    return session;
  }

  public async ensureValidToken(): Promise<AuthSession> {
    const sessionMgr = SessionManager.getInstance();
    const session = sessionMgr.getSession();
    if (session === null) {
      throw new Error('Chưa đăng nhập');
    }
    if (!sessionMgr.isTokenExpiringSoon()) {
      return session;
    }
    const formBody = `grant_type=refresh_token&refresh_token=${encodeURIComponent(session.refreshToken)}`;
    const res = await this.requestJson<FirebaseRefreshResponse>(
      FIREBASE_REFRESH_URL,
      http.RequestMethod.POST,
      this.buildHeaders(undefined, 'application/x-www-form-urlencoded'),
      formBody
    );
    if (res.id_token === undefined) {
      throw new Error(res.error?.message ?? 'Không thể làm mới phiên đăng nhập');
    }
    const expiresInSec = Number(res.expires_in ?? '3600');
    const updated: AuthSession = {
      localId: res.user_id ?? session.localId,
      email: session.email,
      displayName: session.displayName,
      idToken: res.id_token,
      refreshToken: res.refresh_token ?? session.refreshToken,
      expiresAt: Date.now() + expiresInSec * 1000
    };
    await sessionMgr.saveSession(updated);
    return updated;
  }

  public async fetchUser(userUid: string, forceRefresh: boolean = false): Promise<UserProfile> {
    if (!forceRefresh && this.userCache.has(userUid)) {
      const cached = this.userCache.get(userUid);
      if (cached !== undefined) {
        return cached;
      }
    }
    const session = await this.ensureValidToken();
    const body: FetchUserRequestBody = {
      data: { user_uid: userUid }
    };
    const res = await this.requestJson<FetchUserResponse>(
      `${LOCKET_API_BASE}/fetchUserV2`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
    const raw = res.result?.data;
    const profile: UserProfile = {
      uid: raw?.uid ?? userUid,
      firstName: raw?.first_name ?? '',
      lastName: raw?.last_name ?? '',
      username: raw?.username ?? '',
      profilePictureUrl: raw?.profile_picture_url ?? ''
    };
    this.userCache.set(userUid, profile);
    return profile;
  }

  public async getAllFriends(): Promise<FriendItem[]> {
    const session = await this.ensureValidToken();
    const friendUids: string[] = [];
    let pageToken = '';

    do {
      const tokenQuery = pageToken.length > 0 ? `&pageToken=${encodeURIComponent(pageToken)}` : '';
      const url = `${FIRESTORE_BASE}/users/${session.localId}/friends?pageSize=100${tokenQuery}`;
      const res = await this.requestJson<FirestoreFriendsResponse>(
        url,
        http.RequestMethod.GET,
        { 'Authorization': `Bearer ${session.idToken}` }
      );
      const docs = res.documents ?? [];
      for (let i = 0; i < docs.length; i++) {
        const uid = docs[i].fields?.user?.stringValue;
        if (uid !== undefined && uid.length > 0) {
          friendUids.push(uid);
        }
      }
      pageToken = res.nextPageToken ?? '';
    } while (pageToken.length > 0);

    const friends: FriendItem[] = [];
    for (let i = 0; i < friendUids.length; i++) {
      try {
        const profile = await this.fetchUser(friendUids[i]);
        friends.push({
          uid: profile.uid,
          firstName: profile.firstName,
          lastName: profile.lastName,
          username: profile.username,
          profilePictureUrl: profile.profilePictureUrl
        });
      } catch (_err) {
        friends.push({
          uid: friendUids[i],
          firstName: 'Bạn bè',
          lastName: '',
          username: friendUids[i].substring(0, 8),
          profilePictureUrl: ''
        });
      }
    }
    return friends;
  }

  public async getLatestMoments(pageToken?: string, filterUserUid?: string): Promise<MomentsFeedResult> {
    const session = await this.ensureValidToken();
    const tokenQuery = pageToken !== undefined && pageToken.length > 0
      ? `&pageToken=${encodeURIComponent(pageToken)}`
      : '';
    const url = `${FIRESTORE_LOCKET_BASE}/history/${encodeURIComponent(session.localId)}/entries?orderBy=date%20desc&pageSize=30${tokenQuery}`;

    const res = await this.requestJson<FirestoreHistoryResponse>(
      url,
      http.RequestMethod.GET,
      { 'Authorization': `Bearer ${session.idToken}` }
    );

    const docs = res.documents ?? [];
    const moments: MomentItem[] = [];

    for (let i = 0; i < docs.length; i++) {
      const doc = docs[i];
      const fields = doc.fields;
      if (fields === undefined) {
        continue;
      }
      const docName = doc.name ?? '';
      const lastSlash = docName.lastIndexOf('/');
      const docId = lastSlash >= 0 ? docName.substring(lastSlash + 1) : '';
      const canonicalUid = fields.canonical_uid?.stringValue ?? docId;
      const senderUid = fields.user?.stringValue ?? '';

      if (filterUserUid !== undefined && filterUserUid.length > 0 && senderUid !== filterUserUid) {
        continue;
      }

      let createdAtSeconds = 0;
      const tsStr = fields.date?.timestampValue;
      if (tsStr !== undefined && tsStr.length > 0) {
        const parsedMs = Date.parse(tsStr);
        if (!Number.isNaN(parsedMs)) {
          createdAtSeconds = Math.floor(parsedMs / 1000);
        }
      }

      let senderName = senderUid.length > 0 ? senderUid.substring(0, 8) : 'Locket';
      let senderAvatar = '';
      if (senderUid.length > 0) {
        try {
          const sender = await this.fetchUser(senderUid);
          const full = `${sender.firstName} ${sender.lastName}`.trim();
          senderName = full.length > 0 ? full : (sender.username.length > 0 ? sender.username : senderName);
          senderAvatar = sender.profilePictureUrl;
        } catch (_err) {
          // Keep fallback sender name
        }
      }

      const thumbUrl = fields.thumbnail_url?.stringValue ?? '';
      if (canonicalUid.length > 0 && thumbUrl.length > 0) {
        this.momentThumbnailCache.set(canonicalUid, thumbUrl);
      }

      moments.push({
        canonicalUid: canonicalUid,
        userUid: senderUid,
        thumbnailUrl: thumbUrl,
        videoUrl: fields.video_url?.stringValue ?? '',
        caption: fields.caption?.stringValue ?? '',
        createdAtSeconds: createdAtSeconds,
        senderName: senderName,
        senderAvatar: senderAvatar
      });
    }

    if ((filterUserUid === undefined || filterUserUid.length === 0) &&
      (pageToken === undefined || pageToken.length === 0) &&
      moments.length > 0) {
      const latest = moments[0];
      await SessionManager.getInstance().saveLatestWidgetMoment({
        canonicalUid: latest.canonicalUid,
        thumbnailUrl: latest.thumbnailUrl,
        caption: latest.caption,
        senderName: latest.senderName,
        createdAtSeconds: latest.createdAtSeconds
      });
    }

    return {
      moments: moments,
      missedMomentsCount: 0,
      syncToken: res.nextPageToken ?? ''
    };
  }

  public async reactToMoment(momentUid: string, emoji: string): Promise<void> {
    const session = await this.ensureValidToken();
    const body: ReactMomentRequestBody = {
      data: {
        moment_uid: momentUid,
        reaction: emoji,
        from_memory: false,
        intensity: {
          '@type': 'type.googleapis.com/google.protobuf.Int64Value',
          value: '0'
        }
      }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/reactToMoment`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
  }

  public async deleteMoment(momentUid: string): Promise<void> {
    const session = await this.ensureValidToken();
    const body: MomentUidRequestBody = {
      data: { moment_uid: momentUid }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/deleteMomentV2`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
  }

  public async markMomentAsViewed(momentUid: string): Promise<void> {
    const session = await this.ensureValidToken();
    const body: MomentUidRequestBody = {
      data: { moment_uid: momentUid }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/markMomentAsViewed`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
  }

  private generateUuidV4(): string {
    const hex = '0123456789abcdef';
    let uuid = '';
    for (let i = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) {
        uuid += '-';
      } else if (i === 14) {
        uuid += '4';
      } else if (i === 19) {
        const r = Math.floor(Math.random() * 16);
        uuid += hex.charAt((r & 0x3) | 0x8);
      } else {
        const r = Math.floor(Math.random() * 16);
        uuid += hex.charAt(r);
      }
    }
    return uuid;
  }

  public async sendChatMessage(receiverUid: string, text: string, momentUid?: string): Promise<void> {
    const session = await this.ensureValidToken();
    const trimmed = text.trim();
    const hasMoment = momentUid !== undefined && momentUid.length > 0;
    if (trimmed.length === 0 && !hasMoment) {
      return;
    }
    const msgText = trimmed.length === 0 && hasMoment ? '\u200b' : trimmed;
    const clientToken = this.generateUuidV4().toUpperCase();
    const body: SendChatMessageRequestBody = {
      data: {
        receiver_uid: receiverUid,
        msg: msgText,
        moment_uid: hasMoment ? (momentUid as string) : null,
        from_memory: false,
        intensity: {
          value: '0',
          '@type': 'type.googleapis.com/google.protobuf.Int64Value'
        },
        client_token: clientToken
      }
    };
    const res = await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/sendChatMessageV2`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
    if (res.error !== undefined) {
      throw new Error(res.error.message ?? 'Gửi tin nhắn thất bại');
    }
    if (res.result?.error !== undefined) {
      throw new Error(res.result.error.message ?? 'Gửi tin nhắn thất bại');
    }
  }

  private parseFirestoreMessages(docs: FirestoreMessageDoc[]): ChatMessage[] {
    const messages: ChatMessage[] = [];
    for (let i = 0; i < docs.length; i++) {
      const doc = docs[i];
      const fields = doc.fields;
      if (fields === undefined) {
        continue;
      }
      const docName = doc.name ?? '';
      const lastSlash = docName.lastIndexOf('/');
      const id = lastSlash >= 0 ? docName.substring(lastSlash + 1) : `msg_${i}`;

      const senderUid = fields.sender?.stringValue ?? fields.sender_uid?.stringValue ?? '';
      const text = fields.body?.stringValue ?? fields.msg?.stringValue ?? fields.text?.stringValue ?? '';
      const momentUid = fields.reply_moment?.stringValue ?? fields.moment_uid?.stringValue ?? fields.moment?.stringValue ?? '';
      const thumbnailUrl = fields.thumbnail_url?.stringValue ?? '';

      let createdAtMs = 0;
      const tsStr = fields.created_at?.timestampValue ?? fields.create_time?.timestampValue ?? doc.createTime;
      if (tsStr !== undefined && tsStr.length > 0) {
        const parsed = Date.parse(tsStr);
        if (!Number.isNaN(parsed)) {
          createdAtMs = parsed;
        }
      } else if (fields.date?.integerValue !== undefined) {
        const num = Number(fields.date.integerValue);
        if (!Number.isNaN(num)) {
          createdAtMs = num > 1000000000000 ? num : num * 1000;
        }
      }

      if (text.length > 0 || momentUid.length > 0 || thumbnailUrl.length > 0) {
        messages.push({
          id: id,
          senderUid: senderUid,
          text: text,
          momentUid: momentUid,
          createdAtMs: createdAtMs,
          thumbnailUrl: thumbnailUrl
        });
      }
    }
    messages.sort((a: ChatMessage, b: ChatMessage) => a.createdAtMs - b.createdAtMs);
    return messages;
  }

  public async getMessagesWithUser(otherUid: string): Promise<ChatMessage[]> {
    const session = await this.ensureValidToken();
    const convUrl = `${FIRESTORE_BASE}/users/${encodeURIComponent(session.localId)}/conversations?pageSize=50`;
    const convRes = await this.requestJson<FirestoreConversationsResponse>(
      convUrl,
      http.RequestMethod.GET,
      { 'Authorization': `Bearer ${session.idToken}` }
    );

    const convDocs = convRes.documents ?? [];
    let cid = '';
    for (let i = 0; i < convDocs.length; i++) {
      const convDoc = convDocs[i];
      const cFields = convDoc.fields;
      if (cFields === undefined) {
        continue;
      }
      const friendUid = this.extractFriendUidFromConversation(cFields, session.localId);
      if (friendUid === otherUid) {
        const docName = convDoc.name ?? '';
        const lastSlash = docName.lastIndexOf('/');
        cid = lastSlash >= 0 ? docName.substring(lastSlash + 1) : docName;
        break;
      }
    }

    if (cid.length === 0) {
      return [];
    }

    const msgUrl = `${FIRESTORE_BASE}/conversations/${encodeURIComponent(cid)}/messages?orderBy=created_at%20asc&pageSize=50`;
    const msgRes = await this.requestJson<FirestoreMessagesResponse>(
      msgUrl,
      http.RequestMethod.GET,
      { 'Authorization': `Bearer ${session.idToken}` }
    );
    const messages = this.parseFirestoreMessages(msgRes.documents ?? []);
    for (let i = 0; i < messages.length; i++) {
      const m = messages[i];
      if (m.momentUid.length > 0 && (m.thumbnailUrl === undefined || m.thumbnailUrl.length === 0)) {
        const resolved = await this.resolveMomentThumbnail(m.momentUid, session);
        if (resolved.length > 0) {
          m.thumbnailUrl = resolved;
        }
      }
    }
    return messages;
  }

  private async resolveMomentThumbnail(momentUid: string, session: AuthSession): Promise<string> {
    if (this.momentThumbnailCache.has(momentUid)) {
      return this.momentThumbnailCache.get(momentUid) ?? '';
    }
    try {
      const url = `${FIRESTORE_LOCKET_BASE}/history/${encodeURIComponent(session.localId)}/entries/${encodeURIComponent(momentUid)}`;
      const doc = await this.requestJson<FirestoreHistoryDoc>(
        url,
        http.RequestMethod.GET,
        { 'Authorization': `Bearer ${session.idToken}` }
      );
      const thumb = doc.fields?.thumbnail_url?.stringValue ?? '';
      if (thumb.length > 0) {
        this.momentThumbnailCache.set(momentUid, thumb);
      }
      return thumb;
    } catch (_err) {
      return '';
    }
  }

  private extractFriendUidFromConversation(fields: FirestoreConversationFields, myUid: string): string {
    const memberValues = fields.members?.arrayValue?.values ?? [];
    if (memberValues.length > 0) {
      for (let j = 0; j < memberValues.length; j++) {
        const candidate = memberValues[j].stringValue ?? '';
        if (candidate.length > 0 && candidate !== myUid) {
          return candidate;
        }
      }
      return '';
    }
    const otherUser = fields.other_user?.stringValue ?? '';
    if (otherUser.length > 0 && otherUser !== myUid) {
      return otherUser;
    }
    const fallbackUser = fields.user?.stringValue ?? '';
    if (fallbackUser.length > 0 && fallbackUser !== myUid) {
      return fallbackUser;
    }
    return '';
  }

  private extractLatestMessagePreview(fields: FirestoreConversationFields): string {
    const latestField = fields.latest_message ?? fields.last_message;
    if (latestField === undefined) {
      return '';
    }
    const mapFields = latestField.mapValue?.fields;
    if (mapFields !== undefined) {
      const rawBody = mapFields.body?.stringValue ?? mapFields.msg?.stringValue ?? mapFields.text?.stringValue ?? '';
      const cleaned = rawBody.replace(/\u200b/g, '').trim();
      if (cleaned.length > 0) {
        return cleaned;
      }
      const hasThumb = (mapFields.thumbnail_url?.stringValue ?? '').length > 0;
      const hasMoment = (mapFields.reply_moment?.stringValue ?? '').length > 0 ||
        (mapFields.moment_uid?.stringValue ?? '').length > 0 ||
        (mapFields.moment?.stringValue ?? '').length > 0;
      if (hasThumb || hasMoment) {
        return 'Đã gửi một ảnh';
      }
      return '';
    }
    const plain = (latestField.stringValue ?? '').replace(/\u200b/g, '').trim();
    return plain;
  }

  private extractLatestMessageTimestampMs(fields: FirestoreConversationFields): number {
    const latestField = fields.latest_message ?? fields.last_message;
    const mapFields = latestField?.mapValue?.fields;
    if (mapFields !== undefined) {
      const tsStr = mapFields.created_at?.timestampValue ?? mapFields.create_time?.timestampValue;
      if (tsStr !== undefined && tsStr.length > 0) {
        const parsed = Date.parse(tsStr);
        if (!Number.isNaN(parsed)) {
          return parsed;
        }
      }
    }
    return 0;
  }

  public async getConversations(): Promise<ConversationSummary[]> {
    const session = await this.ensureValidToken();
    const convUrl = `${FIRESTORE_BASE}/users/${encodeURIComponent(session.localId)}/conversations?pageSize=50`;
    const convRes = await this.requestJson<FirestoreConversationsResponse>(
      convUrl,
      http.RequestMethod.GET,
      { 'Authorization': `Bearer ${session.idToken}` }
    );

    const convDocs = convRes.documents ?? [];
    const dedupedByFriend = new Map<string, ConversationSummary>();

    for (let i = 0; i < convDocs.length; i++) {
      const convDoc = convDocs[i];
      const fields = convDoc.fields;
      if (fields === undefined) {
        continue;
      }

      const friendUid = this.extractFriendUidFromConversation(fields, session.localId);
      if (friendUid.length === 0) {
        continue;
      }

      const docName = convDoc.name ?? '';
      const lastSlash = docName.lastIndexOf('/');
      const convId = lastSlash >= 0 ? docName.substring(lastSlash + 1) : `conv_${i}`;
      const lastMessage = this.extractLatestMessagePreview(fields);

      let lastUpdatedMs = this.extractLatestMessageTimestampMs(fields);
      if (lastUpdatedMs === 0) {
        const tsStr = fields.last_updated?.timestampValue ?? fields.updated_at?.timestampValue ?? convDoc.updateTime;
        if (tsStr !== undefined && tsStr.length > 0) {
          const parsed = Date.parse(tsStr);
          if (!Number.isNaN(parsed)) {
            lastUpdatedMs = parsed;
          }
        } else if (fields.last_updated_ms?.integerValue !== undefined) {
          const num = Number(fields.last_updated_ms.integerValue);
          if (!Number.isNaN(num)) {
            lastUpdatedMs = num > 1000000000000 ? num : num * 1000;
          }
        }
      }

      const existing = dedupedByFriend.get(friendUid);
      if (existing !== undefined && existing.lastUpdatedMs >= lastUpdatedMs) {
        continue;
      }

      let friendName = existing !== undefined ? existing.friendName : friendUid.substring(0, 8);
      let friendAvatar = existing !== undefined ? existing.friendAvatar : '';
      if (existing === undefined) {
        try {
          const profile = await this.fetchUser(friendUid);
          const full = `${profile.firstName} ${profile.lastName}`.trim();
          friendName = full.length > 0 ? full : (profile.username.length > 0 ? profile.username : friendName);
          friendAvatar = profile.profilePictureUrl;
        } catch (_err) {
          // Keep fallback name
        }
      }

      dedupedByFriend.set(friendUid, {
        conversationId: convId,
        friendUid: friendUid,
        friendName: friendName,
        friendAvatar: friendAvatar,
        lastMessage: lastMessage,
        lastUpdatedMs: lastUpdatedMs
      });
    }

    const summaries: ConversationSummary[] = [];
    dedupedByFriend.forEach((summary: ConversationSummary) => {
      summaries.push(summary);
    });
    summaries.sort((a: ConversationSummary, b: ConversationSummary) => b.lastUpdatedMs - a.lastUpdatedMs);
    return summaries;
  }

  private generateHexId(): string {
    const hex = '0123456789abcdef';
    let out = '';
    for (let i = 0; i < 32; i++) {
      out += hex.charAt(Math.floor(Math.random() * 16));
    }
    return out;
  }

  private extractHeaderCaseInsensitive(headerObj: Object | undefined, targetName: string): string {
    if (headerObj === undefined || headerObj === null) {
      return '';
    }
    const targetLower = targetName.toLowerCase();
    const record = headerObj as Record<string, string>;
    const keys = Object.keys(record);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (key.toLowerCase() === targetLower) {
        const val = record[key];
        if (typeof val === 'string' && val.length > 0) {
          return val;
        }
      }
    }
    return '';
  }

  public async uploadAndPostPhotoMoment(imageBytes: ArrayBuffer, options: UploadMomentOptions): Promise<void> {
    const session = await this.ensureValidToken();
    const contentType = options.contentType !== undefined && options.contentType.length > 0
      ? options.contentType
      : 'image/webp';
    const ext = contentType === 'image/jpeg' ? 'jpg' : 'webp';
    const fileName = `${Date.now()}_${this.generateHexId().substring(0, 8)}.${ext}`;
    const objectPath = 'users/' + session.localId + '/moments/thumbnails/' + fileName;
    const encodedPath = encodeURIComponent(objectPath);
    const initUrl = `${FIREBASE_STORAGE_BASE}/${encodedPath}?uploadType=resumable&name=${encodedPath}`;

    // Step 1: Initiate Firebase Storage resumable upload session
    let uploadUrl = '';
    const startBody: ResumableUploadStartBody = {
      name: objectPath,
      contentType: 'image/*',
      bucket: '',
      metadata: {
        creator: session.localId,
        visibility: 'private'
      }
    };

    const startReq = http.createHttp();
    try {
      const startHeaders: Record<string, string> = {
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer ' + session.idToken,
        'x-goog-upload-protocol': 'resumable',
        'x-goog-upload-command': 'start',
        'x-goog-upload-content-length': '' + imageBytes.byteLength,
        'x-goog-upload-content-type': 'image/webp',
        'x-firebase-storage-version': 'ios/10.13.0',
        'x-firebase-gmpid': '1:641029076083:ios:cc8eb46290d69b234fa609',
        'User-Agent': 'com.locket.Locket/1.43.1 iPhone/17.3 hw/iPhone15_3 (GTMSUF/1)'
      };
      const startRes = await startReq.request(initUrl, {
        method: http.RequestMethod.POST,
        header: startHeaders,
        extraData: JSON.stringify(startBody),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 20000
      });
      const startRaw = typeof startRes.result === 'string' ? startRes.result : JSON.stringify(startRes.result);
      if (startRes.responseCode < 200 || startRes.responseCode >= 300) {
        throw new Error(`Upload init failed (${startRes.responseCode}): ${startRaw}`);
      }
      uploadUrl = this.extractHeaderCaseInsensitive(startRes.header, 'x-goog-upload-url');
    } finally {
      startReq.destroy();
    }

    if (uploadUrl.length === 0) {
      throw new Error('Không nhận được URL tải ảnh lên');
    }

    // Step 2: Upload bytes via PUT to resumable session URL
    let uploadRes: FirebaseStorageUploadResponse = {};
    const putReq = http.createHttp();
    try {
      const putHeaders: Record<string, string> = {
        'Content-Type': 'application/octet-stream',
        'x-goog-upload-protocol': 'resumable',
        'x-goog-upload-command': 'upload, finalize',
        'x-goog-upload-offset': '0',
        'x-goog-upload-content-length': '' + imageBytes.byteLength
      };
      const putRes = await putReq.request(uploadUrl, {
        method: http.RequestMethod.PUT,
        header: putHeaders,
        extraData: imageBytes,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      const rawText = typeof putRes.result === 'string' ? putRes.result : JSON.stringify(putRes.result);
      if (putRes.responseCode < 200 || putRes.responseCode >= 300) {
        throw new Error(`Resumable upload failed (${putRes.responseCode}): ${rawText}`);
      }
      if (rawText.trim().length > 0) {
        uploadRes = JSON.parse(rawText) as FirebaseStorageUploadResponse;
      }
    } finally {
      putReq.destroy();
    }

    // Step 3: Read downloadTokens (with fallback metadata GET if empty)
    let downloadTokens = uploadRes.downloadTokens ?? '';
    let downloadToken = downloadTokens.split(',')[0].trim();
    if (downloadToken.length === 0) {
      const metaUrl = `${FIREBASE_STORAGE_BASE}/${encodedPath}`;
      const metaRes = await this.requestJson<FirebaseStorageUploadResponse>(
        metaUrl,
        http.RequestMethod.GET,
        { 'Authorization': 'Bearer ' + session.idToken }
      );
      downloadTokens = metaRes.downloadTokens ?? '';
      downloadToken = downloadTokens.split(',')[0].trim();
    }
    if (downloadToken.length === 0) {
      throw new Error('Không nhận được token tải ảnh');
    }
    const thumbnailUrl = `${FIREBASE_STORAGE_BASE}/${encodedPath}?alt=media&token=${downloadToken}`;

    // Step 4: Publish moment via postMomentV2
    const nowSec = Math.floor(Date.now() / 1000);
    const md5Value = `${this.generateHexId()}_${nowSec}`;
    const trimmedCaption = options.caption.trim();
    const postBody: PostMomentRequestBody = {
      data: {
        thumbnail_url: thumbnailUrl,
        overlays: [],
        sent_to_self_only: false,
        sent_to_all: options.sentToAll,
        recipients: options.sentToAll ? [] : options.recipients,
        md5: md5Value,
        caption: trimmedCaption
      }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/postMomentV2`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(postBody)
    );

    // Immediately sync Home Screen Widgets with the newly posted moment
    let senderName = session.displayName.length > 0 ? session.displayName : 'Bạn';
    const cachedMe = this.userCache.get(session.localId);
    if (cachedMe !== undefined) {
      const fullName = `${cachedMe.firstName} ${cachedMe.lastName}`.trim();
      if (fullName.length > 0) {
        senderName = fullName;
      } else if (cachedMe.username.length > 0) {
        senderName = cachedMe.username;
      }
    }
    const widgetData: WidgetMomentData = {
      canonicalUid: md5Value,
      thumbnailUrl: thumbnailUrl,
      caption: trimmedCaption,
      senderName: senderName,
      createdAtSeconds: nowSec
    };
    await SessionManager.getInstance().saveLatestWidgetMoment(widgetData);
    await SessionManager.getInstance().notifyAllWidgets(widgetData);
  }

  public async fetchUserByUsername(username: string): Promise<UserProfile | null> {
    const trimmed = username.trim().replace(/^@/, '');
    if (trimmed.length === 0) {
      return null;
    }
    const session = await this.ensureValidToken();
    const body: FetchUserByUsernameRequestBody = {
      data: { username: trimmed }
    };
    const res = await this.requestJson<FetchUserByUsernameResponse>(
      `${LOCKET_API_BASE}/fetchUserForInviteToken`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
    const raw = res.result?.data ?? res.result?.user;
    if (raw === undefined || raw.uid === undefined || raw.uid.length === 0) {
      return null;
    }
    const profile: UserProfile = {
      uid: raw.uid,
      firstName: raw.first_name ?? '',
      lastName: raw.last_name ?? '',
      username: raw.username ?? trimmed,
      profilePictureUrl: raw.profile_picture_url ?? ''
    };
    this.userCache.set(profile.uid, profile);
    return profile;
  }

  public async sendFriendRequest(userUid: string): Promise<void> {
    const session = await this.ensureValidToken();
    const body: FriendActionRequestBody = {
      data: { user_uid: userUid }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/sendFriendRequest`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
  }

  public async removeFriend(userUid: string): Promise<void> {
    const session = await this.ensureValidToken();
    const body: FriendActionRequestBody = {
      data: { user_uid: userUid }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/removeFriend`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
  }
}
