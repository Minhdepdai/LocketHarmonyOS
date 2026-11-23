import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'NotificationService';

export class NotificationService {
  private static instance: NotificationService | null = null;
  private notificationSequence: number = 1000;

  public static getInstance(): NotificationService {
    if (NotificationService.instance === null) {
      NotificationService.instance = new NotificationService();
    }
    return NotificationService.instance;
  }

  public async requestEnableNotification(context: common.UIAbilityContext): Promise<boolean> {
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
        }
      };

      await notificationManager.publish(request);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Published local notification id=%{public}d for %{public}s', notificationId, title);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to publish notification: %{public}s', msg);
    }
  }
}
