import { http } from '@kit.NetworkKit';
import {
  AuthSession,
  ChatMessage,
  FriendItem,
  MomentItem,
  MomentsFeedResult,
  MomentTimestamp,
  UploadMomentOptions,
  UserProfile
} from '../models/LocketModels';
import { SessionManager } from './SessionManager';

const FIREBASE_API_KEY = 'AIzaSyCQngaaXQIfJaH0aS2l7REgIjD7nL431So';
const FIREBASE_AUTH_URL = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;
const FIREBASE_REFRESH_URL = `https://securetoken.googleapis.com/v1/token?key=${FIREBASE_API_KEY}`;
const LOCKET_API_BASE = 'https://api.locketcamera.com';
const FIRESTORE_BASE = 'https://firestore.googleapis.com/v1/projects/locket-4252a/databases/(default)/documents';
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
  moment_uid: string;
  from_memory: boolean;
  intensity: ProtobufInt64Value;
}

interface SendChatMessageRequestBody {
  data: SendChatMessageBodyData;
}

interface GenericApiResult {
  status?: number;
}

interface GenericApiResponse {
  result?: GenericApiResult;
}

interface FirestoreTimestampField {
  timestampValue?: string;
}

interface FirestoreIntegerField {
  integerValue?: string;
}

interface FirestoreMessageFields {
  sender?: FirestoreStringField;
  sender_uid?: FirestoreStringField;
  body?: FirestoreStringField;
  msg?: FirestoreStringField;
  text?: FirestoreStringField;
  moment_uid?: FirestoreStringField;
  moment?: FirestoreStringField;
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

interface FirestoreConversationFields {
  conversation_uid?: FirestoreStringField;
  other_user?: FirestoreStringField;
  user?: FirestoreStringField;
}

interface FirestoreConversationDoc {
  name?: string;
  fields?: FirestoreConversationFields;
}

interface FirestoreConversationsResponse {
  documents?: FirestoreConversationDoc[];
}

interface FirebaseStorageUploadResponse {
  name?: string;
  downloadTokens?: string;
}

interface PostMomentOverlay {
  overlay_id: string;
}

interface PostMomentBodyData {
  thumbnail_url: string;
  caption: string;
  recipients: string[];
  sent_to_all: boolean;
  overlays: PostMomentOverlay[];
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

  public async getLatestMoments(syncToken?: string, filterUserUid?: string): Promise<MomentsFeedResult> {
    const session = await this.ensureValidToken();
    const bodyData: GetMomentsBodyData = {
      excluded_users: [],
      last_fetch: 1,
      should_count_missed_moments: true
    };
    if (syncToken !== undefined && syncToken.length > 0) {
      bodyData.sync_token = syncToken;
    }
    const body: GetMomentsRequestBody = { data: bodyData };
    const res = await this.requestJson<GetMomentsResponse>(
      `${LOCKET_API_BASE}/getLatestMomentV2`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );

    const rawMoments = res.result?.data ?? [];
    const moments: MomentItem[] = [];

    for (let i = 0; i < rawMoments.length; i++) {
      const m = rawMoments[i];
      const senderUid = m.user ?? '';
      if (filterUserUid !== undefined && filterUserUid.length > 0 && senderUid !== filterUserUid) {
        continue;
      }
      let senderName = senderUid.substring(0, 8);
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
      moments.push({
        canonicalUid: m.canonical_uid ?? '',
        userUid: senderUid,
        thumbnailUrl: m.thumbnail_url ?? '',
        videoUrl: m.video_url ?? '',
        caption: m.caption ?? '',
        createdAtSeconds: m.date?._seconds ?? 0,
        senderName: senderName,
        senderAvatar: senderAvatar
      });
    }

    if ((filterUserUid === undefined || filterUserUid.length === 0) &&
      (syncToken === undefined || syncToken.length === 0) &&
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
      missedMomentsCount: res.result?.missed_moments_count ?? 0,
      syncToken: res.result?.sync_token ?? ''
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

  public async sendChatMessage(receiverUid: string, text: string, momentUid?: string): Promise<void> {
    const session = await this.ensureValidToken();
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return;
    }
    const body: SendChatMessageRequestBody = {
      data: {
        receiver_uid: receiverUid,
        msg: trimmed,
        moment_uid: momentUid ?? '',
        from_memory: false,
        intensity: {
          '@type': 'type.googleapis.com/google.protobuf.Int64Value',
          value: '0'
        }
      }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/sendChatMessageV2`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(body)
    );
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
      const momentUid = fields.moment_uid?.stringValue ?? fields.moment?.stringValue ?? '';

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

      if (text.length > 0) {
        messages.push({
          id: id,
          senderUid: senderUid,
          text: text,
          momentUid: momentUid,
          createdAtMs: createdAtMs
        });
      }
    }
    messages.sort((a: ChatMessage, b: ChatMessage) => a.createdAtMs - b.createdAtMs);
    return messages;
  }

  public async getMessagesWithUser(otherUid: string): Promise<ChatMessage[]> {
    const session = await this.ensureValidToken();
    const pair: string[] = [session.localId, otherUid];
    pair.sort();
    let conversationId = `${pair[0]}_${pair[1]}`;

    // Try deterministic conversation ID first
    try {
      const url = `${FIRESTORE_BASE}/conversations/${encodeURIComponent(conversationId)}/messages?pageSize=50`;
      const res = await this.requestJson<FirestoreMessagesResponse>(
        url,
        http.RequestMethod.GET,
        { 'Authorization': `Bearer ${session.idToken}` }
      );
      const docs = res.documents ?? [];
      if (docs.length > 0) {
        return this.parseFirestoreMessages(docs);
      }
    } catch (_err) {
      // Fallback to checking user's conversations collection
    }

    try {
      const convUrl = `${FIRESTORE_BASE}/users/${session.localId}/conversations?pageSize=100`;
      const convRes = await this.requestJson<FirestoreConversationsResponse>(
        convUrl,
        http.RequestMethod.GET,
        { 'Authorization': `Bearer ${session.idToken}` }
      );
      const convDocs = convRes.documents ?? [];
      for (let i = 0; i < convDocs.length; i++) {
        const cFields = convDocs[i].fields;
        const targetUid = cFields?.other_user?.stringValue ?? cFields?.user?.stringValue ?? '';
        if (targetUid === otherUid) {
          const cid = cFields?.conversation_uid?.stringValue ?? '';
          if (cid.length > 0) {
            conversationId = cid;
            break;
          }
        }
      }
      const msgUrl = `${FIRESTORE_BASE}/conversations/${encodeURIComponent(conversationId)}/messages?pageSize=50`;
      const msgRes = await this.requestJson<FirestoreMessagesResponse>(
        msgUrl,
        http.RequestMethod.GET,
        { 'Authorization': `Bearer ${session.idToken}` }
      );
      return this.parseFirestoreMessages(msgRes.documents ?? []);
    } catch (_err) {
      return [];
    }
  }

  public async uploadAndPostPhotoMoment(imageBytes: ArrayBuffer, options: UploadMomentOptions): Promise<void> {
    const session = await this.ensureValidToken();
    const contentType = options.contentType !== undefined && options.contentType.length > 0
      ? options.contentType
      : 'image/webp';
    const ext = contentType === 'image/jpeg' ? 'jpg' : 'webp';
    const uniqueId = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    const objectPath = `users/${session.localId}/moments/thumbnails/${uniqueId}.${ext}`;
    const uploadUrl = `${FIREBASE_STORAGE_BASE}?uploadType=media&name=${encodeURIComponent(objectPath)}`;

    const httpRequest = http.createHttp();
    let uploadRes: FirebaseStorageUploadResponse;
    try {
      const uploadHeaders: Record<string, string> = {
        'Content-Type': contentType,
        'Authorization': `Bearer ${session.idToken}`
      };
      const response = await httpRequest.request(uploadUrl, {
        method: http.RequestMethod.POST,
        header: uploadHeaders,
        extraData: imageBytes,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      const rawText = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`Upload failed (${response.responseCode}): ${rawText}`);
      }
      uploadRes = JSON.parse(rawText) as FirebaseStorageUploadResponse;
    } finally {
      httpRequest.destroy();
    }

    const downloadTokens = uploadRes.downloadTokens ?? '';
    const firstToken = downloadTokens.split(',')[0];
    const uploadedPath = uploadRes.name ?? objectPath;
    const downloadUrl = `${FIREBASE_STORAGE_BASE}/${encodeURIComponent(uploadedPath)}?alt=media&token=${encodeURIComponent(firstToken)}`;

    const postBody: PostMomentRequestBody = {
      data: {
        thumbnail_url: downloadUrl,
        caption: options.caption.trim(),
        recipients: options.sentToAll ? [] : options.recipients,
        sent_to_all: options.sentToAll,
        overlays: []
      }
    };
    await this.requestJson<GenericApiResponse>(
      `${LOCKET_API_BASE}/postMomentV2`,
      http.RequestMethod.POST,
      this.buildHeaders(session.idToken),
      JSON.stringify(postBody)
    );
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
