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
  @State showPostSuccess: boolean = false;
  @State successScale: number = 0.5;
  @State isFrontCamera: boolean = false;
  @State isCameraReady: boolean = false;
  @State isCapturing: boolean = false;
  @State zoomRatio: number = 1.0;
  @State shutterScale: number = 1.0;
  @State postBtnScale: number = 1.0;
  @State photoCardScale: number = 1.0;
  @State photoCardX: number = 0;
  @State photoCardY: number = 0;
  @State photoCardOpacity: number = 1.0;
  @State galleryPulseScale: number = 1.0;
  @StorageProp('safe_top_vp') safeTopVp: number = 38;
  @StorageProp('safe_bottom_vp') safeBottomVp: number = 20;
  private pinchStartZoom: number = 1.0;
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

  private handleShutterTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.shutterScale = 0.92;
      });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.shutterScale = 1.0;
      });
    }
  }

  private handlePostBtnTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.postBtnScale = 0.92;
      });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.postBtnScale = 1.0;
      });
    }
  }

  private async startLiveCamera(): Promise<void> {
    if (this.cameraSurfaceId.length === 0) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const started = await this.liveCamera.startSession(context, this.cameraSurfaceId, this.isFrontCamera);
    this.isCameraReady = started;
    this.zoomRatio = this.liveCamera.currentZoomRatio;
  }

  private async stopLiveCamera(): Promise<void> {
    this.isCameraReady = false;
    this.zoomRatio = 1.0;
    await this.liveCamera.release();
  }

  private formatZoomLabel(): string {
    const rounded = Math.round(this.zoomRatio * 10) / 10;
    if (Math.abs(rounded - Math.round(rounded)) < 0.05) {
      return `${Math.round(rounded)}x`;
    }
    return `${rounded.toFixed(1)}x`;
  }

  private toggleZoom(): void {
    const nextZoom = this.zoomRatio < 1.5 ? 2.0 : 1.0;
    this.zoomRatio = this.liveCamera.setZoomRatio(nextZoom);
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
    this.showPostSuccess = false;
    this.successScale = 0.5;
    try {
      const bytes = this.readUriBytes(this.selectedPhotoUri);
      const options: UploadMomentOptions = {
        caption: this.caption.trim(),
        recipients: this.sendToAll ? [] : this.selectedFriendUids,
        sentToAll: this.sendToAll,
        contentType: this.detectContentType(this.selectedPhotoUri)
      };
      await LocketApiClient.getInstance().uploadAndPostPhotoMoment(bytes, options);
      this.isUploading = false;

      // Animate 1:1 photo card shrinking & flying down-left toward Gallery button
      animateTo({ duration: 380, curve: Curve.EaseInOut }, () => {
        this.photoCardScale = 0.14;
        this.photoCardX = -115;
        this.photoCardY = 250;
        this.photoCardOpacity = 0;
      });
      setTimeout(() => {
        animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
          this.galleryPulseScale = 1.18;
        });
        setTimeout(() => {
          animateTo({ duration: 150, curve: Curve.EaseInOut }, () => {
            this.galleryPulseScale = 1.0;
          });
        }, 150);
      }, 280);

      setTimeout(() => {
        this.showPostSuccess = true;
        animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
          this.successScale = 1.0;
        });
        setTimeout(() => {
          this.showPostSuccess = false;
          router.replaceUrl({ url: 'pages/HomePage' });
        }, 700);
      }, 380);
    } catch (err) {
      this.isUploading = false;
      const msg = err instanceof Error ? err.message : 'Đăng ảnh thất bại';
      promptAction.showToast({ message: msg });
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        // Header
        Row() {
          Column() {
            Image($r('app.media.ic_back'))
              .width(20)
              .height(20)
              .fillColor('#FFFFFF')
          }
          .width(40)
          .height(40)
          .backgroundColor('#1C1C1E')
          .borderRadius(20)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            router.back();
          })

          Text('Gửi đến...')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ left: 12 })

          Blank()

          if (this.selectedPhotoUri.length === 0) {
            Column() {
              Image($r('app.media.ic_flip_camera'))
                .width(20)
                .height(20)
                .fillColor('#FFFFFF')
            }
            .width(40)
            .height(40)
            .backgroundColor('#1C1C1E')
            .borderRadius(20)
            .justifyContent(FlexAlign.Center)
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
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        Scroll() {
          Column({ space: 14 }) {
            // 1:1 Square Viewfinder / Preview with balanced 88% (max 340vp) & 40vp rounded corners
            Stack({ alignContent: Alignment.Bottom }) {
              if (this.selectedPhotoUri.length > 0) {
                Image(this.getDisplayPhotoSrc())
                  .width('100%')
                  .aspectRatio(1)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(40)
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
                    .borderRadius(40)
                    .clip(true)

                  if (!this.isCameraReady) {
                    Column({ space: 10 }) {
                      Image($r('app.media.ic_heart_locket'))
                        .width(40)
                        .height(40)
                        .fillColor('#FFB800')
                      Text('Đang khởi động camera...')
                        .fontSize(13)
                        .fontColor('#8E8E93')
                    }
                    .width('100%')
                    .aspectRatio(1)
                    .backgroundColor('#141416')
                    .borderRadius(40)
                    .border({ width: 1, color: '#2E2E30' })
                    .justifyContent(FlexAlign.Center)
                  }
                }
                .width('100%')
                .aspectRatio(1)
                .borderRadius(40)
                .clip(true)
              }

              if (this.selectedPhotoUri.length === 0) {
                Row() {
                  Text(this.formatZoomLabel())
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFB800')
                }
                .height(32)
                .padding({ left: 14, right: 14 })
                .borderRadius(16)
                .backgroundColor('#991C1C1E')
                .border({ width: 1, color: '#44FFFFFF' })
                .justifyContent(FlexAlign.Center)
                .margin({ bottom: 14 })
                .onClick(() => {
                  this.toggleZoom();
                })
              }

              if (this.selectedPhotoUri.length > 0 && this.caption.trim().length > 0) {
                Text(this.caption)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .backgroundColor('#993A3A3C')
                  .borderRadius(20)
                  .margin({ bottom: 14, left: 20, right: 20 })
              }
            }
            .width('88%')
            .constraintSize({ maxWidth: 340 })
            .scale({ x: this.photoCardScale, y: this.photoCardScale })
            .translate({ x: this.photoCardX, y: this.photoCardY })
            .opacity(this.photoCardOpacity)
            .gesture(
              PinchGesture()
                .onActionStart(() => {
                  this.pinchStartZoom = this.zoomRatio;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.selectedPhotoUri.length === 0) {
                    this.zoomRatio = this.liveCamera.setZoomRatio(this.pinchStartZoom * event.scale);
                  }
                })
            )

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
                .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
                .scale({ x: this.shutterScale, y: this.shutterScale })
                .enabled(!this.isCapturing)
                .onTouch((event: TouchEvent) => {
                  this.handleShutterTouch(event);
                })
                .onClick(() => {
                  if (this.selectedPhotoUri.length > 0) {
                    this.selectedPhotoUri = '';
                  } else {
                    this.captureFromCamera();
                  }
                })

              Row({ space: 8 }) {
                Image($r('app.media.ic_gallery'))
                  .width(18)
                  .height(18)
                  .fillColor('#FFFFFF')
                Text('Thư viện ảnh')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
              }
              .layoutWeight(1)
              .height(48)
              .backgroundColor('#1C1C1E')
              .borderRadius(24)
              .border({ width: 1, color: '#2E2E30' })
              .scale({ x: this.galleryPulseScale, y: this.galleryPulseScale })
              .justifyContent(FlexAlign.Center)
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

            // Post Button with Golden Glow + Press-Scale + SVG Send Icon
            Row({ space: 10 }) {
              Text(this.isUploading ? 'Đang tải lên...' : 'Đăng ngay')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.selectedPhotoUri.length > 0 && !this.isUploading ? '#000000' : '#8E8E93')

              if (!this.isUploading) {
                Image($r('app.media.ic_send'))
                  .width(18)
                  .height(18)
                  .fillColor(this.selectedPhotoUri.length > 0 ? '#000000' : '#8E8E93')
              }
            }
            .width('100%')
            .height(54)
            .backgroundColor(this.selectedPhotoUri.length > 0 && !this.isUploading ? '#FFB800' : '#1C1C1E')
            .borderRadius(27)
            .shadow(this.selectedPhotoUri.length > 0 && !this.isUploading
              ? { radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 }
              : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
            .scale({ x: this.postBtnScale, y: this.postBtnScale })
            .justifyContent(FlexAlign.Center)
            .enabled(!this.isUploading && this.selectedPhotoUri.length > 0)
            .margin({ top: 6, bottom: 28 })
            .onTouch((event: TouchEvent) => {
              if (this.selectedPhotoUri.length > 0 && !this.isUploading) {
                this.handlePostBtnTouch(event);
              }
            })
            .onClick(() => {
              this.handlePostMoment();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeTopVp, bottom: this.safeBottomVp })
      .backgroundColor('#000000')

      // Animated Uploading & Post-Success Overlay
      if (this.isUploading || this.showPostSuccess) {
        Column({ space: 18 }) {
          if (this.isUploading) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(88)
                .height(88)
                .borderRadius(44)
                .backgroundColor('#1C1C1E')
                .border({ width: 3, color: '#FFB800' })
                .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })

              LoadingProgress()
                .width(56)
                .height(56)
                .color('#FFB800')
            }

            Text('Đang đăng khoảnh khắc...')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          } else {
            Column() {
              Text('✓')
                .fontSize(42)
                .fontWeight(FontWeight.Bold)
                .fontColor('#000000')
            }
            .width(88)
            .height(88)
            .borderRadius(44)
            .backgroundColor('#FFB800')
            .shadow({ radius: 28, color: '#88FFB800', offsetX: 0, offsetY: 4 })
            .justifyContent(FlexAlign.Center)
            .scale({ x: this.successScale, y: this.successScale })

            Text('Đã đăng thành công!')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFB800')
              .scale({ x: this.successScale, y: this.successScale })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#D9000000')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
