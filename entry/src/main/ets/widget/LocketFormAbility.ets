import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidgetMomentData } from '../models/LocketModels';
import { LocketApiClient } from '../services/LocketApiClient';
import { SessionManager, WidgetFormBindingPayload } from '../services/SessionManager';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'LocketFormAbility';

export default class LocketFormAbility extends FormExtensionAbility {
  private buildInitialPayload(moment: WidgetMomentData | null): WidgetFormBindingPayload {
    if (moment !== null && moment.thumbnailUrl.length > 0) {
      return {
        imgName: '',
        hasImage: false,
        caption: moment.caption,
        senderName: moment.senderName,
        hasData: true,
        unseenCount: Math.max(0, moment.unseenCount ?? 0)
      };
    }
    return {
      imgName: '',
      hasImage: false,
      caption: '',
      senderName: '',
      hasData: false,
      unseenCount: 0
    };
  }

  private async registerAndRefreshForm(formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      await SessionManager.getInstance().addFormId(formId, this.context);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to register formId %{public}s: %{public}s', formId, msg);
    }
    await this.refreshFormFromLiveOrStorage(formId);
  }

  private async refreshFormFromLiveOrStorage(formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      const sessionMgr = SessionManager.getInstance();
      await sessionMgr.refreshLatestWidgetMoment(this.context);
      let moment: WidgetMomentData | null = sessionMgr.getLatestWidgetMoment();
      let unseenCount: number = moment?.unseenCount ?? 0;

      if (sessionMgr.isLoggedIn()) {
        try {
          const api = LocketApiClient.getInstance();
          await api.ensureValidToken();
          const feed = await api.getLatestMoments();
          try {
            unseenCount = await api.fetchMissedMomentsCount();
          } catch (countErr) {
            const countMsg = countErr instanceof Error ? countErr.message : String(countErr);
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Widget unseen count fetch skipped: %{public}s', countMsg);
          }

          if (feed.moments.length > 0) {
            const latest = feed.moments[0];
            moment = {
              canonicalUid: latest.canonicalUid,
              thumbnailUrl: latest.thumbnailUrl,
              caption: latest.caption,
              senderName: latest.senderName,
              createdAtSeconds: latest.createdAtSeconds,
              unseenCount: unseenCount
            };
            await sessionMgr.saveLatestWidgetMoment(moment);
          }
        } catch (liveErr) {
          const liveMsg = liveErr instanceof Error ? liveErr.message : String(liveErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Widget live refresh failed, falling back to cache: %{public}s', liveMsg);
        }
      }

      await sessionMgr.pushWidgetUpdateToForms([formId], moment, this.context, unseenCount);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to update widget form %{public}s: %{public}s', formId, msg);
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const cached = SessionManager.getInstance().getLatestWidgetMoment();
    const initialData = this.buildInitialPayload(cached);

    const formIdParam = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    if (typeof formIdParam === 'string' && formIdParam.length > 0) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'onAddForm registering formId=%{public}s', formIdParam);
      this.registerAndRefreshForm(formIdParam);
    }

    return formBindingData.createFormBindingData(initialData);
  }

  onUpdateForm(formId: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onUpdateForm: %{public}s', formId);
    this.registerAndRefreshForm(formId);
  }

  onRemoveForm(formId: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onRemoveForm: %{public}s', formId);
    SessionManager.getInstance().removeFormId(formId, this.context).catch((err: Error) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to remove formId %{public}s: %{public}s', formId, err.message);
    });
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
