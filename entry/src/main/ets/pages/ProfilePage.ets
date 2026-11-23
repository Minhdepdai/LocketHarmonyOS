import { promptAction, router } from '@kit.ArkUI';
import { getDisplayName, UserProfile } from '../models/LocketModels';
import { LocketApiClient } from '../services/LocketApiClient';
import { SessionManager } from '../services/SessionManager';

@Entry
@Component
struct ProfilePage {
  @State myProfile: UserProfile | null = null;
  @State userEmail: string = '';
  @State streakOnWidget: boolean = true;
  @State isLoading: boolean = true;

  aboutToAppear(): void {
    this.loadProfile();
  }

  private async loadProfile(): Promise<void> {
    this.isLoading = true;
    try {
      const session = SessionManager.getInstance().getSession();
      if (session === null) {
        router.clear();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.userEmail = session.email;
      this.myProfile = await LocketApiClient.getInstance().fetchUser(session.localId);
    } catch (_err) {
      // Keep fallback session info if network fetch fails
    } finally {
      this.isLoading = false;
    }
  }

  private getProfileName(): string {
    if (this.myProfile !== null) {
      return getDisplayName(this.myProfile);
    }
    const session = SessionManager.getInstance().getSession();
    if (session !== null && session.displayName.length > 0) {
      return session.displayName;
    }
    return 'Người dùng Locket';
  }

  private getProfileUsername(): string {
    if (this.myProfile !== null && this.myProfile.username.length > 0) {
      return this.myProfile.username;
    }
    const session = SessionManager.getInstance().getSession();
    if (session !== null && session.email.includes('@')) {
      return session.email.split('@')[0];
    }
    return 'locket';
  }

  private getInitial(): string {
    const name = this.getProfileName();
    return name.length > 0 ? name.substring(0, 1).toUpperCase() : 'L';
  }

  private async handleLogout(): Promise<void> {
    await SessionManager.getInstance().clearSession();
    router.clear();
    router.replaceUrl({ url: 'pages/LoginPage' });
  }

  @Builder
  private buildSettingsRow(
    iconRes: Resource,
    iconColor: string,
    label: string,
    trailing: string,
    isDanger: boolean,
    onTap: () => void
  ) {
    Row() {
      Image(iconRes)
        .width(20)
        .height(20)
        .fillColor(iconColor)

      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(isDanger ? '#FF453A' : '#FFFFFF')
        .margin({ left: 12 })

      Blank()

      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(13)
          .fontColor('#8E8E93')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 140 })
          .margin({ right: 6 })
      }

      Text('›')
        .fontSize(20)
        .fontColor(isDanger ? '#FF453A' : '#8E8E93')
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Column() {
      // Top Back Bar
      Row() {
        Column() {
          Image($r('app.media.ic_back'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF')
        }
        .width(44)
        .height(44)
        .backgroundColor('#1C1C1E')
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.back();
        })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 4 })

      Scroll() {
        Column({ space: 14 }) {
          // Centered Avatar with 3vp gold ring + golden glow + Name + Chỉnh ảnh
          Column() {
            Stack({ alignContent: Alignment.Center }) {
              if (this.myProfile !== null && this.myProfile.profilePictureUrl.length > 0) {
                Image(this.myProfile.profilePictureUrl)
                  .width(96)
                  .height(96)
                  .borderRadius(48)
                  .objectFit(ImageFit.Cover)
                  .border({ width: 3, color: '#FFB800' })
                  .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
              } else {
                Column() {
                  Text(this.getInitial())
                    .fontSize(36)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                }
                .width(96)
                .height(96)
                .borderRadius(48)
                .backgroundColor('#262628')
                .border({ width: 3, color: '#FFB800' })
                .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
                .justifyContent(FlexAlign.Center)
              }
            }

            Text(this.getProfileName())
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .margin({ top: 14 })

            Text('Chỉnh ảnh')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFB800')
              .margin({ top: 6 })
              .onClick(() => {
                promptAction.showToast({ message: 'Cập nhật ảnh đại diện trên Locket' });
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 4, bottom: 8 })

          // Card 1: Locket Gold
          Row() {
            Column() {
              Image($r('app.media.ic_heart_locket'))
                .width(22)
                .height(22)
                .fillColor('#FFB800')
            }
            .width(42)
            .height(42)
            .borderRadius(21)
            .backgroundColor('#3D3112')
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('Locket Gold')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFB800')
              Text('Mở khóa các tính năng độc quyền')
                .fontSize(13)
                .fontColor('#C8B480')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })

            Blank()

            Text('›')
              .fontSize(22)
              .fontColor('#FFB800')
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#2A2210')
          .borderRadius(18)
          .border({ width: 1, color: '#5A4614' })
          .onClick(() => {
            promptAction.showToast({ message: 'Locket Gold đang khả dụng trên tài khoản của bạn' });
          })

          // Card 2: Rollcall — Ngay bây giờ
          Row() {
            Column() {
              Text('Rollcall — Ngay bây giờ')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text('Chia sẻ khoảnh khắc ngay lúc này')
                .fontSize(13)
                .fontColor('#8E8E93')
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button('CHỌN ẢNH')
              .height(34)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFB800')
              .backgroundColor('#000000')
              .borderRadius(17)
              .border({ width: 1.5, color: '#FFB800' })
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/CameraPage' });
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#1C1C1E')
          .borderRadius(18)
          .border({ width: 1, color: '#2E2E30' })

          // Card 3: Mời bạn bè tham gia Locket!
          Row() {
            Column() {
              Text('Mời bạn bè tham gia Locket!')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text(`locket.cam/${this.getProfileUsername()}`)
                .fontSize(13)
                .fontColor('#FFB800')
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column() {
              Image($r('app.media.ic_share'))
                .width(18)
                .height(18)
                .fillColor('#FFFFFF')
            }
            .width(38)
            .height(38)
            .borderRadius(19)
            .backgroundColor('#262628')
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#1C1C1E')
          .borderRadius(18)
          .border({ width: 1, color: '#2E2E30' })
          .onClick(() => {
            promptAction.showToast({ message: `Đã sao chép locket.cam/${this.getProfileUsername()}` });
          })

          // Section 1: Thiết lập Tiện ích
          Text('Thiết lập Tiện ích')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#8E8E93')
            .width('100%')
            .padding({ left: 8, top: 8 })

          Column() {
            this.buildSettingsRow($r('app.media.ic_grid'), '#FFFFFF', 'Thêm Tiện ích', '', false, () => {
              promptAction.showToast({ message: 'Nhấn giữ màn hình chính để thêm tiện ích Locket' });
            })
            Divider().color('#2E2E30').margin({ left: 48 })
            Row() {
              Image($r('app.media.ic_heart_locket'))
                .width(20)
                .height(20)
                .fillColor('#FFB800')
              Text('Chuỗi trên tiện ích')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .margin({ left: 12 })
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.streakOnWidget })
                .selectedColor('#FFB800')
                .onChange((isOn: boolean) => {
                  this.streakOnWidget = isOn;
                })
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor('#1C1C1E')
          .borderRadius(18)
          .border({ width: 1, color: '#2E2E30' })

          // Section 2: Tổng quát
          Text('Tổng quát')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#8E8E93')
            .width('100%')
            .padding({ left: 8, top: 8 })

          Column() {
            this.buildSettingsRow($r('app.media.ic_megaphone'), '#FFFFFF', 'Thông báo', '', false, () => {
              promptAction.showToast({ message: 'Thông báo Locket đang được bật' });
            })
            Divider().color('#2E2E30').margin({ left: 48 })
            this.buildSettingsRow($r('app.media.ic_friends'), '#FFFFFF', 'Sửa tên', this.getProfileName(), false, () => {
              promptAction.showToast({ message: `Tên hiện tại: ${this.getProfileName()}` });
            })
            Divider().color('#2E2E30').margin({ left: 48 })
            this.buildSettingsRow($r('app.media.ic_chat'), '#FFFFFF', 'Thay đổi địa chỉ email', this.userEmail, false, () => {
              promptAction.showToast({ message: `Email hiện tại: ${this.userEmail}` });
            })
          }
          .width('100%')
          .backgroundColor('#1C1C1E')
          .borderRadius(18)
          .border({ width: 1, color: '#2E2E30' })

          // Section 3: Riêng tư & bảo mật
          Text('Riêng tư & bảo mật')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#8E8E93')
            .width('100%')
            .padding({ left: 8, top: 8 })

          Column() {
            this.buildSettingsRow($r('app.media.ic_home'), '#FFFFFF', 'Quyền riêng tư', '', false, () => {
              promptAction.showToast({ message: 'Chỉ bạn bè mới có thể xem ảnh Locket của bạn' });
            })
            Divider().color('#2E2E30').margin({ left: 48 })
            this.buildSettingsRow($r('app.media.ic_close'), '#FFFFFF', 'Tài khoản đã chặn', '', false, () => {
              promptAction.showToast({ message: 'Không có tài khoản nào bị chặn' });
            })
          }
          .width('100%')
          .backgroundColor('#1C1C1E')
          .borderRadius(18)
          .border({ width: 1, color: '#2E2E30' })

          // Section 4: Vùng nguy hiểm
          Text('Vùng nguy hiểm')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#8E8E93')
            .width('100%')
            .padding({ left: 8, top: 8 })

          Column() {
            this.buildSettingsRow($r('app.media.ic_trash'), '#FF453A', 'Xóa tài khoản', '', true, () => {
              promptAction.showToast({ message: 'Vui lòng xác nhận xóa tài khoản qua email hỗ trợ' });
            })
            Divider().color('#2E2E30').margin({ left: 48 })
            this.buildSettingsRow($r('app.media.ic_back'), '#FF453A', 'Đăng xuất', '', true, () => {
              this.handleLogout();
            })
          }
          .width('100%')
          .backgroundColor('#1C1C1E')
          .borderRadius(18)
          .border({ width: 1, color: '#2E2E30' })
          .margin({ bottom: 32 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
