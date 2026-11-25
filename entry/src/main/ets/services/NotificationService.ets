import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { pushService } from '@kit.PushKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'NotificationService';

export class NotificationService {
  private static instance: NotificationService | null = null;
  private notificationSequence: number = 1000;
  private bundleName: string = 'com.locket.harmony';

  public static getInstance(): NotificationService {
    if (NotificationService.instance === null) {
      NotificationService.instance = new NotificationService();
    }
    return NotificationService.instance;
  }

  public setBundleName(name: string): void {
    if (name.length > 0) {
      this.bundleName = name;
    }
  }

  private async createOpenAppWantAgent(viewMode: string, friendUid: string = ''): Promise<WantAgent | undefined> {
    try {
      const params: Record<string, Object> = {
        'source': 'notification',
        'viewMode': viewMode,
        'friendUid': friendUid
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: this.bundleName,
            abilityName: 'EntryAbility',
            parameters: params
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: this.notificationSequence,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to create notification WantAgent: %{public}s', msg);
      return undefined;
    }
  }

  public async requestEnableNotification(context: common.UIAbilityContext): Promise<boolean> {
    if (context.abilityInfo.bundleName.length > 0) {
      this.bundleName = context.abilityInfo.bundleName;
    }
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      await notificationManager.requestEnableNotification(context);
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Notification permission request skipped or denied: %{public}s', msg);
      return false;
    }
  }

  public async initPushKit(): Promise<string> {
    try {
      const token: string = await pushService.getToken();
      hilog.info(LOG_DOMAIN, 'LocketPush', 'PushKit token acquired: %{public}s', token);
      return token;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, 'LocketPush', 'PushKit unavailable or AGC not configured: %{public}s', msg);
      return '';
    }
  }

  public async publishNewMomentNotification(senderName: string, caption: string): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Notifications are disabled; skipping local notification');
        return;
      }

      const trimmedSender = senderName.trim();
      const trimmedCaption = caption.trim();
      const title = trimmedSender.length > 0
        ? `${trimmedSender} vừa gửi một Locket`
        : 'Khoảnh khắc Locket mới';
      const bodyText = trimmedCaption.length > 0
        ? trimmedCaption
        : 'Chạm để xem ảnh mới nhất từ bạn bè';

      this.notificationSequence += 1;
      const notificationId = this.notificationSequence;
      const agent = await this.createOpenAppWantAgent('feed');

      const request: notificationManager.NotificationRequest = {
        id: notificationId,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: bodyText,
            additionalText: 'Locket'
          }
        },
        wantAgent: agent
      };

      await notificationManager.publish(request);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Published local notification id=%{public}d for %{public}s', notificationId, title);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to publish notification: %{public}s', msg);
    }
  }

  public async publishNewMessageNotification(senderName: string, bodyText: string, friendUid: string): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Notifications are disabled; skipping message notification');
        return;
      }

      const trimmedSender = senderName.trim();
      const trimmedBody = bodyText.trim();
      const title = trimmedSender.length > 0 ? trimmedSender : 'Tin nhắn Locket mới';
      const text = trimmedBody.length > 0 ? trimmedBody : 'Đã gửi một tin nhắn mới';

      this.notificationSequence += 1;
      const notificationId = this.notificationSequence;
      const agent = await this.createOpenAppWantAgent('messages', friendUid);

      const request: notificationManager.NotificationRequest = {
        id: notificationId,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
            additionalText: 'Locket'
          }
        },
        wantAgent: agent
      };

      await notificationManager.publish(request);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Published message notification id=%{public}d for %{public}s', notificationId, title);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to publish message notification: %{public}s', msg);
    }
  }
}
