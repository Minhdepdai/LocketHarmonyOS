import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AuthSession, WidgetMomentData } from '../models/LocketModels';
import { CacheService } from './CacheService';

const PREF_NAME = 'locket_session_store';
const KEY_SESSION = 'auth_session_json';
const KEY_WIDGET_MOMENT = 'latest_widget_moment_json';
const KEY_FORM_IDS = 'active_widget_form_ids_json';

export const APP_STORAGE_LOGGED_IN = 'locket_logged_in';
export const APP_STORAGE_UID = 'locket_uid';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'SessionManager';

interface WidgetFormBindingPayload {
  thumbnailUrl: string;
  caption: string;
  senderName: string;
  hasData: boolean;
}

export class SessionManager {
  private static instance: SessionManager | null = null;
  private pref: preferences.Preferences | null = null;
  private currentSession: AuthSession | null = null;
  private latestWidgetMoment: WidgetMomentData | null = null;
  private formIds: string[] = [];

  public static getInstance(): SessionManager {
    if (SessionManager.instance === null) {
      SessionManager.instance = new SessionManager();
    }
    return SessionManager.instance;
  }

  public async init(context: common.Context): Promise<void> {
    if (this.pref === null) {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
    }
    const raw = await this.pref.get(KEY_SESSION, '') as string;
    if (raw.length > 0) {
      try {
        this.currentSession = JSON.parse(raw) as AuthSession;
      } catch (_err) {
        this.currentSession = null;
      }
    }
    await this.loadWidgetMomentFromPref();
    await this.loadFormIdsFromPref();
    this.syncAuthAppStorage();
  }

  public syncAuthAppStorage(): void {
    const loggedIn = this.isLoggedIn();
    const uid = this.currentSession !== null ? this.currentSession.localId : '';
    AppStorage.setOrCreate<boolean>(APP_STORAGE_LOGGED_IN, loggedIn);
    AppStorage.setOrCreate<string>(APP_STORAGE_UID, uid);
  }

  private async ensurePref(context?: common.Context): Promise<void> {
    if (this.pref === null && context !== undefined) {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
      await this.loadFormIdsFromPref();
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

  private async persistFormIds(): Promise<void> {
    if (this.pref !== null) {
      await this.pref.put(KEY_FORM_IDS, JSON.stringify(this.formIds));
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

  public async notifyAllWidgets(data: WidgetMomentData): Promise<void> {
    const ids = this.getFormIds();
    if (ids.length === 0) {
      return;
    }
    const payload: WidgetFormBindingPayload = {
      thumbnailUrl: data.thumbnailUrl,
      caption: data.caption,
      senderName: data.senderName,
      hasData: data.thumbnailUrl.length > 0
    };
    const binding = formBindingData.createFormBindingData(payload);
    for (let i = 0; i < ids.length; i++) {
      const formId = ids[i];
      try {
        await formProvider.updateForm(formId, binding);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to push update to widget %{public}s: %{public}s', formId, msg);
      }
    }
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
    if (this.pref !== null) {
      await this.pref.delete(KEY_SESSION);
      await this.pref.delete(KEY_WIDGET_MOMENT);
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
    try {
      await preferences.removePreferencesFromCache(context, PREF_NAME);
    } catch (_err) {
      // Ignore cache removal failure and proceed with reading
    }
    this.pref = await preferences.getPreferences(context, PREF_NAME);
    await this.loadWidgetMomentFromPref();
    await this.loadFormIdsFromPref();
    return this.latestWidgetMoment;
  }
}
