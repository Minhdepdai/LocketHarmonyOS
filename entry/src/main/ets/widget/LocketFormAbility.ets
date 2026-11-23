import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidgetMomentData } from '../models/LocketModels';
import { SessionManager } from '../services/SessionManager';

interface WidgetFormData {
  thumbnailUrl: string;
  caption: string;
  senderName: string;
  hasData: boolean;
}

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'LocketFormAbility';

export default class LocketFormAbility extends FormExtensionAbility {
  private buildFormData(moment: WidgetMomentData | null): WidgetFormData {
    if (moment !== null && moment.thumbnailUrl.length > 0) {
      return {
        thumbnailUrl: moment.thumbnailUrl,
        caption: moment.caption,
        senderName: moment.senderName,
        hasData: true
      };
    }
    return {
      thumbnailUrl: '',
      caption: '',
      senderName: '',
      hasData: false
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
    await this.refreshFormFromStorage(formId);
  }

  private async refreshFormFromStorage(formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      const moment = await SessionManager.getInstance().refreshLatestWidgetMoment(this.context);
      const data = this.buildFormData(moment);
      const binding = formBindingData.createFormBindingData(data);
      await formProvider.updateForm(formId, binding);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to update widget form %{public}s: %{public}s', formId, msg);
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const cached = SessionManager.getInstance().getLatestWidgetMoment();
    const initialData = this.buildFormData(cached);

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
