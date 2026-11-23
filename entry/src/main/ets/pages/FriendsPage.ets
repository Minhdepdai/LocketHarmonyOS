import { common } from '@kit.AbilityKit';
import { curves, promptAction, router } from '@kit.ArkUI';
import { FriendItem, getDisplayName, UserProfile } from '../models/LocketModels';
import { CacheService } from '../services/CacheService';
import { LocketApiClient } from '../services/LocketApiClient';
import { SessionManager } from '../services/SessionManager';
import { ShareService } from '../services/ShareService';

@Entry
@Component
struct FriendsPage {
  @State friends: FriendItem[] = [];
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State searchUsername: string = '';
  @State isSearching: boolean = false;
  @State searchResult: UserProfile | null = null;
  @State searchError: string = '';
  @State isSendingRequest: boolean = false;
  @State showTipCard: boolean = true;
  @State myUsername: string = 'locket';
  @State myDisplayName: string = '';
  @State isKnockShareActive: boolean = false;
  @State pressedButtonId: string = '';
  @StorageProp('safe_top_vp') safeTopVp: number = 38;
  @StorageProp('safe_bottom_vp') safeBottomVp: number = 20;
  private isPageVisible: boolean = false;
  private isUsernameLoaded: boolean = false;

  private handleButtonTouch(id: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      animateTo({ curve: curves.springMotion(0.35, 0.65) }, () => {
        this.pressedButtonId = id;
      });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      animateTo({ curve: curves.springMotion(0.45, 0.72) }, () => {
        if (this.pressedButtonId === id) {
          this.pressedButtonId = '';
        }
      });
    }
  }

  aboutToAppear(): void {
    const cached = CacheService.getInstance().getCachedFriends();
    if (cached.length > 0) {
      this.friends = cached;
      this.isLoading = false;
    }
    this.loadFriends();
    this.loadMyUsername();
  }

  onPageShow(): void {
    this.isPageVisible = true;
    if (this.isUsernameLoaded) {
      this.activateKnockShare(false);
    }
  }

  onPageHide(): void {
    this.isPageVisible = false;
    ShareService.disableKnockShare();
    this.isKnockShareActive = false;
  }

  aboutToDisappear(): void {
    this.isPageVisible = false;
    ShareService.disableKnockShare();
    this.isKnockShareActive = false;
  }

  private async loadMyUsername(): Promise<void> {
    try {
      const session = SessionManager.getInstance().getSession();
      if (session !== null) {
        if (session.displayName.length > 0) {
          this.myDisplayName = session.displayName;
        }
        const me = await LocketApiClient.getInstance().fetchUser(session.localId);
        const resolvedName = getDisplayName(me);
        if (resolvedName.length > 0) {
          this.myDisplayName = resolvedName;
        }
        if (me.username.length > 0) {
          this.myUsername = me.username;
        } else if (session.email.includes('@')) {
          this.myUsername = session.email.split('@')[0];
        }
      }
    } catch (_err) {
      // Keep fallback username
    } finally {
      this.isUsernameLoaded = true;
      if (this.isPageVisible) {
        this.activateKnockShare(false);
      }
    }
  }

  private async handleCopyInviteLink(): Promise<void> {
    try {
      await ShareService.copyInviteLink(this.myUsername);
      promptAction.showToast({ message: 'Đã sao chép link mời!' });
    } catch (_err) {
      promptAction.showToast({ message: 'Không thể sao chép link mời' });
    }
  }

  private async handleSystemShare(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await ShareService.shareViaSystemSheet(context, this.myUsername, this.myDisplayName);
    } catch (_err) {
      try {
        await ShareService.copyInviteLink(this.myUsername);
        promptAction.showToast({ message: 'Đã sao chép link mời!' });
      } catch (_copyErr) {
        promptAction.showToast({ message: 'Không thể mở bảng chia sẻ hệ thống' });
      }
    }
  }

  private activateKnockShare(showFeedback: boolean): void {
    const enabled = ShareService.enableKnockShare(this.myUsername, this.myDisplayName);
    this.isKnockShareActive = enabled;
    if (showFeedback) {
      if (enabled) {
        promptAction.showToast({ message: 'Đưa đỉnh 2 máy HarmonyOS lại gần nhau để chia sẻ link' });
      } else {
        promptAction.showToast({ message: 'Thiết bị chưa hỗ trợ Chạm máy (NearLink)' });
      }
    }
  }

  private handleToggleKnockShare(): void {
    if (this.isKnockShareActive) {
      ShareService.disableKnockShare();
      this.isKnockShareActive = false;
      promptAction.showToast({ message: 'Đã tắt Chạm máy (NearLink)' });
      return;
    }
    this.activateKnockShare(true);
  }

  private async loadFriends(): Promise<void> {
    const hasCached = this.friends.length > 0;
    if (!hasCached) {
      this.isLoading = true;
    }
    this.errorMessage = '';
    try {
      const fresh = await LocketApiClient.getInstance().getAllFriends();
      this.friends = fresh;
      CacheService.getInstance().saveFriends(fresh);
    } catch (err) {
      if (!hasCached) {
        const msg = err instanceof Error ? err.message : 'Không thể tải danh sách bạn bè';
        this.errorMessage = msg;
      }
    } finally {
      this.isLoading = false;
    }
  }

  private async handleSearchUsername(): Promise<void> {
    const query = this.searchUsername.trim();
    if (query.length === 0) {
      this.searchResult = null;
      this.searchError = '';
      return;
    }
    this.isSearching = true;
    this.searchResult = null;
    this.searchError = '';
    try {
      const user = await LocketApiClient.getInstance().fetchUserByUsername(query);
      if (user === null) {
        this.searchError = 'Không tìm thấy người dùng với username này';
      } else {
        this.searchResult = user;
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Tìm kiếm thất bại';
      this.searchError = msg;
    } finally {
      this.isSearching = false;
    }
  }

  private async handleSendFriendRequest(user: UserProfile): Promise<void> {
    if (this.isSendingRequest) {
      return;
    }
    this.isSendingRequest = true;
    try {
      await LocketApiClient.getInstance().sendFriendRequest(user.uid);
      promptAction.showToast({ message: `Đã gửi lời mời kết bạn tới ${getDisplayName(user)}` });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể gửi lời mời kết bạn';
      promptAction.showToast({ message: msg });
    } finally {
      this.isSendingRequest = false;
    }
  }

  private async handleRemoveFriend(friend: FriendItem): Promise<void> {
    try {
      await LocketApiClient.getInstance().removeFriend(friend.uid);
      this.friends = this.friends.filter((f: FriendItem) => f.uid !== friend.uid);
      CacheService.getInstance().saveFriends(this.friends);
      promptAction.showToast({ message: `Đã xóa ${getDisplayName(friend)} khỏi danh sách bạn bè` });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể xóa bạn bè';
      promptAction.showToast({ message: msg });
    }
  }

  @Builder
  private buildShareActionButton(
    label: string,
    iconRes: Resource,
    bgColor: string,
    iconColor: string,
    isHighlighted: boolean,
    onTap: () => void
  ) {
    Column({ space: 8 }) {
      Column() {
        Image(iconRes)
          .width(24)
          .height(24)
          .fillColor(iconColor)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(bgColor)
      .border(isHighlighted ? { width: 1.5, color: '#FFB800' } : { width: 1, color: '#3A3A3C' })
      .shadow(isHighlighted
        ? { radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 }
        : { radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(12)
        .fontWeight(isHighlighted ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(isHighlighted ? '#FFB800' : '#FFFFFF')
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .scale(this.pressedButtonId === `share_${label}` ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
    .onTouch((e: TouchEvent) => {
      this.handleButtonTouch(`share_${label}`, e);
    })
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Column() {
      // Dark sheet surface #1C1C1E
      Column() {
        // Top drag handle (36x4, #48484A, radius 2) + tap to go back
        Column() {
          Row()
            .width(36)
            .height(4)
            .borderRadius(2)
            .backgroundColor('#48484A')
        }
        .width('100%')
        .padding({ top: 12, bottom: 10 })
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          router.back();
        })

        // Centered bold title & muted subtitle
        Text('Bạn bè của bạn')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)

        Text(`${this.friends.length} / 20 người bạn đã được bổ sung`)
          .fontSize(13)
          .fontColor('#8E8E93')
          .margin({ top: 4, bottom: 16 })

        // Rounded search pill #2C2C2E
        Row({ space: 8 }) {
          Image($r('app.media.ic_search'))
            .width(18)
            .height(18)
            .fillColor('#8E8E93')
            .margin({ left: 14 })

          TextInput({
            placeholder: 'Thêm một người bạn mới',
            text: this.searchUsername
          })
            .layoutWeight(1)
            .height(46)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .placeholderColor('#8E8E93')
            .caretColor('#FFB800')
            .backgroundColor(Color.Transparent)
            .padding({ left: 4, right: 8 })
            .onChange((value: string) => {
              this.searchUsername = value;
            })
            .onSubmit(() => {
              this.handleSearchUsername();
            })

          if (this.searchUsername.trim().length > 0) {
            Button(this.isSearching ? '...' : 'Tìm')
              .height(34)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#000000')
              .backgroundColor('#FFB800')
              .borderRadius(17)
              .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
              .scale(this.pressedButtonId === 'friends_search_btn' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
              .margin({ right: 6 })
              .enabled(!this.isSearching)
              .onTouch((e: TouchEvent) => {
                this.handleButtonTouch('friends_search_btn', e);
              })
              .onClick(() => {
                this.handleSearchUsername();
              })
          }
        }
        .width('100%')
        .height(46)
        .backgroundColor('#2C2C2E')
        .borderRadius(23)
        .margin({ bottom: 14 })

        // Found-user add card or error
        if (this.searchError.length > 0) {
          Text(this.searchError)
            .fontSize(13)
            .fontColor('#FF453A')
            .width('100%')
            .margin({ bottom: 12 })
        } else if (this.searchResult !== null) {
          Row() {
            if (this.searchResult.profilePictureUrl.length > 0) {
              Image(this.searchResult.profilePictureUrl)
                .width(48)
                .height(48)
                .borderRadius(24)
                .objectFit(ImageFit.Cover)
                .border({ width: 2, color: '#FFB800' })
                .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
            } else {
              Column() {
                Text(getDisplayName(this.searchResult).substring(0, 1).toUpperCase())
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#000000')
              }
              .width(48)
              .height(48)
              .borderRadius(24)
              .backgroundColor('#FFB800')
              .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
              .justifyContent(FlexAlign.Center)
            }

            Column() {
              Text(getDisplayName(this.searchResult))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              if (this.searchResult.username.length > 0) {
                Text(`@${this.searchResult.username}`)
                  .fontSize(13)
                  .fontColor('#8E8E93')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })

            Blank()

            Button(this.isSendingRequest ? '...' : '+ Thêm')
              .height(34)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#000000')
              .backgroundColor('#FFB800')
              .borderRadius(17)
              .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
              .scale(this.pressedButtonId === 'friends_add_btn' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
              .enabled(!this.isSendingRequest)
              .onTouch((e: TouchEvent) => {
                this.handleButtonTouch('friends_add_btn', e);
              })
              .onClick(() => {
                if (this.searchResult !== null) {
                  this.handleSendFriendRequest(this.searchResult);
                }
              })
          }
          .width('100%')
          .padding(12)
          .margin({ bottom: 14 })
          .backgroundColor('#262628')
          .borderRadius(18)
          .border({ width: 1, color: '#333336' })
        }

        Scroll() {
          Column({ space: 16 }) {
            // Section: HarmonyOS Native Share Bar
            Column({ space: 12 }) {
              Text('Chia sẻ & Kết nối nhanh')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#8E8E93')
                .width('100%')

              Row() {
                this.buildShareActionButton(
                  'Sao chép link',
                  $r('app.media.ic_copy'),
                  '#2C2C2E',
                  '#FFFFFF',
                  false,
                  () => {
                    this.handleCopyInviteLink();
                  }
                )

                this.buildShareActionButton(
                  'Chia sẻ app',
                  $r('app.media.ic_share'),
                  '#FFB800',
                  '#000000',
                  true,
                  () => {
                    this.handleSystemShare();
                  }
                )

                this.buildShareActionButton(
                  'Chạm máy (NearLink)',
                  $r('app.media.ic_nearlink'),
                  this.isKnockShareActive ? '#2A2210' : '#2C2C2E',
                  this.isKnockShareActive ? '#FFB800' : '#FFFFFF',
                  this.isKnockShareActive,
                  () => {
                    this.handleToggleKnockShare();
                  }
                )
              }
              .width('100%')
              .padding({ left: 4, right: 4 })

              if (this.isKnockShareActive) {
                Row({ space: 8 }) {
                  Image($r('app.media.ic_nearlink'))
                    .width(16)
                    .height(16)
                    .fillColor('#FFB800')

                  Text('Đưa đỉnh 2 máy HarmonyOS lại gần nhau để chia sẻ link')
                    .fontSize(12)
                    .fontColor('#FFB800')
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor('#2A2210')
                .borderRadius(12)
                .border({ width: 1, color: '#5A4614' })
              }
            }
            .width('100%')

            // Dismissible Tip card
            if (this.showTipCard) {
              Row() {
                Column({ space: 3 }) {
                  Text('Tip! Add by username')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                  Text(`Friends can search @${this.myUsername}`)
                    .fontSize(13)
                    .fontColor('#8E8E93')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Column() {
                  Image($r('app.media.ic_close'))
                    .width(14)
                    .height(14)
                    .fillColor('#8E8E93')
                }
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor('#2C2C2E')
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.showTipCard = false;
                })
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#262628')
              .borderRadius(18)
              .border({ width: 1, color: '#333336' })
            }

            // Section: Bạn bè của bạn
            Text('Bạn bè của bạn')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#8E8E93')
              .width('100%')

            if (this.isLoading) {
              Column() {
                LoadingProgress()
                  .width(38)
                  .height(38)
                  .color('#FFB800')
                Text('Đang tải danh sách bạn bè...')
                  .fontSize(13)
                  .fontColor('#8E8E93')
                  .margin({ top: 10 })
              }
              .width('100%')
              .padding({ top: 28, bottom: 28 })
              .justifyContent(FlexAlign.Center)
            } else if (this.errorMessage.length > 0) {
              Column() {
                Text(this.errorMessage)
                  .fontSize(13)
                  .fontColor('#FF453A')
                  .margin({ bottom: 12 })
                Button('Thử lại')
                  .height(38)
                  .fontColor('#000000')
                  .fontWeight(FontWeight.Bold)
                  .backgroundColor('#FFB800')
                  .borderRadius(19)
                  .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
                  .scale(this.pressedButtonId === 'friends_retry_btn' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
                  .onTouch((e: TouchEvent) => {
                    this.handleButtonTouch('friends_retry_btn', e);
                  })
                  .onClick(() => {
                    this.loadFriends();
                  })
              }
              .width('100%')
              .padding({ top: 20, bottom: 20 })
              .justifyContent(FlexAlign.Center)
            } else {
              Column({ space: 12 }) {
                ForEach(this.friends, (friend: FriendItem) => {
                  Row({ space: 12 }) {
                    // 56x56 circular avatar with 2.5vp #FFB800 gold ring + golden glow
                    if (friend.profilePictureUrl.length > 0) {
                      Image(friend.profilePictureUrl)
                        .width(56)
                        .height(56)
                        .borderRadius(28)
                        .objectFit(ImageFit.Cover)
                        .border({ width: 2.5, color: '#FFB800' })
                        .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
                    } else {
                      Column() {
                        Text(getDisplayName(friend).substring(0, 1).toUpperCase())
                          .fontSize(20)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#FFFFFF')
                      }
                      .width(56)
                      .height(56)
                      .borderRadius(28)
                      .backgroundColor('#2C2C2E')
                      .border({ width: 2.5, color: '#FFB800' })
                      .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
                      .justifyContent(FlexAlign.Center)
                    }

                    // Bold white display name + muted username
                    Column({ space: 2 }) {
                      Text(getDisplayName(friend))
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                        .maxLines(1)
                      if (friend.username.length > 0) {
                        Text(`@${friend.username}`)
                          .fontSize(13)
                          .fontColor('#8E8E93')
                          .maxLines(1)
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    // Quick chat icon button
                    Column() {
                      Image($r('app.media.ic_chat'))
                        .width(18)
                        .height(18)
                        .fillColor('#FFFFFF')
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor('#2C2C2E')
                    .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
                    .scale(this.pressedButtonId === `friend_chat_${friend.uid}` ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
                    .justifyContent(FlexAlign.Center)
                    .onTouch((e: TouchEvent) => {
                      this.handleButtonTouch(`friend_chat_${friend.uid}`, e);
                    })
                    .onClick(() => {
                      router.pushUrl({
                        url: 'pages/ChatPage',
                        params: {
                          friendUid: friend.uid,
                          friendName: getDisplayName(friend),
                          friendAvatar: friend.profilePictureUrl
                        }
                      });
                    })

                    // Circular #2C2C2E close/remove button
                    Column() {
                      Image($r('app.media.ic_close'))
                        .width(14)
                        .height(14)
                        .fillColor('#8E8E93')
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor('#2C2C2E')
                    .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
                    .scale(this.pressedButtonId === `friend_rm_${friend.uid}` ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
                    .justifyContent(FlexAlign.Center)
                    .onTouch((e: TouchEvent) => {
                      this.handleButtonTouch(`friend_rm_${friend.uid}`, e);
                    })
                    .onClick(() => {
                      this.handleRemoveFriend(friend);
                    })
                  }
                  .width('100%')
                  .padding({ top: 4, bottom: 4 })
                  .onClick(() => {
                    router.replaceUrl({
                      url: 'pages/HomePage',
                      params: {
                        filterUserUid: friend.uid,
                        filterUserName: getDisplayName(friend)
                      }
                    });
                  })
                }, (friend: FriendItem) => friend.uid)
              }
              .width('100%')
              .padding({ bottom: 28 })
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 18, right: 18, bottom: this.safeBottomVp })
      .backgroundColor('#1C1C1E')
      .borderRadius({ topLeft: 28, topRight: 28 })
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopVp })
    .backgroundColor('#000000')
  }
}
