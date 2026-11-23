import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'ShareService';

export class ShareService {
  private static knockShareCallback: ((sharableTarget: harmonyShare.SharableTarget) => void) | null = null;

  public static buildInviteUrl(username: string): string {
    const trimmed = username.trim();
    return trimmed.length > 0 ? 'https://locket.cam/' + trimmed : 'https://locket.cam';
  }

  private static buildSharedData(username: string, displayName: string): systemShare.SharedData {
    const url = ShareService.buildInviteUrl(username);
    const trimmedName = displayName.trim();
    const description = trimmedName.length > 0
      ? `${trimmedName} mời bạn kết bạn trên Locket: ${url}`
      : `Tham gia Locket cùng mình nhé: ${url}`;

    return new systemShare.SharedData({
      utd: utd.UniformDataType.HYPERLINK,
      content: url,
      title: 'Mời bạn tham gia Locket',
      description: description
    });
  }

  public static async copyText(text: string): Promise<void> {
    const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    await systemPasteboard.setData(pasteData);
  }

  public static async copyInviteLink(username: string): Promise<string> {
    const url = ShareService.buildInviteUrl(username);
    await ShareService.copyText(url);
    return url;
  }

  public static async shareViaSystemSheet(
    context: common.UIAbilityContext,
    username: string,
    displayName: string
  ): Promise<void> {
    const sharedData = ShareService.buildSharedData(username, displayName);
    const controller = new systemShare.ShareController(sharedData);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  public static async shareMomentViaSystemSheet(
    context: common.UIAbilityContext,
    thumbnailUrl: string,
    senderName: string,
    caption: string
  ): Promise<void> {
    const cleanName = senderName.trim();
    const cleanCaption = caption.trim();
    const title = cleanName.length > 0 ? `Khoảnh khắc từ ${cleanName}` : 'Khoảnh khắc Locket';
    const description = cleanCaption.length > 0 ? cleanCaption : 'Xem khoảnh khắc trên Locket';
    const sharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.HYPERLINK,
      content: thumbnailUrl,
      title: title,
      description: description
    });
    const controller = new systemShare.ShareController(sharedData);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  public static enableKnockShare(username: string, displayName: string): boolean {
    if (ShareService.knockShareCallback !== null) {
      ShareService.disableKnockShare();
    }

    const callback: (sharableTarget: harmonyShare.SharableTarget) => void =
      (sharableTarget: harmonyShare.SharableTarget): void => {
        try {
          const sharedData = ShareService.buildSharedData(username, displayName);
          sharableTarget.share(sharedData);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Knock Share transfer failed: %{public}s', msg);
        }
      };

    try {
      harmonyShare.on('knockShare', callback);
      ShareService.knockShareCallback = callback;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Knock Share enabled for %{public}s', ShareService.buildInviteUrl(username));
      return true;
    } catch (err) {
      ShareService.knockShareCallback = null;
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Knock Share unavailable on this device: %{public}s', msg);
      return false;
    }
  }

  public static disableKnockShare(): void {
    if (ShareService.knockShareCallback === null) {
      return;
    }

    const callback = ShareService.knockShareCallback;
    ShareService.knockShareCallback = null;
    try {
      harmonyShare.off('knockShare', callback);
      hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Knock Share disabled');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to disable Knock Share: %{public}s', msg);
    }
  }
}
