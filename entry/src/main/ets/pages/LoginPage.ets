import { promptAction, router } from '@kit.ArkUI';
import { LocketApiClient } from '../services/LocketApiClient';

const PHONE_DOT_ROWS: number[] = [0, 1, 2];
const PHONE_DOT_COLS: number[] = [0, 1, 2, 3];

@Entry
@Component
struct LoginPage {
  @State step: number = 0;
  @State email: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';

  private async handleLogin(): Promise<void> {
    if (this.email.trim().length === 0 || this.password.length === 0) {
      this.errorMessage = 'Vui lòng nhập đầy đủ email và mật khẩu.';
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      await LocketApiClient.getInstance().login(this.email, this.password);
      router.replaceUrl({ url: 'pages/HomePage' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Đăng nhập thất bại';
      this.errorMessage = msg;
    } finally {
      this.isLoading = false;
    }
  }

  @Builder
  private buildPhoneIllustration() {
    Column() {
      // Top dynamic island notch
      Row()
        .width(50)
        .height(10)
        .borderRadius(5)
        .backgroundColor('#000000')
        .margin({ top: 12, bottom: 18 })

      // Top widget row: 2x2 golden-bordered widget + 2x2 icon dots
      Row({ space: 10 }) {
        // 2x2 Golden Locket Widget
        Column() {
          Text('💛')
            .fontSize(26)
          Text('Locket')
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFB800')
            .margin({ top: 4 })
        }
        .width(72)
        .height(72)
        .borderRadius(18)
        .backgroundColor('#262628')
        .border({ width: 2, color: '#FFB800' })
        .justifyContent(FlexAlign.Center)

        // 2x2 App Icon Dots beside widget
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Column()
              .width(30)
              .height(30)
              .borderRadius(9)
              .backgroundColor('#2C2C2E')
            Column()
              .width(30)
              .height(30)
              .borderRadius(9)
              .backgroundColor('#2C2C2E')
          }
          Row({ space: 10 }) {
            Column()
              .width(30)
              .height(30)
              .borderRadius(9)
              .backgroundColor('#2C2C2E')
            Column()
              .width(30)
              .height(30)
              .borderRadius(9)
              .backgroundColor('#2C2C2E')
          }
        }
      }
      .margin({ bottom: 12 })

      // 3x4 Grey Icon Dots Grid
      Column({ space: 10 }) {
        ForEach(PHONE_DOT_ROWS, (rowIdx: number) => {
          Row({ space: 10 }) {
            ForEach(PHONE_DOT_COLS, (colIdx: number) => {
              Column()
                .width(30)
                .height(30)
                .borderRadius(9)
                .backgroundColor('#262628')
            }, (colIdx: number) => `${rowIdx}_${colIdx}`)
          }
        }, (rowIdx: number) => `row_${rowIdx}`)
      }

      Blank()

      // Bottom Dock Bar
      Row({ space: 10 }) {
        ForEach(PHONE_DOT_COLS, (idx: number) => {
          Column()
            .width(28)
            .height(28)
            .borderRadius(8)
            .backgroundColor('#3A3A3C')
        }, (idx: number) => `dock_${idx}`)
      }
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor('#1C1C1E')
      .margin({ bottom: 12 })
    }
    .width(184)
    .height(324)
    .borderRadius(34)
    .backgroundColor('#141416')
    .border({ width: 3, color: '#2E2E30' })
    .rotate({ angle: -8 })
    .shadow({
      radius: 32,
      color: '#33FFB800',
      offsetX: 0,
      offsetY: 12
    })
  }

  @Builder
  private buildWelcomeStep() {
    Column() {
      Blank()

      this.buildPhoneIllustration()

      // Brand Badge + Title
      Row({ space: 10 }) {
        Column() {
          Text('♥')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#000000')
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .backgroundColor('#FFB800')
        .justifyContent(FlexAlign.Center)

        Text('Locket')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .margin({ top: 36 })
      .justifyContent(FlexAlign.Center)

      Text('Ảnh trực tiếp từ bạn bè,\nngay trên màn hình chính')
        .fontSize(17)
        .fontColor('#8E8E93')
        .textAlign(TextAlign.Center)
        .lineHeight(24)
        .margin({ top: 12, bottom: 40 })

      Button('Tạo một tài khoản')
        .width('100%')
        .height(54)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#000000')
        .backgroundColor('#FFB800')
        .borderRadius(27)
        .onClick(() => {
          this.errorMessage = '';
          this.step = 1;
        })

      Text('Đăng nhập')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .padding({ top: 18, bottom: 24, left: 24, right: 24 })
        .onClick(() => {
          this.errorMessage = '';
          this.step = 1;
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, bottom: 16 })
  }

  @Builder
  private buildEmailStep() {
    Column() {
      // Top-left circular back button
      Row() {
        Button('<')
          .width(44)
          .height(44)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor('#1C1C1E')
          .borderRadius(22)
          .onClick(() => {
            this.errorMessage = '';
            this.step = 0;
          })
        Blank()
      }
      .width('100%')
      .padding({ top: 16 })

      Blank()

      Text('Email của bạn là gì?')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })

      TextInput({ placeholder: 'Địa chỉ email', text: this.email })
        .type(InputType.Email)
        .width('100%')
        .height(56)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .placeholderColor('#8E8E93')
        .caretColor('#FFB800')
        .backgroundColor('#1C1C1E')
        .borderRadius(16)
        .border({ width: 1, color: '#2E2E30' })
        .padding({ left: 18, right: 18 })
        .onChange((val: string) => {
          this.email = val;
        })
        .onSubmit(() => {
          if (this.email.trim().length > 0) {
            this.step = 2;
          }
        })

      // Pill chip: Sử dụng số điện thoại
      Button('Sử dụng số điện thoại')
        .height(36)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor('#1C1C1E')
        .borderRadius(18)
        .border({ width: 1, color: '#2E2E30' })
        .padding({ left: 16, right: 16 })
        .margin({ top: 18 })
        .onClick(() => {
          promptAction.showToast({ message: 'Vui lòng sử dụng địa chỉ email Locket để đăng nhập' });
        })

      Blank()

      Text('Bằng cách nhấn Tiếp tục, bạn đồng ý với Điều khoản dịch vụ\nvà Chính sách quyền riêng tư của chúng tôi.')
        .fontSize(12)
        .fontColor('#8E8E93')
        .textAlign(TextAlign.Center)
        .lineHeight(18)
        .margin({ bottom: 16 })

      Button('Tiếp tục →')
        .width('100%')
        .height(54)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.email.trim().length > 0 ? '#000000' : '#8E8E93')
        .backgroundColor(this.email.trim().length > 0 ? '#FFB800' : '#1C1C1E')
        .borderRadius(27)
        .enabled(this.email.trim().length > 0)
        .margin({ bottom: 24 })
        .onClick(() => {
          if (this.email.trim().length > 0) {
            this.errorMessage = '';
            this.step = 2;
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
  }

  @Builder
  private buildPasswordStep() {
    Column() {
      // Top-left circular back button
      Row() {
        Button('<')
          .width(44)
          .height(44)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor('#1C1C1E')
          .borderRadius(22)
          .onClick(() => {
            this.errorMessage = '';
            this.step = 1;
          })
        Blank()
      }
      .width('100%')
      .padding({ top: 16 })

      Blank()

      Text('Điền mật khẩu của bạn')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })

      TextInput({ placeholder: 'Mật khẩu', text: this.password })
        .type(InputType.Password)
        .width('100%')
        .height(56)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .placeholderColor('#8E8E93')
        .caretColor('#FFB800')
        .backgroundColor('#1C1C1E')
        .borderRadius(16)
        .border({ width: 1, color: '#2E2E30' })
        .padding({ left: 18, right: 18 })
        .onChange((val: string) => {
          this.password = val;
        })
        .onSubmit(() => {
          if (this.password.length > 0 && !this.isLoading) {
            this.handleLogin();
          }
        })

      // Pill chip: Bạn đã quên mật khẩu
      Button('Bạn đã quên mật khẩu')
        .height(36)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor('#1C1C1E')
        .borderRadius(18)
        .border({ width: 1, color: '#2E2E30' })
        .padding({ left: 16, right: 16 })
        .margin({ top: 18 })
        .onClick(() => {
          promptAction.showToast({ message: 'Vui lòng đặt lại mật khẩu qua email đã đăng ký' });
        })

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor('#FF453A')
          .textAlign(TextAlign.Center)
          .margin({ top: 16 })
          .width('100%')
      }

      Blank()

      Button(this.isLoading ? 'Đang đăng nhập...' : 'Tiếp tục →')
        .width('100%')
        .height(54)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.password.length > 0 && !this.isLoading ? '#000000' : '#8E8E93')
        .backgroundColor(this.password.length > 0 && !this.isLoading ? '#FFB800' : '#1C1C1E')
        .borderRadius(27)
        .enabled(this.password.length > 0 && !this.isLoading)
        .margin({ bottom: 24 })
        .onClick(() => {
          this.handleLogin();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
  }

  build() {
    Column() {
      if (this.step === 0) {
        this.buildWelcomeStep()
      } else if (this.step === 1) {
        this.buildEmailStep()
      } else {
        this.buildPasswordStep()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
