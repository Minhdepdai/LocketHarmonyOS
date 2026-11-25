import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { ConversationSummary, WidgetMomentData } from '../models/LocketModels';
import { CacheService } from '../services/CacheService';
import { LocketApiClient } from '../services/LocketApiClient';
import { NotificationService } from '../services/NotificationService';
import { SessionManager } from '../services/SessionManager';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'LocketHarmony';
const DEFAULT_SAFE_TOP_VP = 38;
const DEFAULT_SAFE_BOTTOM_VP = 20;

interface WidgetDeepLinkParams {
  source?: string;
  viewMode?: string;
  momentUid?: string;
}

export default class EntryAbility extends UIAbility {
  private isSessionInitialized: boolean = false;
  private pollTimerId: number = -1;
  private isSyncing: boolean = false;
  private readonly POLL_INTERVAL_MS: number = 60000;

  private getDensityPixels(): number {
    try {
      const density = display.getDefaultDisplaySync().densityPixels;
      if (density > 0) {
        return density;
      }
    } catch (_err) {
      // Fallback density
    }
    return 3;
  }

  private updateSafeAreaInsets(mainWindow: window.Window): void {
    try {
      const density = this.getDensityPixels();
      const sysArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topVp = sysArea.topRect.height > 0
        ? Math.ceil(sysArea.topRect.height / density)
        : DEFAULT_SAFE_TOP_VP;
      const bottomVp = navArea.bottomRect.height > 0
        ? Math.ceil(navArea.bottomRect.height / density)
        : DEFAULT_SAFE_BOTTOM_VP;
      AppStorage.setOrCreate<number>('safe_top_vp', topVp);
      AppStorage.setOrCreate<number>('safe_bottom_vp', bottomVp);
    } catch (_err) {
      AppStorage.setOrCreate<number>('safe_top_vp', DEFAULT_SAFE_TOP_VP);
      AppStorage.setOrCreate<number>('safe_bottom_vp', DEFAULT_SAFE_BOTTOM_VP);
    }
  }

  private async configureImmersiveWindow(windowStage: window.WindowStage): Promise<void> {
    AppStorage.setOrCreate<number>('safe_top_vp', DEFAULT_SAFE_TOP_VP);
    AppStorage.setOrCreate<number>('safe_bottom_vp', DEFAULT_SAFE_BOTTOM_VP);
    try {
      const mainWindow = windowStage.getMainWindowSync();
      await mainWindow.setWindowLayoutFullScreen(true);
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#FFFFFF'
      });
      this.updateSafeAreaInsets(mainWindow);
      mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
        const density = this.getDensityPixels();
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          const topVp = data.area.topRect.height > 0
            ? Math.ceil(data.area.topRect.height / density)
            : DEFAULT_SAFE_TOP_VP;
          AppStorage.setOrCreate<number>('safe_top_vp', topVp);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          const bottomVp = data.area.bottomRect.height > 0
            ? Math.ceil(data.area.bottomRect.height / density)
            : DEFAULT_SAFE_BOTTOM_VP;
          AppStorage.setOrCreate<number>('safe_bottom_vp', bottomVp);
        }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Immersive window setup fallback: %{public}s', msg);
    }
  }

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

  private startBackgroundPoll(): void {
    this.stopBackgroundPoll();
    this.pollTimerId = setInterval(() => {
      this.refreshOnForeground();
    }, this.POLL_INTERVAL_MS);
  }

  private stopBackgroundPoll(): void {
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  private async refreshOnForeground(): Promise<void> {
    if (this.isSyncing) {
      return;
    }
    this.isSyncing = true;
    try {
      const sessionMgr = SessionManager.getInstance();
      if (!this.isSessionInitialized) {
        await sessionMgr.init(this.context);
        await CacheService.getInstance().init(this.context);
        this.isSessionInitialized = true;
      }
      sessionMgr.syncAuthAppStorage();

      if (!sessionMgr.isLoggedIn()) {
        return;
      }

      const api = LocketApiClient.getInstance();
      await api.ensureValidToken();

      const feed = await api.getLatestMoments();
      let missedCount = 0;
      try {
        missedCount = await api.fetchMissedMomentsCount();
      } catch (countErr) {
        const countMsg = countErr instanceof Error ? countErr.message : String(countErr);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Missed moments count fetch skipped: %{public}s', countMsg);
      }

      if (feed.moments.length > 0) {
        await CacheService.getInstance().saveMoments(feed.moments);

        const latest = feed.moments[0];
        const widgetData: WidgetMomentData = {
          canonicalUid: latest.canonicalUid,
          thumbnailUrl: latest.thumbnailUrl,
          caption: latest.caption,
          senderName: latest.senderName,
          createdAtSeconds: latest.createdAtSeconds,
          unseenCount: missedCount
        };
        await sessionMgr.saveLatestWidgetMoment(widgetData);
        await sessionMgr.notifyAllWidgets(widgetData, this.context, missedCount);

        const lastNotifiedId = sessionMgr.getLastNotifiedMomentId();
        const myUid = sessionMgr.getSession()?.localId ?? '';
        if (latest.canonicalUid.length > 0 && latest.canonicalUid !== lastNotifiedId) {
          if (lastNotifiedId.length > 0 && latest.userUid !== myUid) {
            await NotificationService.getInstance().publishNewMomentNotification(
              latest.senderName,
              latest.caption
            );
          }
          await sessionMgr.setLastNotifiedMomentId(latest.canonicalUid);
        }
      }

      try {
        const convs = await api.getConversations();
        if (convs.length > 0) {
          await CacheService.getInstance().saveConversations(convs);
          let newestConv: ConversationSummary | null = null;
          let maxUpdatedMs = 0;
          for (let i = 0; i < convs.length; i++) {
            const conv = convs[i];
            if (conv.lastUpdatedMs > maxUpdatedMs) {
              maxUpdatedMs = conv.lastUpdatedMs;
              newestConv = conv;
            }
          }
          const lastMsgTs = sessionMgr.getLastNotifiedMsgTs();
          if (newestConv !== null && newestConv.lastUpdatedMs > lastMsgTs) {
            if (lastMsgTs > 0 && newestConv.lastMessage.length > 0) {
              await NotificationService.getInstance().publishNewMessageNotification(
                newestConv.friendName,
                newestConv.lastMessage,
                newestConv.friendUid
              );
            }
            await sessionMgr.setLastNotifiedMsgTs(newestConv.lastUpdatedMs);
          }
        }
      } catch (msgErr) {
        const msgText = msgErr instanceof Error ? msgErr.message : String(msgErr);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Conversation poll skipped: %{public}s', msgText);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Foreground refresh skipped: %{public}s', msg);
    } finally {
      this.isSyncing = false;
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
    await this.configureImmersiveWindow(windowStage);
    await SessionManager.getInstance().init(this.context);
    await CacheService.getInstance().init(this.context);
    this.isSessionInitialized = true;
    SessionManager.getInstance().syncAuthAppStorage();

    NotificationService.getInstance().setBundleName(this.context.abilityInfo.bundleName);
    NotificationService.getInstance().requestEnableNotification(this.context);
    NotificationService.getInstance().initPushKit();

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
    this.startBackgroundPoll();
  }

  onBackground(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onBackground');
    this.stopBackgroundPoll();
  }

  onDestroy(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onDestroy');
    this.stopBackgroundPoll();
  }
}
