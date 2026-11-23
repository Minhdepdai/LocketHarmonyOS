import { promptAction, router } from '@kit.ArkUI';
import { FriendItem, getDisplayName, UserProfile } from '../models/LocketModels';
import { LocketApiClient } from '../services/LocketApiClient';
import { SessionManager } from '../services/SessionManager';

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

  aboutToAppear(): void {
    this.loadFriends();
    this.loadMyUsername();
  }

  private async loadMyUsername(): Promise<void> {
    try {
      const session = SessionManager.getInstance().getSession();
      if (session !== null) {
        const me = await LocketApiClient.getInstance().fetchUser(session.localId);
        if (me.username.length > 0) {
          this.myUsername = me.username;
        } else if (session.email.includes('@')) {
          this.myUsername = session.email.split('@')[0];
        }
      }
    } catch (_err) {
      // Keep fallback username
    }
  }

  private async loadFriends(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      this.friends = await LocketApiClient.getInstance().getAllFriends();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể tải danh sách bạn bè';
      this.errorMessage = msg;
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
      promptAction.showToast({ message: `Đã xóa ${getDisplayName(friend)} khỏi danh sách bạn bè` });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể xóa bạn bè';
      promptAction.showToast({ message: msg });
    }
  }

  @Builder
  private buildSocialAppButton(label: string, icon: string, bgColor: string, iconColor: string, isTextIcon: boolean) {
    Column({ space: 6 }) {
      Column() {
        Text(icon)
          .fontSize(isTextIcon ? 15 : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor(iconColor)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(bgColor)
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(12)
        .fontColor('#FFFFFF')
    }
    .onClick(() => {
      promptAction.showToast({ message: `Chia sẻ liên kết locket.cam/${this.myUsername} qua ${label}` });
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
          Text('🔍')
            .fontSize(16)
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
              .margin({ right: 6 })
              .enabled(!this.isSearching)
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
              .enabled(!this.isSendingRequest)
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
            // Section: Tìm bạn bè từ các ứng dụng khác
            Column({ space: 12 }) {
              Text('Tìm bạn bè từ các ứng dụng khác')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#8E8E93')
                .width('100%')

              Row() {
                this.buildSocialAppButton('Messenger', '⚡', '#0084FF', '#FFFFFF', false)
                Blank()
                this.buildSocialAppButton('Zalo', 'Zalo', '#FFFFFF', '#0068FF', true)
                Blank()
                this.buildSocialAppButton('Insta', '📷', '#E1306C', '#FFFFFF', false)
                Blank()
                this.buildSocialAppButton('Khác', '•••', '#3A3A3C', '#FFFFFF', true)
              }
              .width('100%')
              .padding({ left: 8, right: 8 })
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
                  Text('✕')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#8E8E93')
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
                    // 56x56 circular avatar with 2.5vp #FFB800 gold ring
                    if (friend.profilePictureUrl.length > 0) {
                      Image(friend.profilePictureUrl)
                        .width(56)
                        .height(56)
                        .borderRadius(28)
                        .objectFit(ImageFit.Cover)
                        .border({ width: 2.5, color: '#FFB800' })
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
                      Text('💬')
                        .fontSize(16)
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor('#2C2C2E')
                    .justifyContent(FlexAlign.Center)
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

                    // Circular #2C2C2E ✕ remove button
                    Column() {
                      Text('✕')
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#8E8E93')
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor('#2C2C2E')
                    .justifyContent(FlexAlign.Center)
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
      .padding({ left: 18, right: 18 })
      .backgroundColor('#1C1C1E')
      .borderRadius({ topLeft: 28, topRight: 28 })
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
