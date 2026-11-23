import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SessionManager } from '../services/SessionManager';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'LocketHarmony', '%{public}s', 'Ability onCreate');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    await SessionManager.getInstance().init(this.context);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'LocketHarmony', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }
}
