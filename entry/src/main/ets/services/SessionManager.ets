import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AuthSession, WidgetMomentData } from '../models/LocketModels';

const PREF_NAME = 'locket_session_store';
const KEY_SESSION = 'auth_session_json';
const KEY_WIDGET_MOMENT = 'latest_widget_moment_json';

export class SessionManager {
  private static instance: SessionManager | null = null;
  private pref: preferences.Preferences | null = null;
  private currentSession: AuthSession | null = null;
  private latestWidgetMoment: WidgetMomentData | null = null;

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
  }

  public async clearSession(): Promise<void> {
    this.currentSession = null;
    this.latestWidgetMoment = null;
    if (this.pref !== null) {
      await this.pref.delete(KEY_SESSION);
      await this.pref.delete(KEY_WIDGET_MOMENT);
      await this.pref.flush();
    }
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
    return this.latestWidgetMoment;
  }
}
