import { promptAction, router } from '@kit.ArkUI';
import { ChatMessage } from '../models/LocketModels';
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
  @State messages: ChatMessage[] = [];
  @State isLoading: boolean = true;
  @State inputText: string = '';
  @State isSending: boolean = false;

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
    }
    this.loadMessages();
  }

  private async loadMessages(): Promise<void> {
    if (this.friendUid.length === 0) {
      this.isLoading = false;
      return;
    }
    this.isLoading = true;
    try {
      this.messages = await LocketApiClient.getInstance().getMessagesWithUser(this.friendUid);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể tải tin nhắn';
      promptAction.showToast({ message: msg });
    } finally {
      this.isLoading = false;
    }
  }

  private async handleSend(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0 || this.friendUid.length === 0 || this.isSending) {
      return;
    }
    this.isSending = true;
    try {
      await LocketApiClient.getInstance().sendChatMessage(this.friendUid, text);
      this.inputText = '';
      const optimistic: ChatMessage = {
        id: `local_${Date.now()}`,
        senderUid: this.myUid,
        text: text,
        momentUid: '',
        createdAtMs: Date.now()
      };
      this.messages = [...this.messages, optimistic];
      await this.loadMessages();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Gửi tin nhắn thất bại';
      promptAction.showToast({ message: msg });
    } finally {
      this.isSending = false;
    }
  }

  private formatTime(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d = new Date(ms);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }

  build() {
    Column() {
      // Header
      Row() {
        Button('←')
          .width(42)
          .height(42)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor('#1C1C1E')
          .borderRadius(21)
          .onClick(() => {
            router.back();
          })

        if (this.friendAvatar.length > 0) {
          Image(this.friendAvatar)
            .width(38)
            .height(38)
            .borderRadius(19)
            .objectFit(ImageFit.Cover)
            .border({ width: 1.5, color: '#FFB800' })
            .margin({ left: 12 })
        } else {
          Column() {
            Text(this.friendName.length > 0 ? this.friendName.substring(0, 1).toUpperCase() : 'B')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .width(38)
          .height(38)
          .borderRadius(19)
          .backgroundColor('#262628')
          .border({ width: 1.5, color: '#FFB800' })
          .justifyContent(FlexAlign.Center)
          .margin({ left: 12 })
        }

        Text(this.friendName)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ left: 10 })
          .maxLines(1)

        Blank()

        Button('↻')
          .width(40)
          .height(40)
          .fontSize(18)
          .fontColor('#FFB800')
          .backgroundColor('#1C1C1E')
          .borderRadius(20)
          .onClick(() => {
            this.loadMessages();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })

      // Messages List
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
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.messages.length === 0) {
        Column() {
          Text('Chưa có tin nhắn nào')
            .fontSize(16)
            .fontWeight(FontWeight.SemiBold)
            .fontColor('#FFFFFF')
          Text('Hãy gửi lời chào tới bạn bè của bạn!')
            .fontSize(13)
            .fontColor('#8E8E93')
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.messages, (msg: ChatMessage) => {
            ListItem() {
              Row() {
                if (msg.senderUid === this.myUid) {
                  Blank()
                  Column() {
                    Text(msg.text)
                      .fontSize(15)
                      .fontColor('#000000')
                    if (msg.createdAtMs > 0) {
                      Text(this.formatTime(msg.createdAtMs))
                        .fontSize(10)
                        .fontColor('#4A3A00')
                        .margin({ top: 4 })
                    }
                  }
                  .alignItems(HorizontalAlign.End)
                  .padding({ left: 14, right: 14, top: 10, bottom: 8 })
                  .backgroundColor('#FFB800')
                  .borderRadius(20)
                  .constraintSize({ maxWidth: '78%' })
                } else {
                  Column() {
                    Text(msg.text)
                      .fontSize(15)
                      .fontColor('#FFFFFF')
                    if (msg.createdAtMs > 0) {
                      Text(this.formatTime(msg.createdAtMs))
                        .fontSize(10)
                        .fontColor('#8E8E93')
                        .margin({ top: 4 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 14, right: 14, top: 10, bottom: 8 })
                  .backgroundColor('#1C1C1E')
                  .border({ width: 1, color: '#2E2E30' })
                  .borderRadius(20)
                  .constraintSize({ maxWidth: '78%' })
                  Blank()
                }
              }
              .width('100%')
            }
          }, (msg: ChatMessage) => msg.id)
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }

      // Bottom Message Composer
      Row({ space: 8 }) {
        TextInput({
          placeholder: 'Gửi tin nhắn...',
          text: this.inputText
        })
          .layoutWeight(1)
          .height(48)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .placeholderColor('#8E8E93')
          .caretColor('#FFB800')
          .backgroundColor('#1C1C1E')
          .borderRadius(24)
          .border({ width: 1, color: '#2E2E30' })
          .padding({ left: 18, right: 18 })
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.handleSend();
          })

        Button(this.isSending ? '...' : '➤')
          .width(48)
          .height(48)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.inputText.trim().length > 0 && !this.isSending ? '#000000' : '#8E8E93')
          .backgroundColor(this.inputText.trim().length > 0 && !this.isSending ? '#FFB800' : '#1C1C1E')
          .borderRadius(24)
          .enabled(!this.isSending && this.inputText.trim().length > 0)
          .onClick(() => {
            this.handleSend();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
