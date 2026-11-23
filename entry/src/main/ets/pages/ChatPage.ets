import { curves, promptAction, router } from '@kit.ArkUI';
import { ChatMessage } from '../models/LocketModels';
import { CacheService } from '../services/CacheService';
import { LocketApiClient } from '../services/LocketApiClient';
import { SessionManager } from '../services/SessionManager';

interface ChatRouteParams {
  friendUid?: string;
  friendName?: string;
  friendAvatar?: string;
}

@Entry
@Component
struct ChatPage {
  @State friendUid: string = '';
  @State friendName: string = 'Bạn bè';
  @State friendAvatar: string = '';
  @State myUid: string = '';
  @State myName: string = 'Bạn';
  @State myAvatar: string = '';
  @State messages: ChatMessage[] = [];
  @State isLoading: boolean = true;
  @State inputText: string = '';
  @State isSending: boolean = false;
  @State pressedButtonId: string = '';
  @StorageProp('safe_top_vp') safeTopVp: number = 38;
  @StorageProp('safe_bottom_vp') safeBottomVp: number = 20;
  private listScroller: Scroller = new Scroller();

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
    const params = router.getParams() as ChatRouteParams | undefined;
    if (params !== undefined) {
      this.friendUid = params.friendUid ?? '';
      this.friendName = params.friendName ?? 'Bạn bè';
      this.friendAvatar = params.friendAvatar ?? '';
    }
    const session = SessionManager.getInstance().getSession();
    if (session !== null) {
      this.myUid = session.localId;
      if (session.displayName.length > 0) {
        this.myName = session.displayName;
      }
      this.loadMyProfile(session.localId);
    }
    if (this.friendUid.length > 0) {
      const cached = CacheService.getInstance().getCachedMessages(this.friendUid);
      if (cached.length > 0) {
        this.messages = cached;
        this.isLoading = false;
        this.scrollToBottom(false);
      }
    }
    this.loadMessages();
  }

  private async loadMyProfile(uid: string): Promise<void> {
    try {
      const me = await LocketApiClient.getInstance().fetchUser(uid);
      const full = `${me.firstName} ${me.lastName}`.trim();
      if (full.length > 0) {
        this.myName = full;
      } else if (me.username.length > 0) {
        this.myName = me.username;
      }
      this.myAvatar = me.profilePictureUrl;
    } catch (_err) {
      // Non-critical
    }
  }

  private scrollToBottom(animated: boolean = false): void {
    if (this.messages.length > 0) {
      setTimeout(() => {
        try {
          this.listScroller.scrollToIndex(this.messages.length - 1, animated, ScrollAlign.END);
        } catch (_err) {
          this.listScroller.scrollEdge(Edge.Bottom);
        }
      }, 60);
    }
  }

  private async loadMessages(): Promise<void> {
    if (this.friendUid.length === 0) {
      this.isLoading = false;
      return;
    }
    const hasCached = this.messages.length > 0;
    if (!hasCached) {
      this.isLoading = true;
    }
    try {
      const fresh = await LocketApiClient.getInstance().getMessagesWithUser(this.friendUid);
      this.messages = fresh;
      CacheService.getInstance().saveMessages(this.friendUid, fresh);
    } catch (err) {
      if (!hasCached) {
        const msg = err instanceof Error ? err.message : 'Không thể tải tin nhắn';
        promptAction.showToast({ message: msg });
      }
    } finally {
      this.isLoading = false;
      this.scrollToBottom(false);
    }
  }

  private async handleSendText(textToSend: string): Promise<void> {
    const text = textToSend.trim();
    if (text.length === 0 || this.friendUid.length === 0 || this.isSending) {
      return;
    }
    this.isSending = true;
    try {
      await LocketApiClient.getInstance().sendChatMessage(this.friendUid, text);
      if (textToSend === this.inputText) {
        this.inputText = '';
      }
      const optimistic: ChatMessage = {
        id: `local_${Date.now()}`,
        senderUid: this.myUid,
        text: text,
        momentUid: '',
        createdAtMs: Date.now()
      };
      this.messages = [...this.messages, optimistic];
      this.scrollToBottom(true);
      await this.loadMessages();
      this.scrollToBottom(true);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Gửi tin nhắn thất bại';
      promptAction.showToast({ message: msg });
    } finally {
      this.isSending = false;
    }
  }

  private formatVietnameseDate(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d = new Date(ms);
    return `Ngày ${d.getDate()} tháng ${d.getMonth() + 1}`;
  }

  private hasDisplayText(msg: ChatMessage): boolean {
    const cleaned = msg.text.replace(/\u200b/g, '').trim();
    return cleaned.length > 0;
  }

  private getDisplayText(msg: ChatMessage): string {
    return msg.text.replace(/\u200b/g, '').trim();
  }

  private getCardAuthorName(msg: ChatMessage): string {
    return msg.senderUid === this.myUid ? this.myName : this.friendName;
  }

  private getCardAuthorAvatar(msg: ChatMessage): string {
    return msg.senderUid === this.myUid ? this.myAvatar : this.friendAvatar;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Full-bleed Messages List scrolling underneath top header & bottom composer
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(38)
            .height(38)
            .color('#FFB800')
          Text('Đang tải cuộc trò chuyện...')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ top: 10 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.messages.length === 0) {
        Column() {
          Text('Chưa có tin nhắn nào')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Text('Hãy gửi lời chào tới bạn bè của bạn!')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ top: 6 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10, scroller: this.listScroller }) {
          ForEach(this.messages, (msg: ChatMessage) => {
            ListItem() {
              Column({ space: 8 }) {
                // Large 1:1 Replied Moment Photo Card with translucent dark top-left badge
                if (msg.thumbnailUrl !== undefined && msg.thumbnailUrl.length > 0) {
                  Stack({ alignContent: Alignment.TopStart }) {
                    Image(msg.thumbnailUrl)
                      .width('100%')
                      .aspectRatio(1)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(44)
                      .backgroundColor('#141416')

                    Row({ space: 8 }) {
                      if (this.getCardAuthorAvatar(msg).length > 0) {
                        Image(this.getCardAuthorAvatar(msg))
                          .width(24)
                          .height(24)
                          .borderRadius(12)
                          .objectFit(ImageFit.Cover)
                      } else {
                        Column() {
                          Text(this.getCardAuthorName(msg).substring(0, 1).toUpperCase())
                            .fontSize(11)
                            .fontWeight(FontWeight.Bold)
                            .fontColor('#FFFFFF')
                        }
                        .width(24)
                        .height(24)
                        .borderRadius(12)
                        .backgroundColor('#3A3A3C')
                        .justifyContent(FlexAlign.Center)
                      }

                      Text(this.getCardAuthorName(msg))
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                        .maxLines(1)

                      if (msg.createdAtMs > 0) {
                        Text(this.formatVietnameseDate(msg.createdAtMs))
                          .fontSize(12)
                          .fontColor('#D1D1D6')
                          .maxLines(1)
                      }
                    }
                    .padding({ left: 8, right: 12, top: 6, bottom: 6 })
                    .borderRadius(20)
                    .backgroundColor('#991C1C1E')
                    .margin({ top: 16, left: 16 })
                  }
                  .width('100%')
                  .padding({ left: 4, right: 4 })
                }

                // Text message bubble
                if (this.hasDisplayText(msg)) {
                  Row() {
                    if (msg.senderUid === this.myUid) {
                      Blank()
                      Column() {
                        Text(this.getDisplayText(msg))
                          .fontSize(17)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#000000')
                      }
                      .alignItems(HorizontalAlign.End)
                      .padding({ left: 18, right: 18, top: 12, bottom: 12 })
                      .backgroundColor('#F2F2F7')
                      .borderRadius(24)
                      .constraintSize({ maxWidth: '80%' })
                    } else {
                      Column() {
                        Text(this.getDisplayText(msg))
                          .fontSize(17)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#FFFFFF')
                      }
                      .alignItems(HorizontalAlign.Start)
                      .padding({ left: 18, right: 18, top: 12, bottom: 12 })
                      .backgroundColor('#262628')
                      .borderRadius(24)
                      .constraintSize({ maxWidth: '80%' })
                      Blank()
                    }
                  }
                  .width('100%')
                  .padding({ left: 4, right: 4 })
                }
              }
              .width('100%')
            }
          }, (msg: ChatMessage) => msg.id)
        }
        .width('100%')
        .height('100%')
        .padding({
          top: this.safeTopVp + 66,
          bottom: this.safeBottomVp + 78,
          left: 12,
          right: 12
        })
        .scrollBar(BarState.Off)
      }

      // Top-down Smooth 4-stop Gradient Scrim (no full-width backdropBlur)
      Column()
        .width('100%')
        .height(this.safeTopVp + 76)
        .hitTestBehavior(HitTestMode.Transparent)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#F5000000', 0], ['#CC000000', 0.45], ['#59000000', 0.78], ['#00000000', 1]]
        })

      // Header Controls Row (backdropBlur only on circular pills)
      Row() {
        Column() {
          Image($r('app.media.ic_back'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF')
        }
        .width(42)
        .height(42)
        .backgroundColor('#CC1C1C1E')
        .backdropBlur(16)
        .borderRadius(21)
        .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
        .scale(this.pressedButtonId === 'chat_back' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('chat_back', e);
        })
        .onClick(() => {
          router.back();
        })

        if (this.friendAvatar.length > 0) {
          Image(this.friendAvatar)
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .border({ width: 1.5, color: '#2C2C2E' })
            .margin({ left: 12 })
        } else {
          Column() {
            Text(this.friendName.length > 0 ? this.friendName.substring(0, 1).toUpperCase() : 'B')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor('#262628')
          .border({ width: 1.5, color: '#2C2C2E' })
          .justifyContent(FlexAlign.Center)
          .margin({ left: 12 })
        }

        Text(this.friendName)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ left: 10 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Column() {
          Image($r('app.media.ic_flip_camera'))
            .width(18)
            .height(18)
            .fillColor('#FFB800')
        }
        .width(40)
        .height(40)
        .backgroundColor('#CC1C1C1E')
        .backdropBlur(16)
        .borderRadius(20)
        .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
        .scale(this.pressedButtonId === 'chat_refresh' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('chat_refresh', e);
        })
        .onClick(() => {
          this.loadMessages();
        })
      }
      .width('100%')
      .padding({ top: this.safeTopVp + 8, bottom: 14, left: 16, right: 16 })
      .hitTestBehavior(HitTestMode.Transparent)

      // Bottom-up Smooth 4-stop Fade + Frosted Pill Composer Overlay
      Column() {
        Column() {
          Row({ space: 6 }) {
            TextInput({
              placeholder: 'Gửi tin nhắn...',
              text: this.inputText
            })
              .layoutWeight(1)
              .height(48)
              .fontSize(16)
              .fontColor('#FFFFFF')
              .placeholderColor('#8E8E93')
              .caretColor('#FFB800')
              .backgroundColor(Color.Transparent)
              .padding({ left: 12, right: 6 })
              .onChange((value: string) => {
                this.inputText = value;
              })
              .onSubmit(() => {
                this.handleSendText(this.inputText);
              })

            if (this.inputText.trim().length > 0) {
              Column() {
                if (this.isSending) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color('#000000')
                } else {
                  Image($r('app.media.ic_send'))
                    .width(18)
                    .height(18)
                    .fillColor('#000000')
                }
              }
              .width(42)
              .height(42)
              .backgroundColor('#FFB800')
              .borderRadius(21)
              .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
              .scale(this.pressedButtonId === 'chat_send' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
              .justifyContent(FlexAlign.Center)
              .enabled(!this.isSending)
              .onTouch((e: TouchEvent) => {
                this.handleButtonTouch('chat_send', e);
              })
              .onClick(() => {
                this.handleSendText(this.inputText);
              })
            } else {
              Text('💛')
                .fontSize(22)
                .padding({ left: 4, right: 4 })
                .scale(this.pressedButtonId === 'chat_react_heart' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
                .onTouch((e: TouchEvent) => {
                  this.handleButtonTouch('chat_react_heart', e);
                })
                .onClick(() => {
                  this.handleSendText('💛');
                })
              Text('🔥')
                .fontSize(22)
                .padding({ left: 4, right: 4 })
                .scale(this.pressedButtonId === 'chat_react_fire' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
                .onTouch((e: TouchEvent) => {
                  this.handleButtonTouch('chat_react_fire', e);
                })
                .onClick(() => {
                  this.handleSendText('🔥');
                })
              Text('😍')
                .fontSize(22)
                .padding({ left: 4, right: 4 })
                .scale(this.pressedButtonId === 'chat_react_love' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
                .onTouch((e: TouchEvent) => {
                  this.handleButtonTouch('chat_react_love', e);
                })
                .onClick(() => {
                  this.handleSendText('😍');
                })
              Column() {
                Image($r('app.media.ic_emoji_add'))
                  .width(20)
                  .height(20)
                  .fillColor('#FFFFFF')
              }
              .width(34)
              .height(34)
              .justifyContent(FlexAlign.Center)
              .scale(this.pressedButtonId === 'chat_react_more' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
              .onTouch((e: TouchEvent) => {
                this.handleButtonTouch('chat_react_more', e);
              })
              .onClick(() => {
                this.handleSendText('😂');
              })
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 10, right: 10 })
          .backgroundColor('#CC1C1C1E')
          .backdropBlur(16)
          .borderRadius(28)
          .border({ width: 1, color: '#2E2E30' })
          .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 24, bottom: this.safeBottomVp + 14 })
        .hitTestBehavior(HitTestMode.Transparent)
        .linearGradient({
          direction: GradientDirection.Top,
          colors: [['#F5000000', 0], ['#CC000000', 0.45], ['#59000000', 0.78], ['#00000000', 1]]
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
