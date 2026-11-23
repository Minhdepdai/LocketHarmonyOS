import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { FriendItem, getDisplayName, UploadMomentOptions } from '../models/LocketModels';
import { LiveCameraController } from '../services/LiveCameraController';
import { LocketApiClient } from '../services/LocketApiClient';

interface CameraRouteParams {
  capturedPhotoPath?: string;
}

@Entry
@Component
struct CameraPage {
  @State selectedPhotoUri: string = '';
  @State caption: string = '';
  @State sendToAll: boolean = true;
  @State friends: FriendItem[] = [];
  @State selectedFriendUids: string[] = [];
  @State isLoadingFriends: boolean = false;
  @State isUploading: boolean = false;
  @State isFrontCamera: boolean = false;
  @State isCameraReady: boolean = false;
  @State isCapturing: boolean = false;
  private cameraSurfaceId: string = '';
  private xComponentController: XComponentController = new XComponentController();
  private liveCamera: LiveCameraController = new LiveCameraController();

  aboutToAppear(): void {
    const params = router.getParams() as CameraRouteParams | undefined;
    if (params !== undefined && params.capturedPhotoPath !== undefined && params.capturedPhotoPath.length > 0) {
      this.selectedPhotoUri = params.capturedPhotoPath;
    }
    this.loadFriends();
  }

  onPageShow(): void {
    if (this.selectedPhotoUri.length === 0 && this.cameraSurfaceId.length > 0 && !this.liveCamera.isSessionRunning()) {
      this.startLiveCamera();
    }
  }

  onPageHide(): void {
    this.stopLiveCamera();
  }

  aboutToDisappear(): void {
    this.stopLiveCamera();
  }

  private async startLiveCamera(): Promise<void> {
    if (this.cameraSurfaceId.length === 0) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const started = await this.liveCamera.startSession(context, this.cameraSurfaceId, this.isFrontCamera);
    this.isCameraReady = started;
  }

  private async stopLiveCamera(): Promise<void> {
    this.isCameraReady = false;
    await this.liveCamera.release();
  }

  private async flipCamera(): Promise<void> {
    this.isFrontCamera = !this.isFrontCamera;
    if (this.selectedPhotoUri.length === 0 && this.cameraSurfaceId.length > 0) {
      await this.startLiveCamera();
    }
    promptAction.showToast({ message: this.isFrontCamera ? 'Đã chuyển camera trước' : 'Đã chuyển camera sau' });
  }

  private async loadFriends(): Promise<void> {
    this.isLoadingFriends = true;
    try {
      this.friends = await LocketApiClient.getInstance().getAllFriends();
    } catch (_err) {
      // Friends list can fail silently when defaulting to sendToAll
    } finally {
      this.isLoadingFriends = false;
    }
  }

  private async pickFromGallery(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        await this.stopLiveCamera();
        this.selectedPhotoUri = result.photoUris[0];
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể mở thư viện ảnh';
      promptAction.showToast({ message: msg });
    }
  }

  private async captureFromCamera(): Promise<void> {
    if (this.isCapturing) {
      return;
    }
    if (!this.isCameraReady) {
      await this.startLiveCamera();
      if (!this.isCameraReady) {
        promptAction.showToast({ message: 'Vui lòng cấp quyền camera để chụp ảnh' });
        return;
      }
    }
    this.isCapturing = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const filePath = await this.liveCamera.capturePhotoToFile(context);
      await this.stopLiveCamera();
      this.selectedPhotoUri = filePath;
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể chụp ảnh';
      promptAction.showToast({ message: msg });
    } finally {
      this.isCapturing = false;
    }
  }

  private getDisplayPhotoSrc(): string {
    if (this.selectedPhotoUri.startsWith('/')) {
      return `file://${this.selectedPhotoUri}`;
    }
    return this.selectedPhotoUri;
  }

  private toggleFriendSelection(uid: string): void {
    if (this.selectedFriendUids.includes(uid)) {
      this.selectedFriendUids = this.selectedFriendUids.filter((id: string) => id !== uid);
    } else {
      this.selectedFriendUids = [...this.selectedFriendUids, uid];
    }
  }

  private readUriBytes(uri: string): ArrayBuffer {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      return buffer;
    } finally {
      fileIo.closeSync(file);
    }
  }

  private detectContentType(uri: string): string {
    const lower = uri.toLowerCase();
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  private async handlePostMoment(): Promise<void> {
    if (this.selectedPhotoUri.length === 0) {
      promptAction.showToast({ message: 'Vui lòng chọn hoặc chụp ảnh trước' });
      return;
    }
    if (!this.sendToAll && this.selectedFriendUids.length === 0) {
      promptAction.showToast({ message: 'Vui lòng chọn ít nhất một người bạn' });
      return;
    }
    this.isUploading = true;
    try {
      const bytes = this.readUriBytes(this.selectedPhotoUri);
      const options: UploadMomentOptions = {
        caption: this.caption.trim(),
        recipients: this.sendToAll ? [] : this.selectedFriendUids,
        sentToAll: this.sendToAll,
        contentType: this.detectContentType(this.selectedPhotoUri)
      };
      await LocketApiClient.getInstance().uploadAndPostPhotoMoment(bytes, options);
      promptAction.showToast({ message: 'Đã đăng khoảnh khắc thành công!' });
      router.replaceUrl({ url: 'pages/HomePage' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Đăng ảnh thất bại';
      promptAction.showToast({ message: msg });
    } finally {
      this.isUploading = false;
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Button('←')
          .width(44)
          .height(44)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor('#1C1C1E')
          .borderRadius(22)
          .onClick(() => {
            router.back();
          })

        Text('Gửi đến...')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ left: 14 })

        Blank()

        if (this.selectedPhotoUri.length === 0) {
          Button('🔄')
            .width(44)
            .height(44)
            .fontSize(18)
            .fontColor('#FFFFFF')
            .backgroundColor('#1C1C1E')
            .borderRadius(22)
            .onClick(() => {
              this.flipCamera();
            })
        } else {
          Button('Chụp lại')
            .height(36)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFB800')
            .backgroundColor('#1C1C1E')
            .borderRadius(18)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.selectedPhotoUri = '';
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })

      Scroll() {
        Column({ space: 14 }) {
          // 1:1 Square Viewfinder / Preview with Locket 48vp rounded corners
          Stack({ alignContent: Alignment.Bottom }) {
            if (this.selectedPhotoUri.length > 0) {
              Image(this.getDisplayPhotoSrc())
                .width('100%')
                .aspectRatio(1)
                .objectFit(ImageFit.Cover)
                .borderRadius(48)
                .backgroundColor('#141416')
            } else {
              Stack({ alignContent: Alignment.Center }) {
                XComponent({
                  id: 'locket_camera_page_preview',
                  type: XComponentType.SURFACE,
                  controller: this.xComponentController
                })
                  .onLoad(() => {
                    this.cameraSurfaceId = this.xComponentController.getXComponentSurfaceId();
                    this.startLiveCamera();
                  })
                  .onDestroy(() => {
                    this.stopLiveCamera();
                  })
                  .width('100%')
                  .aspectRatio(1)
                  .borderRadius(48)
                  .clip(true)

                if (!this.isCameraReady) {
                  Column({ space: 8 }) {
                    Text('📷')
                      .fontSize(40)
                    Text('Đang khởi động camera...')
                      .fontSize(13)
                      .fontColor('#8E8E93')
                  }
                  .width('100%')
                  .aspectRatio(1)
                  .backgroundColor('#141416')
                  .borderRadius(48)
                  .border({ width: 1, color: '#2E2E30' })
                  .justifyContent(FlexAlign.Center)
                }
              }
              .width('100%')
              .aspectRatio(1)
              .borderRadius(48)
              .clip(true)
            }

            if (this.selectedPhotoUri.length > 0 && this.caption.trim().length > 0) {
              Text(this.caption)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor('#993A3A3C')
                .borderRadius(20)
                .margin({ bottom: 16, left: 20, right: 20 })
            }
          }
          .width('100%')

          // Pick / Capture Action Row
          Row({ space: 10 }) {
            Button(this.isCapturing ? 'Đang chụp...' : 'Chụp ảnh')
              .layoutWeight(1)
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#000000')
              .backgroundColor('#FFB800')
              .borderRadius(24)
              .enabled(!this.isCapturing)
              .onClick(() => {
                if (this.selectedPhotoUri.length > 0) {
                  this.selectedPhotoUri = '';
                } else {
                  this.captureFromCamera();
                }
              })

            Button('Thư viện ảnh')
              .layoutWeight(1)
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor('#1C1C1E')
              .borderRadius(24)
              .border({ width: 1, color: '#2E2E30' })
              .onClick(() => {
                this.pickFromGallery();
              })
          }
          .width('100%')

          // Caption Input
          TextInput({
            placeholder: 'Thêm tin nhắn...',
            text: this.caption
          })
            .width('100%')
            .height(50)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .placeholderColor('#8E8E93')
            .caretColor('#FFB800')
            .backgroundColor('#1C1C1E')
            .borderRadius(25)
            .border({ width: 1, color: '#2E2E30' })
            .padding({ left: 18, right: 18 })
            .onChange((value: string) => {
              this.caption = value;
            })

          // Audience Toggle
          Row() {
            Text(this.sendToAll ? 'Gửi tới: Tất cả bạn bè' : `Gửi tới: ${this.selectedFriendUids.length} bạn đã chọn`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')

            Blank()

            Toggle({ type: ToggleType.Switch, isOn: this.sendToAll })
              .selectedColor('#FFB800')
              .onChange((isOn: boolean) => {
                this.sendToAll = isOn;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor('#1C1C1E')
          .borderRadius(18)
          .border({ width: 1, color: '#2E2E30' })

          // Friend Selector List when not sending to all
          if (!this.sendToAll) {
            if (this.isLoadingFriends) {
              LoadingProgress()
                .width(32)
                .height(32)
                .color('#FFB800')
            } else {
              Column({ space: 8 }) {
                ForEach(this.friends, (friend: FriendItem) => {
                  Row() {
                    Text(getDisplayName(friend))
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#FFFFFF')
                    Blank()
                    Text(this.selectedFriendUids.includes(friend.uid) ? '✓ Đã chọn' : 'Chọn')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.selectedFriendUids.includes(friend.uid) ? '#FFB800' : '#8E8E93')
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .backgroundColor(this.selectedFriendUids.includes(friend.uid) ? '#262628' : '#1C1C1E')
                  .borderRadius(16)
                  .border({
                    width: 1,
                    color: this.selectedFriendUids.includes(friend.uid) ? '#FFB800' : '#2E2E30'
                  })
                  .onClick(() => {
                    this.toggleFriendSelection(friend.uid);
                  })
                }, (friend: FriendItem) => friend.uid)
              }
              .width('100%')
            }
          }

          // Post Button
          Button(this.isUploading ? 'Đang tải lên...' : 'Gửi Locket ➤')
            .width('100%')
            .height(54)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedPhotoUri.length > 0 && !this.isUploading ? '#000000' : '#8E8E93')
            .backgroundColor(this.selectedPhotoUri.length > 0 && !this.isUploading ? '#FFB800' : '#1C1C1E')
            .borderRadius(27)
            .enabled(!this.isUploading && this.selectedPhotoUri.length > 0)
            .margin({ top: 6, bottom: 28 })
            .onClick(() => {
              this.handlePostMoment();
            })
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
