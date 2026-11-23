import { router } from '@kit.ArkUI';
import { SessionManager } from '../services/SessionManager';

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    const loggedIn = SessionManager.getInstance().isLoggedIn();
    const targetUrl = loggedIn ? 'pages/HomePage' : 'pages/LoginPage';
    setTimeout(() => {
      router.replaceUrl({ url: targetUrl });
    }, 150);
  }

  build() {
    Column() {
      Text('Locket')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFB800')
      Text('HarmonyOS Edition')
        .fontSize(14)
        .fontColor('#8E8E93')
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#000000')
  }
}
