import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AuthSession, WidgetMomentData } from '../models/LocketModels';
import { CacheService } from './CacheService';

const PREF_NAME = 'locket_session_store';
const KEY_SESSION = 'auth_session_json';
const KEY_WIDGET_MOMENT = 'latest_widget_moment_json';
const KEY_FORM_IDS = 'active_widget_form_ids_json';
const KEY_LAST_NOTIFIED_MOMENT_ID = 'last_notified_moment_id';
const KEY_LAST_NOTIFIED_MSG_TS = 'last_notified_msg_ts';

export const APP_STORAGE_LOGGED_IN = 'locket_logged_in';
export const APP_STORAGE_UID = 'locket_uid';
export const WIDGET_IMAGE_KEY = 'locket_widget_img';

const WIDGET_IMAGE_FILENAME = 'locket_widget_latest.jpg';
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'SessionManager';

export interface WidgetFormBindingPayload {
  imgName: string;
  hasImage: boolean;
  caption: string;
  senderName: string;
  hasData: boolean;
  unseenCount: number;
  formImages?: Record<string, number>;
}

export class SessionManager {
  private static instance: SessionManager | null = null;
  private pref: preferences.Preferences | null = null;
  private appContext: common.Context | null = null;
  private currentSession: AuthSession | null = null;
  private latestWidgetMoment: WidgetMomentData | null = null;
  private formIds: string[] = [];
  private lastNotifiedMomentId: string = '';
  private lastNotifiedMsgTs: number = 0;

  public static getInstance(): SessionManager {
    if (SessionManager.instance === null) {
      SessionManager.instance = new SessionManager();
    }
    return SessionManager.instance;
  }

  public async init(context: common.Context): Promise<void> {
    this.appContext = context;
    if (this.pref === null) {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
    }
    await this.loadSessionFromPref();
    await this.loadWidgetMomentFromPref();
    await this.loadFormIdsFromPref();
    await this.loadNotificationStateFromPref();
    this.syncAuthAppStorage();
  }

  public syncAuthAppStorage(): void {
    const loggedIn = this.isLoggedIn();
    const uid = this.currentSession !== null ? this.currentSession.localId : '';
    AppStorage.setOrCreate<boolean>(APP_STORAGE_LOGGED_IN, loggedIn);
    AppStorage.setOrCreate<string>(APP_STORAGE_UID, uid);
  }

  private async ensurePref(context?: common.Context): Promise<void> {
    if (context !== undefined) {
      this.appContext = context;
    }
    if (this.pref === null && this.appContext !== null) {
      this.pref = await preferences.getPreferences(this.appContext, PREF_NAME);
      await this.loadSessionFromPref();
      await this.loadFormIdsFromPref();
      await this.loadNotificationStateFromPref();
    }
  }

  private async loadSessionFromPref(): Promise<void> {
    if (this.pref === null) {
      return;
    }
    const raw = await this.pref.get(KEY_SESSION, '') as string;
    if (raw.length > 0) {
      try {
        this.currentSession = JSON.parse(raw) as AuthSession;
      } catch (_err) {
        this.currentSession = null;
      }
    } else {
      this.currentSession = null;
    }
  }

  private async loadWidgetMomentFromPref(): Promise<void> {
    if (this.pref === null) {
      return;
    }
    const rawWidget = await this.pref.get(KEY_WIDGET_MOMENT, '') as string;
    if (rawWidget.length > 0) {
      try {
        this.latestWidgetMoment = JSON.parse(rawWidget) as WidgetMomentData;
      } catch (_err) {
        this.latestWidgetMoment = null;
      }
    } else {
      this.latestWidgetMoment = null;
    }
  }

  private async loadFormIdsFromPref(): Promise<void> {
    if (this.pref === null) {
      return;
    }
    const rawIds = await this.pref.get(KEY_FORM_IDS, '') as string;
    if (rawIds.length > 0) {
      try {
        const parsed = JSON.parse(rawIds) as string[];
        if (Array.isArray(parsed)) {
          this.formIds = parsed.filter((id: string) => typeof id === 'string' && id.length > 0);
        } else {
          this.formIds = [];
        }
      } catch (_err) {
        this.formIds = [];
      }
    } else {
      this.formIds = [];
    }
  }

  private async loadNotificationStateFromPref(): Promise<void> {
    if (this.pref === null) {
      return;
    }
    this.lastNotifiedMomentId = await this.pref.get(KEY_LAST_NOTIFIED_MOMENT_ID, '') as string;
    const rawMsgTs = await this.pref.get(KEY_LAST_NOTIFIED_MSG_TS, 0) as number;
    this.lastNotifiedMsgTs = typeof rawMsgTs === 'number' && !Number.isNaN(rawMsgTs) ? rawMsgTs : 0;
  }

  private async persistFormIds(): Promise<void> {
    if (this.pref !== null) {
      await this.pref.put(KEY_FORM_IDS, JSON.stringify(this.formIds));
      await this.pref.flush();
    }
  }

  public getLastNotifiedMomentId(): string {
    return this.lastNotifiedMomentId;
  }

  public async setLastNotifiedMomentId(momentId: string): Promise<void> {
    this.lastNotifiedMomentId = momentId;
    if (this.pref !== null) {
      await this.pref.put(KEY_LAST_NOTIFIED_MOMENT_ID, momentId);
      await this.pref.flush();
    }
  }

  public getLastNotifiedMsgTs(): number {
    return this.lastNotifiedMsgTs;
  }

  public async setLastNotifiedMsgTs(timestampMs: number): Promise<void> {
    this.lastNotifiedMsgTs = timestampMs;
    if (this.pref !== null) {
      await this.pref.put(KEY_LAST_NOTIFIED_MSG_TS, timestampMs);
      await this.pref.flush();
    }
  }

  public async addFormId(formId: string, context?: common.Context): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    await this.ensurePref(context);
    if (!this.formIds.includes(formId)) {
      this.formIds = [...this.formIds, formId];
      await this.persistFormIds();
    }
  }

  public async removeFormId(formId: string, context?: common.Context): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    await this.ensurePref(context);
    if (this.formIds.includes(formId)) {
      this.formIds = this.formIds.filter((id: string) => id !== formId);
      await this.persistFormIds();
    }
  }

  public getFormIds(): string[] {
    return [...this.formIds];
  }

  public async downloadWidgetThumbnail(context: common.Context, imageUrl: string): Promise<string> {
    if (imageUrl.length === 0) {
      return '';
    }
    const targetPath = `${context.cacheDir}/${WIDGET_IMAGE_FILENAME}`;
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(imageUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      if (response.responseCode >= 200 && response.responseCode < 300 && response.result instanceof ArrayBuffer) {
        const buffer = response.result as ArrayBuffer;
        if (buffer.byteLength > 0) {
          let outFile: fileIo.File | null = null;
          try {
            outFile = fileIo.openSync(
              targetPath,
              fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
            );
            fileIo.writeSync(outFile.fd, buffer);
          } finally {
            if (outFile !== null) {
              try {
                fileIo.closeSync(outFile);
              } catch (_closeErr) {
                // Ignore close error
              }
            }
          }
          return targetPath;
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Widget thumbnail download failed: %{public}s', msg);
    } finally {
      httpRequest.destroy();
    }

    try {
      if (fileIo.accessSync(targetPath)) {
        return targetPath;
      }
    } catch (_accessErr) {
      // Cached file does not exist
    }
    return '';
  }

  public async pushWidgetUpdateToForms(
    formIds: string[],
    data: WidgetMomentData | null,
    context: common.Context,
    unseenCount?: number
  ): Promise<void> {
    if (formIds.length === 0) {
      return;
    }
    const resolvedCount = unseenCount !== undefined ? unseenCount : (data?.unseenCount ?? 0);
    let localPath = '';
    if (data !== null && data.thumbnailUrl.length > 0) {
      localPath = await this.downloadWidgetThumbnail(context, data.thumbnailUrl);
    }

    let readFile: fileIo.File | null = null;
    try {
      let formImagesMap: Record<string, number> | undefined = undefined;
      if (localPath.length > 0) {
        try {
          readFile = fileIo.openSync(localPath, fileIo.OpenMode.READ_ONLY);
          formImagesMap = {};
          formImagesMap[WIDGET_IMAGE_KEY] = readFile.fd;
        } catch (openErr) {
          const msg = openErr instanceof Error ? openErr.message : String(openErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to open widget cached image: %{public}s', msg);
          readFile = null;
          formImagesMap = undefined;
        }
      }

      const payload: WidgetFormBindingPayload = {
        imgName: WIDGET_IMAGE_KEY,
        hasImage: readFile !== null,
        caption: data !== null ? data.caption : '',
        senderName: data !== null ? data.senderName : '',
        hasData: data !== null && data.thumbnailUrl.length > 0,
        unseenCount: Math.max(0, resolvedCount),
        formImages: formImagesMap
      };
      const binding = formBindingData.createFormBindingData(payload);

      for (let i = 0; i < formIds.length; i++) {
        const formId = formIds[i];
        try {
          await formProvider.updateForm(formId, binding);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to push update to widget %{public}s: %{public}s', formId, msg);
        }
      }
    } finally {
      if (readFile !== null) {
        try {
          fileIo.closeSync(readFile);
        } catch (_closeErr) {
          // Ignore close error
        }
      }
    }
  }

  public async notifyAllWidgets(
    data: WidgetMomentData,
    context?: common.Context,
    unseenCount?: number
  ): Promise<void> {
    const ids = this.getFormIds();
    const resolvedContext = context !== undefined ? context : this.appContext;
    if (ids.length === 0 || resolvedContext === null) {
      return;
    }
    await this.pushWidgetUpdateToForms(ids, data, resolvedContext, unseenCount);
  }

  public getSession(): AuthSession | null {
    return this.currentSession;
  }

  public isLoggedIn(): boolean {
    return this.currentSession !== null && this.currentSession.idToken.length > 0;
  }

  public isTokenExpiringSoon(): boolean {
    if (this.currentSession === null) {
      return true;
    }
    const bufferMs = 60 * 1000;
    return Date.now() + bufferMs >= this.currentSession.expiresAt;
  }

  public async saveSession(session: AuthSession): Promise<void> {
    this.currentSession = session;
    if (this.pref !== null) {
      await this.pref.put(KEY_SESSION, JSON.stringify(session));
      await this.pref.flush();
    }
    this.syncAuthAppStorage();
  }

  public async clearSession(): Promise<void> {
    this.currentSession = null;
    this.latestWidgetMoment = null;
    this.lastNotifiedMomentId = '';
    this.lastNotifiedMsgTs = 0;
    if (this.pref !== null) {
      await this.pref.delete(KEY_SESSION);
      await this.pref.delete(KEY_WIDGET_MOMENT);
      await this.pref.delete(KEY_LAST_NOTIFIED_MOMENT_ID);
      await this.pref.delete(KEY_LAST_NOTIFIED_MSG_TS);
      await this.pref.flush();
    }
    await CacheService.getInstance().clearAll();
    this.syncAuthAppStorage();
  }

  public async saveLatestWidgetMoment(data: WidgetMomentData): Promise<void> {
    this.latestWidgetMoment = data;
    if (this.pref !== null) {
      await this.pref.put(KEY_WIDGET_MOMENT, JSON.stringify(data));
      await this.pref.flush();
    }
  }

  public getLatestWidgetMoment(): WidgetMomentData | null {
    return this.latestWidgetMoment;
  }

  public async refreshLatestWidgetMoment(context: common.Context): Promise<WidgetMomentData | null> {
    this.appContext = context;
    try {
      await preferences.removePreferencesFromCache(context, PREF_NAME);
    } catch (_err) {
      // Ignore cache removal failure and proceed with reading
    }
    this.pref = await preferences.getPreferences(context, PREF_NAME);
    await this.loadSessionFromPref();
    await this.loadWidgetMomentFromPref();
    await this.loadFormIdsFromPref();
    await this.loadNotificationStateFromPref();
    return this.latestWidgetMoment;
  }
}
