import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { WidgetMomentData } from '../models/LocketModels';
import { LocketApiClient } from '../services/LocketApiClient';
import { NotificationService } from '../services/NotificationService';
import { SessionManager } from '../services/SessionManager';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'LocketHarmony';

interface WidgetDeepLinkParams {
  source?: string;
  viewMode?: string;
  momentUid?: string;
}

export default class EntryAbility extends UIAbility {
  private isSessionInitialized: boolean = false;

  private handleDeepLinkWant(want: Want): void {
    const params = want.parameters;
    if (params === undefined) {
      return;
    }
    const rawParams = params['params'];
    let targetViewMode = '';
    if (typeof rawParams === 'string' && rawParams.length > 0) {
      try {
        const parsed = JSON.parse(rawParams) as WidgetDeepLinkParams;
        if (parsed.viewMode !== undefined && parsed.viewMode.length > 0) {
          targetViewMode = parsed.viewMode;
        } else if (parsed.source === 'widget') {
          targetViewMode = 'feed';
        }
      } catch (_err) {
        // Ignore malformed deep-link JSON
      }
    }
    const directMode = params['viewMode'];
    if (typeof directMode === 'string' && directMode.length > 0) {
      targetViewMode = directMode;
    }
    const directSource = params['source'];
    if (targetViewMode.length === 0 && directSource === 'widget') {
      targetViewMode = 'feed';
    }

    if (targetViewMode.length > 0) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Widget deep-link detected -> viewMode=%{public}s', targetViewMode);
      AppStorage.setOrCreate<string>('locket_pending_view_mode', targetViewMode);
      AppStorage.setOrCreate<number>('locket_widget_tap_ts', Date.now());
    }
  }

  private async refreshOnForeground(): Promise<void> {
    try {
      const sessionMgr = SessionManager.getInstance();
      if (!this.isSessionInitialized) {
        await sessionMgr.init(this.context);
        this.isSessionInitialized = true;
      }
      sessionMgr.syncAuthAppStorage();

      if (!sessionMgr.isLoggedIn()) {
        return;
      }

      const api = LocketApiClient.getInstance();
      await api.ensureValidToken();

      const previousCached = sessionMgr.getLatestWidgetMoment();
      const previousUid = previousCached !== null ? previousCached.canonicalUid : '';

      const feed = await api.getLatestMoments();
      if (feed.moments.length === 0) {
        return;
      }

      const latest = feed.moments[0];
      if (latest.canonicalUid.length > 0 && latest.canonicalUid !== previousUid) {
        const widgetData: WidgetMomentData = {
          canonicalUid: latest.canonicalUid,
          thumbnailUrl: latest.thumbnailUrl,
          caption: latest.caption,
          senderName: latest.senderName,
          createdAtSeconds: latest.createdAtSeconds
        };
        await sessionMgr.saveLatestWidgetMoment(widgetData);
        await sessionMgr.notifyAllWidgets(widgetData);

        if (previousUid.length > 0) {
          await NotificationService.getInstance().publishNewMomentNotification(
            latest.senderName,
            latest.caption
          );
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Foreground refresh skipped: %{public}s', msg);
    }
  }

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onCreate');
    this.handleDeepLinkWant(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onNewWant');
    this.handleDeepLinkWant(want);
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    await SessionManager.getInstance().init(this.context);
    this.isSessionInitialized = true;
    SessionManager.getInstance().syncAuthAppStorage();

    NotificationService.getInstance().requestEnableNotification(this.context);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }

  onForeground(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onForeground');
    this.refreshOnForeground();
  }

  onBackground(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onBackground');
  }
}
