import { promptAction, router } from '@kit.ArkUI';
import { getDisplayName, MomentItem, UserProfile } from '../models/LocketModels';
import { LocketApiClient } from '../services/LocketApiClient';
import { SessionManager } from '../services/SessionManager';

interface HomeRouteParams {
  filterUserUid?: string;
  filterUserName?: string;
}

@Entry
@Component
struct HomePage {
  @State viewMode: string = 'camera';
  @State moments: MomentItem[] = [];
  @State friendsCount: number = 0;
  @State isLoading: boolean = true;
  @State isLoadingMore: boolean = false;
  @State errorMessage: string = '';
  @State myProfile: UserProfile | null = null;
  @State filterUid: string = '';
  @State filterLabel: string = 'Tất cả bạn bè';
  @State syncToken: string = '';
  @State currentIndex: number = 0;
  @State replyText: string = '';
  @State isSendingReply: boolean = false;
  @State isFrontCamera: boolean = false;
  private viewedMomentIds: Set<string> = new Set();
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    const params = router.getParams() as HomeRouteParams | undefined;
    if (params !== undefined && params.filterUserUid !== undefined && params.filterUserUid.length > 0) {
      this.filterUid = params.filterUserUid;
      this.filterLabel = params.filterUserName ?? 'Đã lọc';
      this.viewMode = 'feed';
    }
    this.loadInitialData();
  }

  private async loadInitialData(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.currentIndex = 0;
    this.replyText = '';
    try {
      const session = SessionManager.getInstance().getSession();
      if (session === null) {
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.myProfile = await LocketApiClient.getInstance().fetchUser(session.localId);
      const feed = await LocketApiClient.getInstance().getLatestMoments(undefined, this.filterUid);
      this.moments = feed.moments;
      this.syncToken = feed.syncToken;
      if (this.moments.length > 0) {
        this.markAsViewedSilently(this.moments[0].canonicalUid);
      }
      this.loadFriendsCountSilently();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể tải dữ liệu';
      this.errorMessage = msg;
    } finally {
      this.isLoading = false;
    }
  }

  private loadFriendsCountSilently(): void {
    LocketApiClient.getInstance().getAllFriends().then((list) => {
      this.friendsCount = list.length;
    }).catch(() => {
      // Non-critical count fetch
    });
  }

  private async loadMoreMoments(): Promise<void> {
    if (this.isLoadingMore || this.syncToken.length === 0) {
      return;
    }
    this.isLoadingMore = true;
    try {
      const feed = await LocketApiClient.getInstance().getLatestMoments(this.syncToken, this.filterUid);
      this.syncToken = feed.syncToken;
      if (feed.moments.length > 0) {
        const existingIds: Set<string> = new Set();
        for (let i = 0; i < this.moments.length; i++) {
          existingIds.add(this.moments[i].canonicalUid);
        }
        const appended: MomentItem[] = [...this.moments];
        for (let i = 0; i < feed.moments.length; i++) {
          const item = feed.moments[i];
          if (!existingIds.has(item.canonicalUid)) {
            appended.push(item);
            existingIds.add(item.canonicalUid);
          }
        }
        this.moments = appended;
      }
    } catch (_err) {
      // Keep current feed intact
    } finally {
      this.isLoadingMore = false;
    }
  }

  private markAsViewedSilently(momentUid: string): void {
    if (momentUid.length === 0 || this.viewedMomentIds.has(momentUid)) {
      return;
    }
    this.viewedMomentIds.add(momentUid);
    LocketApiClient.getInstance().markMomentAsViewed(momentUid).catch(() => {
      // Non-critical background call
    });
  }

  private getCurrentMoment(): MomentItem | null {
    if (this.moments.length === 0) {
      return null;
    }
    const idx = Math.min(Math.max(0, this.currentIndex), this.moments.length - 1);
    return this.moments[idx];
  }

  private isOwnMoment(item: MomentItem | null): boolean {
    if (item === null || this.myProfile === null) {
      return false;
    }
    return item.userUid === this.myProfile.uid;
  }

  private async handleReact(momentUid: string, emoji: string): Promise<void> {
    if (momentUid.length === 0) {
      return;
    }
    try {
      await LocketApiClient.getInstance().reactToMoment(momentUid, emoji);
      promptAction.showToast({ message: `Đã thả cảm xúc ${emoji}` });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể thả cảm xúc';
      promptAction.showToast({ message: msg });
    }
  }

  private async handleSendQuickReply(item: MomentItem): Promise<void> {
    const text = this.replyText.trim();
    if (text.length === 0 || this.isSendingReply) {
      return;
    }
    this.isSendingReply = true;
    try {
      await LocketApiClient.getInstance().sendChatMessage(item.userUid, text, item.canonicalUid);
      this.replyText = '';
      promptAction.showToast({ message: `Đã gửi tin nhắn tới ${item.senderName}` });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Gửi tin nhắn thất bại';
      promptAction.showToast({ message: msg });
    } finally {
      this.isSendingReply = false;
    }
  }

  private async handleDeleteMoment(momentUid: string): Promise<void> {
    try {
      await LocketApiClient.getInstance().deleteMoment(momentUid);
      this.moments = this.moments.filter((m: MomentItem) => m.canonicalUid !== momentUid);
      if (this.currentIndex >= this.moments.length && this.moments.length > 0) {
        this.currentIndex = this.moments.length - 1;
      }
      promptAction.showToast({ message: 'Đã xóa khoảnh khắc' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể xóa khoảnh khắc';
      promptAction.showToast({ message: msg });
    }
  }

  private formatShortRelativeTime(seconds: number): string {
    if (seconds <= 0) {
      return '';
    }
    const diffSec = Math.max(0, Math.floor(Date.now() / 1000) - seconds);
    if (diffSec < 60) {
      return '1m';
    }
    const diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) {
      return `${diffMin}m`;
    }
    const diffHour = Math.floor(diffMin / 60);
    if (diffHour < 24) {
      return `${diffHour}h`;
    }
    const diffDay = Math.floor(diffHour / 24);
    return `${diffDay}d`;
  }

  private getMyInitial(): string {
    if (this.myProfile !== null) {
      const name = getDisplayName(this.myProfile);
      if (name.length > 0) {
        return name.substring(0, 1).toUpperCase();
      }
    }
    return 'L';
  }

  @Builder
  private buildTopBar() {
    Row() {
      // Left: 44x44 circle megaphone icon
      Column() {
        Text('📢')
          .fontSize(18)
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor('#1A1A1C')
      .border({ width: 1, color: '#2E2E30' })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.loadInitialData();
        promptAction.showToast({ message: 'Đã làm mới khoảnh khắc' });
      })

      Blank()

      // Center: Mode-aware Friends / Filter pill
      Row({ space: 6 }) {
        if (this.viewMode === 'camera') {
          Text('👥')
            .fontSize(15)
          Text(`${this.friendsCount} Bạn bè`)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
        } else {
          Text(this.filterUid.length > 0 ? `${this.filterLabel} ✕` : `${this.filterLabel} ⌄`)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
        }
      }
      .height(44)
      .padding({ left: 18, right: 18 })
      .borderRadius(22)
      .backgroundColor('#1A1A1C')
      .border({ width: 1, color: '#2E2E30' })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.viewMode !== 'camera' && this.filterUid.length > 0) {
          this.filterUid = '';
          this.filterLabel = 'Tất cả bạn bè';
          this.loadInitialData();
        } else {
          router.pushUrl({ url: 'pages/FriendsPage' });
        }
      })

      Blank()

      // Right: 44x44 circular user avatar -> ProfilePage
      Stack({ alignContent: Alignment.Center }) {
        if (this.myProfile !== null && this.myProfile.profilePictureUrl.length > 0) {
          Image(this.myProfile.profilePictureUrl)
            .width(44)
            .height(44)
            .borderRadius(22)
            .objectFit(ImageFit.Cover)
            .border({ width: 1.5, color: '#2E2E30' })
        } else {
          Column() {
            Text(this.getMyInitial())
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor('#2C2C2E')
          .border({ width: 1.5, color: '#2E2E30' })
          .justifyContent(FlexAlign.Center)
        }
      }
      .onClick(() => {
        router.pushUrl({ url: 'pages/ProfilePage' });
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 10 })
  }

  @Builder
  private buildCameraMode() {
    Column() {
      // Large 1:1 rounded viewfinder
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Text('📷')
            .fontSize(44)
            .opacity(0.65)
          Text(this.isFrontCamera ? 'Camera trước • Chạm để chụp' : 'Chạm để chụp hoặc chọn ảnh')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ top: 10 })
        }
        .width('100%')
        .aspectRatio(1)
        .borderRadius(56)
        .backgroundColor('#141416')
        .border({ width: 1, color: '#2E2E30' })
        .justifyContent(FlexAlign.Center)

        // Subtle zoom badge inside viewfinder
        Text('1x')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFB800')
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(14)
          .backgroundColor('#88000000')
          .margin({ bottom: 18 })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .margin({ top: 8 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/CameraPage' });
      })

      Blank()

      // Shutter Row: Gallery | Big 84x84 Shutter | Flip
      Row() {
        // Left Gallery button
        Column() {
          Text('🖼️')
            .fontSize(22)
        }
        .width(50)
        .height(50)
        .borderRadius(25)
        .backgroundColor('#1C1C1E')
        .border({ width: 1, color: '#2E2E30' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.pushUrl({ url: 'pages/CameraPage' });
        })

        // Center big 84x84 Shutter circle (#FFB800 4vp ring + black gap + inner circle)
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(84)
            .height(84)
            .borderRadius(42)
            .backgroundColor('#000000')
            .border({ width: 4, color: '#FFB800' })

          Column()
            .width(68)
            .height(68)
            .borderRadius(34)
            .backgroundColor('#FFFFFF')
        }
        .margin({ left: 36, right: 36 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/CameraPage' });
        })

        // Right Flip icon
        Column() {
          Text('🔄')
            .fontSize(22)
        }
        .width(50)
        .height(50)
        .borderRadius(25)
        .backgroundColor('#1C1C1E')
        .border({ width: 1, color: '#2E2E30' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.isFrontCamera = !this.isFrontCamera;
          promptAction.showToast({ message: this.isFrontCamera ? 'Đã chuyển camera trước' : 'Đã chuyển camera sau' });
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // History cue below shutter
      Row({ space: 8 }) {
        Text(`${this.moments.length}+`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFB800')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(10)
          .backgroundColor('#6E5200')

        Text('Lịch sử ⌄')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .margin({ top: 14 })
      .onClick(() => {
        this.viewMode = 'feed';
      })

      // Bottom floating pill nav
      Row({ space: 8 }) {
        // Grid / Calendar icon
        Column() {
          Text('⊞')
            .fontSize(20)
            .fontColor('#8E8E93')
        }
        .width(54)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.viewMode = 'grid';
        })

        // Home highlighted pill
        Column() {
          Text('⌂')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(68)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#262628')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.viewMode = 'camera';
        })

        // Chat icon
        Column() {
          Text('💬')
            .fontSize(18)
        }
        .width(54)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.pushUrl({ url: 'pages/FriendsPage' });
        })
      }
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .borderRadius(32)
      .backgroundColor('#141416')
      .border({ width: 1, color: '#2E2E30' })
      .margin({ top: 10, bottom: 18 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildFeedMode() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(44)
            .height(44)
            .color('#FFB800')
          Text('Đang tải khoảnh khắc...')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMessage.length > 0) {
        Column() {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#FF453A')
            .textAlign(TextAlign.Center)
            .margin({ bottom: 16 })
          Button('Thử lại')
            .height(42)
            .fontColor('#000000')
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#FFB800')
            .borderRadius(21)
            .padding({ left: 24, right: 24 })
            .onClick(() => {
              this.loadInitialData();
            })
        }
        .layoutWeight(1)
        .padding(24)
        .justifyContent(FlexAlign.Center)
      } else if (this.moments.length === 0) {
        Column() {
          Text('Chưa có khoảnh khắc nào')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .margin({ bottom: 14 })
          Button('Làm mới')
            .height(42)
            .fontColor('#000000')
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#FFB800')
            .borderRadius(21)
            .padding({ left: 24, right: 24 })
            .onClick(() => {
              this.loadInitialData();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // Vertical Swiper of moments
        Swiper(this.swiperController) {
          ForEach(this.moments, (item: MomentItem) => {
            Column() {
              // 1:1 Photo Card (borderRadius 56) + translucent caption pill
              Stack({ alignContent: Alignment.Bottom }) {
                Image(item.thumbnailUrl)
                  .width('100%')
                  .aspectRatio(1)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(56)
                  .backgroundColor('#141416')

                if (item.caption.length > 0) {
                  Text(item.caption)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                    .backgroundColor('#993A3A3C')
                    .borderRadius(20)
                    .margin({ bottom: 18, left: 20, right: 20 })
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12 })

              // Sender row: 28x28 avatar + bold white name + muted short relative time
              Row({ space: 8 }) {
                if (item.senderAvatar.length > 0) {
                  Image(item.senderAvatar)
                    .width(28)
                    .height(28)
                    .borderRadius(14)
                    .objectFit(ImageFit.Cover)
                } else {
                  Column() {
                    Text(item.senderName.length > 0 ? item.senderName.substring(0, 1).toUpperCase() : 'L')
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                  }
                  .width(28)
                  .height(28)
                  .borderRadius(14)
                  .backgroundColor('#2C2C2E')
                  .justifyContent(FlexAlign.Center)
                }

                Text(item.senderName)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .maxLines(1)

                Text(this.formatShortRelativeTime(item.createdAtSeconds))
                  .fontSize(14)
                  .fontColor('#8E8E93')
              }
              .margin({ top: 14 })
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }, (item: MomentItem) => item.canonicalUid)
        }
        .index(this.currentIndex)
        .vertical(true)
        .loop(false)
        .indicator(false)
        .layoutWeight(1)
        .onChange((index: number) => {
          this.currentIndex = index;
          this.replyText = '';
          if (index >= 0 && index < this.moments.length) {
            this.markAsViewedSilently(this.moments[index].canonicalUid);
          }
          if (index >= this.moments.length - 1 && this.syncToken.length > 0 && !this.isLoadingMore) {
            this.loadMoreMoments();
          }
        })

        // Combined Reply + Reaction Pill Bar
        Row({ space: 4 }) {
          TextInput({ placeholder: 'Gửi tin nh...', text: this.replyText })
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .placeholderColor('#8E8E93')
            .caretColor('#FFB800')
            .backgroundColor(Color.Transparent)
            .padding({ left: 10, right: 6 })
            .onChange((value: string) => {
              this.replyText = value;
            })
            .onSubmit(() => {
              const current = this.getCurrentMoment();
              if (current !== null) {
                this.handleSendQuickReply(current);
              }
            })

          if (this.replyText.trim().length > 0) {
            Button(this.isSendingReply ? '...' : '➤')
              .width(40)
              .height(40)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#000000')
              .backgroundColor('#FFB800')
              .borderRadius(20)
              .enabled(!this.isSendingReply)
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleSendQuickReply(current);
                }
              })
          } else {
            Text('💛')
              .fontSize(22)
              .padding({ left: 5, right: 5 })
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleReact(current.canonicalUid, '💛');
                }
              })
            Text('🔥')
              .fontSize(22)
              .padding({ left: 5, right: 5 })
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleReact(current.canonicalUid, '🔥');
                }
              })
            Text('😍')
              .fontSize(22)
              .padding({ left: 5, right: 5 })
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleReact(current.canonicalUid, '😍');
                }
              })
            Text('☺+')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 8 })
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleReact(current.canonicalUid, '😂');
                }
              })
          }
        }
        .height(52)
        .padding({ left: 10, right: 10 })
        .margin({ left: 16, right: 16, bottom: 12 })
        .borderRadius(26)
        .backgroundColor('#1C1C1E')
        .border({ width: 1, color: '#2E2E30' })
      }

      // Bottom Controls Row
      Row() {
        // Left 48x48 circle: 4-squares Grid icon
        Column() {
          Text('⊞')
            .fontSize(20)
            .fontColor('#FFFFFF')
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor('#1A1A1C')
        .border({ width: 1, color: '#2E2E30' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.viewMode = 'grid';
        })

        Blank()

        // Center pill: Calendar | 44x44 white circle with #FFB800 ring | Chat
        Row({ space: 18 }) {
          Text('📅')
            .fontSize(19)
            .onClick(() => {
              this.viewMode = 'grid';
            })

          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor('#000000')
              .border({ width: 3, color: '#FFB800' })
            Column()
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor('#FFFFFF')
          }
          .onClick(() => {
            this.viewMode = 'camera';
          })

          Text('💬')
            .fontSize(19)
            .onClick(() => {
              const current = this.getCurrentMoment();
              if (current !== null) {
                router.pushUrl({
                  url: 'pages/ChatPage',
                  params: {
                    friendUid: current.userUid,
                    friendName: current.senderName,
                    friendAvatar: current.senderAvatar
                  }
                });
              } else {
                router.pushUrl({ url: 'pages/FriendsPage' });
              }
            })
        }
        .height(56)
        .padding({ left: 20, right: 20 })
        .borderRadius(28)
        .backgroundColor('#1A1A1C')
        .border({ width: 1, color: '#2E2E30' })

        Blank()

        // Right 48x48 circle: Share/Delete icon
        Column() {
          Text(this.isOwnMoment(this.getCurrentMoment()) ? '🗑' : '↗')
            .fontSize(19)
            .fontColor(this.isOwnMoment(this.getCurrentMoment()) ? '#FF453A' : '#FFFFFF')
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor('#1A1A1C')
        .border({ width: 1, color: '#2E2E30' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const current = this.getCurrentMoment();
          if (current !== null && this.isOwnMoment(current)) {
            this.handleDeleteMoment(current.canonicalUid);
          } else {
            promptAction.showToast({ message: 'Đã chia sẻ khoảnh khắc Locket' });
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 18 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildGridMode() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(44)
            .height(44)
            .color('#FFB800')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.moments.length === 0) {
        Column() {
          Text('Chưa có ảnh nào trong lịch sử')
            .fontSize(15)
            .fontColor('#8E8E93')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.moments, (item: MomentItem, idx: number) => {
            GridItem() {
              Image(item.thumbnailUrl)
                .width('100%')
                .aspectRatio(1)
                .objectFit(ImageFit.Cover)
                .borderRadius(18)
                .backgroundColor('#1C1C1E')
                .onClick(() => {
                  this.currentIndex = idx;
                  this.viewMode = 'feed';
                })
            }
          }, (item: MomentItem) => item.canonicalUid)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(4)
        .rowsGap(4)
        .width('100%')
        .height('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 96 })
        .scrollBar(BarState.Off)
      }

      // Floating bottom center pill overlay (#CC1C1C1E, radius 30)
      Row({ space: 22 }) {
        Text('⊞')
          .fontSize(21)
          .fontColor('#FFB800')
          .onClick(() => {
            this.viewMode = 'grid';
          })

        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor('#000000')
            .border({ width: 3, color: '#FFB800' })
          Column()
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor('#FFFFFF')
        }
        .onClick(() => {
          this.viewMode = 'camera';
        })

        Text('💬')
          .fontSize(20)
          .onClick(() => {
            router.pushUrl({ url: 'pages/FriendsPage' });
          })
      }
      .height(60)
      .padding({ left: 22, right: 22 })
      .borderRadius(30)
      .backgroundColor('#CC1C1C1E')
      .border({ width: 1, color: '#2E2E30' })
      .margin({ bottom: 20 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      this.buildTopBar()

      if (this.viewMode === 'camera') {
        this.buildCameraMode()
      } else if (this.viewMode === 'feed') {
        this.buildFeedMode()
      } else {
        this.buildGridMode()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
