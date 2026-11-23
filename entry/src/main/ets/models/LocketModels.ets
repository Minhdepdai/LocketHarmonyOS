export interface AuthSession {
  localId: string;
  email: string;
  displayName: string;
  idToken: string;
  refreshToken: string;
  expiresAt: number; // Unix timestamp in milliseconds
}

export interface UserProfile {
  uid: string;
  firstName: string;
  lastName: string;
  username: string;
  profilePictureUrl: string;
}

export interface MomentTimestamp {
  _seconds: number;
  _nanoseconds: number;
}

export interface MomentItem {
  canonicalUid: string;
  userUid: string;
  thumbnailUrl: string;
  videoUrl: string;
  caption: string;
  createdAtSeconds: number;
  senderName: string;
  senderAvatar: string;
}

export interface MomentsFeedResult {
  moments: MomentItem[];
  missedMomentsCount: number;
  syncToken: string;
}

export interface FriendItem {
  uid: string;
  firstName: string;
  lastName: string;
  username: string;
  profilePictureUrl: string;
}

export interface MomentReaction {
  momentUid: string;
  senderUid: string;
  emoji: string;
  createdAtSeconds: number;
}

export interface ChatMessage {
  id: string;
  senderUid: string;
  text: string;
  momentUid: string;
  createdAtMs: number;
  thumbnailUrl?: string;
}

export interface UploadMomentOptions {
  caption: string;
  recipients: string[];
  sentToAll: boolean;
  contentType?: string;
}

export interface WidgetMomentData {
  canonicalUid: string;
  thumbnailUrl: string;
  caption: string;
  senderName: string;
  createdAtSeconds: number;
}

export function getDisplayName(profile: UserProfile | FriendItem): string {
  const fullName = `${profile.firstName} ${profile.lastName}`.trim();
  if (fullName.length > 0) {
    return fullName;
  }
  if (profile.username.length > 0) {
    return profile.username;
  }
  return profile.uid;
}
