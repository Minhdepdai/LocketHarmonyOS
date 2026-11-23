import { curves, promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
  @State pressedButtonId: string = '';
  @State captionStyleIndex: number = 0;
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

  private handleShutterTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      animateTo({ curve: curves.springMotion(0.35, 0.65) }, () => {
        this.shutterScale = 0.91;
      });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      animateTo({ curve: curves.springMotion(0.45, 0.72) }, () => {
        this.shutterScale = 1.0;
      });
    }
  }

  private handlePostBtnTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      animateTo({ curve: curves.springMotion(0.35, 0.65) }, () => {
        this.postBtnScale = 0.91;
      });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      animateTo({ curve: curves.springMotion(0.45, 0.72) }, () => {
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
    await this.stopLiveCamera();
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        this.selectedPhotoUri = result.photoUris[0];
        return;
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể mở thư viện ảnh';
      promptAction.showToast({ message: msg });
    }
    if (this.selectedPhotoUri.length === 0 && this.cameraSurfaceId.length > 0) {
      this.startLiveCamera();
    }
  }

  private async captureFromCamera(): Promise<void> {
    if (this.isCapturing) {
      return;
    }
    const logDomain = 0x0000;
    const logTag = 'LocketCamera';
    const context = getContext(this) as common.UIAbilityContext;
    if (!this.isCameraReady) {
      hilog.info(logDomain, logTag, '%{public}s', 'CameraPage captureFromCamera: starting live camera first');
      await this.startLiveCamera();
    }
    if (!this.isCameraReady) {
      hilog.error(logDomain, logTag, '%{public}s', 'CameraPage captureFromCamera: camera session not ready');
      promptAction.showToast({ message: 'Camera chưa sẵn sàng, vui lòng thử lại' });
      return;
    }
    this.isCapturing = true;
    try {
      hilog.info(logDomain, logTag, '%{public}s', 'CameraPage captureFromCamera: capturing photo in-app');
      const filePath = await this.liveCamera.capturePhotoToFile(context);
      await this.stopLiveCamera();

      if (filePath.length > 0) {
        this.selectedPhotoUri = filePath;
      } else {
        promptAction.showToast({ message: 'Không thể đọc dữ liệu ảnh' });
        if (this.selectedPhotoUri.length === 0 && this.cameraSurfaceId.length > 0) {
          this.startLiveCamera();
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể chụp ảnh';
      hilog.error(logDomain, logTag, '%{public}s', `CameraPage captureFromCamera error: ${msg}`);
      promptAction.showToast({ message: msg });
      if (this.selectedPhotoUri.length === 0 && this.cameraSurfaceId.length > 0 && !this.liveCamera.isSessionRunning()) {
        this.isCameraReady = false;
        this.zoomRatio = 1.0;
        this.startLiveCamera();
      }
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
    if (this.sendToAll) {
      this.sendToAll = false;
      this.selectedFriendUids = [uid];
      return;
    }
    if (this.selectedFriendUids.includes(uid)) {
      const next = this.selectedFriendUids.filter((id: string) => id !== uid);
      this.selectedFriendUids = next;
      if (next.length === 0) {
        this.sendToAll = true;
      }
    } else {
      this.selectedFriendUids = [...this.selectedFriendUids, uid];
    }
  }

  private getFriendShortName(friend: FriendItem): string {
    const first = friend.firstName.trim();
    if (first.length > 0) {
      return first;
    }
    return getDisplayName(friend);
  }

  private getCaptionPillBg(): string {
    if (this.captionStyleIndex === 1) {
      return '#CCFFB800';
    }
    if (this.captionStyleIndex === 2) {
      return '#E6FFFFFF';
    }
    return '#8C1C1C1E';
  }

  private getCaptionTextColor(): string {
    if (this.captionStyleIndex === 1 || this.captionStyleIndex === 2) {
      return '#000000';
    }
    return '#FFFFFF';
  }

  private handleSavePhotoCopy(): void {
    if (this.selectedPhotoUri.length === 0) {
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const bytes = this.readUriBytes(this.selectedPhotoUri);
      const outPath = `${context.filesDir}/locket_saved_${Date.now()}.jpg`;
      const outFile = fileIo.openSync(outPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        fileIo.writeSync(outFile.fd, bytes);
      } finally {
        fileIo.closeSync(outFile);
      }
      promptAction.showToast({ message: 'Đã lưu bản sao ảnh' });
    } catch (_err) {
      promptAction.showToast({ message: 'Không thể lưu ảnh' });
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

  private async packPixelMapUnderLimit(
    packer: image.ImagePacker,
    pixelMap: image.PixelMap,
    format: string,
    maxBytes: number
  ): Promise<ArrayBuffer> {
    const qualities: number[] = [82, 68, 52, 38];
    let lastResult: ArrayBuffer = new ArrayBuffer(0);
    for (let i = 0; i < qualities.length; i++) {
      const packOpts: image.PackingOption = {
        format: format,
        quality: qualities[i]
      };
      lastResult = await packer.packToData(pixelMap, packOpts);
      if (lastResult.byteLength <= maxBytes) {
        return lastResult;
      }
    }
    await pixelMap.scale(0.65, 0.65);
    const fallbackOpts: image.PackingOption = {
      format: format,
      quality: 50
    };
    return await packer.packToData(pixelMap, fallbackOpts);
  }

  private async prepareUploadImageBytes(uri: string): Promise<ArrayBuffer> {
    const logDomain = 0x0000;
    const logTag = 'LocketUpload';
    const maxBytes = 900 * 1024;
    const maxSide = 1080;

    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    let origSize = 0;
    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;

    try {
      const stat = fileIo.statSync(file.fd);
      origSize = stat.size;
      hilog.info(logDomain, logTag, '%{public}s',
        `prepareUploadImageBytes: origSize=${origSize}, uri=${uri}`);

      imageSource = image.createImageSource(file.fd);
      const info = await imageSource.getImageInfo();
      const origW = info.size.width;
      const origH = info.size.height;
      let targetW = origW;
      let targetH = origH;
      if (origW > maxSide || origH > maxSide) {
        if (origW >= origH) {
          targetW = maxSide;
          targetH = Math.max(1, Math.round(origH * (maxSide / origW)));
        } else {
          targetH = maxSide;
          targetW = Math.max(1, Math.round(origW * (maxSide / origH)));
        }
      }

      const decodeOpts: image.DecodingOptions = {
        desiredSize: {
          width: targetW,
          height: targetH
        }
      };
      pixelMap = await imageSource.createPixelMap(decodeOpts);
      packer = image.createImagePacker();

      let packed: ArrayBuffer;
      let usedFormat = 'image/webp';
      try {
        packed = await this.packPixelMapUnderLimit(packer, pixelMap, 'image/webp', maxBytes);
      } catch (_webpErr) {
        usedFormat = 'image/jpeg';
        packed = await this.packPixelMapUnderLimit(packer, pixelMap, 'image/jpeg', maxBytes);
      }

      hilog.info(logDomain, logTag, '%{public}s',
        `prepareUploadImageBytes done: ${origW}x${origH} -> ${targetW}x${targetH}, format=${usedFormat}, origBytes=${origSize}, finalBytes=${packed.byteLength}`);
      return packed;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.error(logDomain, logTag, '%{public}s',
        `prepareUploadImageBytes compress failed: ${msg}`);
      if (origSize > 0 && origSize <= maxBytes) {
        return this.readUriBytes(uri);
      }
      throw new Error(`Không thể nén ảnh để tải lên (${msg})`);
    } finally {
      if (packer !== null) {
        try {
          await packer.release();
        } catch (_e) {
          // Ignore
        }
      }
      if (pixelMap !== null) {
        try {
          await pixelMap.release();
        } catch (_e) {
          // Ignore
        }
      }
      if (imageSource !== null) {
        try {
          await imageSource.release();
        } catch (_e) {
          // Ignore
        }
      }
      try {
        fileIo.closeSync(file);
      } catch (_e) {
        // Ignore
      }
    }
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
      const bytes = await this.prepareUploadImageBytes(this.selectedPhotoUri);
      const options: UploadMomentOptions = {
        caption: this.caption.trim(),
        recipients: this.sendToAll ? [] : this.selectedFriendUids,
        sentToAll: this.sendToAll,
        contentType: 'image/webp'
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
      if (this.selectedPhotoUri.length > 0) {
        // Post-capture Locket "Gửi đến..." UI matching reference layout
        Column() {
          // Top floating row: spacer | centered bold "Gửi đến..." | download icon
          Row() {
            Column()
              .width(44)
              .height(44)

            Blank()

            Text('Gửi đến...')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')

            Blank()

            Column() {
              Image($r('app.media.ic_download'))
                .width(26)
                .height(26)
                .fillColor('#FFFFFF')
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .justifyContent(FlexAlign.Center)
            .scale(this.pressedButtonId === 'cam_download' ? { x: 0.88, y: 0.88 } : { x: 1, y: 1 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_download', e);
            })
            .onClick(() => {
              this.handleSavePhotoCopy();
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          Blank()

          // 1:1 Large Rounded Photo Preview with floating "Thêm một tin nhắn" input pill inside bottom
          Stack({ alignContent: Alignment.Bottom }) {
            Image(this.getDisplayPhotoSrc())
              .width('100%')
              .aspectRatio(1)
              .objectFit(ImageFit.Cover)
              .borderRadius(48)
              .backgroundColor('#141416')

            Row() {
              TextInput({
                placeholder: 'Thêm một tin nhắn',
                text: this.caption
              })
                .width('100%')
                .height(44)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getCaptionTextColor())
                .placeholderColor(this.captionStyleIndex === 0 ? '#E5E5EA' : '#55000000')
                .caretColor('#FFB800')
                .textAlign(TextAlign.Center)
                .backgroundColor(Color.Transparent)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.caption = value;
                })
            }
            .constraintSize({ minWidth: 190, maxWidth: '82%' })
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.getCaptionPillBg())
            .backdropBlur(16)
            .margin({ bottom: 18 })
          }
          .width('94%')
          .constraintSize({ maxWidth: 400 })
          .scale({ x: this.photoCardScale, y: this.photoCardScale })
          .translate({ x: this.photoCardX, y: this.photoCardY })
          .opacity(this.photoCardOpacity)

          // 5 Subtle Page / Style Indicator Dots
          Row({ space: 8 }) {
            ForEach([0, 1, 2, 3, 4], (dotIdx: number) => {
              Column()
                .width(7)
                .height(7)
                .borderRadius(4)
                .backgroundColor(dotIdx === this.captionStyleIndex ? '#FFFFFF' : '#48484A')
            }, (dotIdx: number) => `${dotIdx}`)
          }
          .margin({ top: 14, bottom: 20 })
          .justifyContent(FlexAlign.Center)

          // 3-Button Action Row: X (Cancel) | Big Send Circle (84x84) | Aa+ (Style)
          Row() {
            // Left: Cancel / Discard (X)
            Column() {
              Image($r('app.media.ic_close'))
                .width(30)
                .height(30)
                .fillColor('#FFFFFF')
            }
            .width(58)
            .height(58)
            .borderRadius(29)
            .justifyContent(FlexAlign.Center)
            .scale(this.pressedButtonId === 'cam_cancel' ? { x: 0.88, y: 0.88 } : { x: 1, y: 1 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_cancel', e);
            })
            .onClick(() => {
              router.back();
            })

            // Center: Big Circular Send Button (84x84)
            Column() {
              if (this.isUploading) {
                LoadingProgress()
                  .width(32)
                  .height(32)
                  .color('#FFFFFF')
              } else {
                Image($r('app.media.ic_send'))
                  .width(34)
                  .height(34)
                  .fillColor('#FFFFFF')
              }
            }
            .width(84)
            .height(84)
            .borderRadius(42)
            .backgroundColor(this.isUploading ? '#FFB800' : '#48484A')
            .shadow({ radius: 18, color: '#66000000', offsetX: 0, offsetY: 5 })
            .scale({ x: this.postBtnScale, y: this.postBtnScale })
            .justifyContent(FlexAlign.Center)
            .enabled(!this.isUploading)
            .onTouch((event: TouchEvent) => {
              if (!this.isUploading) {
                this.handlePostBtnTouch(event);
              }
            })
            .onClick(() => {
              this.handlePostMoment();
            })

            // Right: Aa✨ Caption Style Button
            Column() {
              Stack({ alignContent: Alignment.TopEnd }) {
                Row() {
                  Text('Aa')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                }
                .width(42)
                .height(32)
                .borderRadius(16)
                .border({ width: 2, color: '#FFFFFF' })
                .justifyContent(FlexAlign.Center)

                Text('✦')
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .margin({ top: -6, right: -4 })
              }
            }
            .width(58)
            .height(58)
            .borderRadius(29)
            .justifyContent(FlexAlign.Center)
            .scale(this.pressedButtonId === 'cam_style' ? { x: 0.88, y: 0.88 } : { x: 1, y: 1 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_style', e);
            })
            .onClick(() => {
              animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
                this.captionStyleIndex = (this.captionStyleIndex + 1) % 3;
              });
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceEvenly)
          .alignItems(VerticalAlign.Center)

          Blank()

          // Bottom Horizontal Friend Selector Strip (Tất cả + Friend Avatars)
          Scroll() {
            Row({ space: 18 }) {
              // First Item: Tất cả
              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Column()
                    .width(62)
                    .height(62)
                    .borderRadius(31)
                    .border({
                      width: this.sendToAll ? 2.5 : 1.5,
                      color: this.sendToAll ? '#FFB800' : '#3A3A3C'
                    })

                  Column() {
                    Image($r('app.media.ic_friends'))
                      .width(24)
                      .height(24)
                      .fillColor('#FFFFFF')
                  }
                  .width(52)
                  .height(52)
                  .borderRadius(26)
                  .backgroundColor('#3A3A3C')
                  .justifyContent(FlexAlign.Center)
                }

                Text('Tất cả')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.sendToAll ? '#FFB800' : '#8E8E93')
                  .maxLines(1)
              }
              .onClick(() => {
                this.sendToAll = true;
                this.selectedFriendUids = [];
              })

              // Friends list
              ForEach(this.friends, (friend: FriendItem) => {
                Column({ space: 6 }) {
                  Stack({ alignContent: Alignment.Center }) {
                    Column()
                      .width(62)
                      .height(62)
                      .borderRadius(31)
                      .border({
                        width: (!this.sendToAll && this.selectedFriendUids.includes(friend.uid)) ? 2.5 : 1.5,
                        color: (!this.sendToAll && this.selectedFriendUids.includes(friend.uid)) ? '#FFB800' : '#3A3A3C'
                      })

                    if (friend.profilePictureUrl.length > 0) {
                      Image(friend.profilePictureUrl)
                        .width(52)
                        .height(52)
                        .borderRadius(26)
                        .objectFit(ImageFit.Cover)
                        .backgroundColor('#2C2C2E')
                    } else {
                      Column() {
                        Text(this.getFriendShortName(friend).substring(0, 1).toUpperCase())
                          .fontSize(18)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#FFFFFF')
                      }
                      .width(52)
                      .height(52)
                      .borderRadius(26)
                      .backgroundColor('#2C2C2E')
                      .justifyContent(FlexAlign.Center)
                    }
                  }

                  Text(this.getFriendShortName(friend))
                    .fontSize(13)
                    .fontWeight((!this.sendToAll && this.selectedFriendUids.includes(friend.uid))
                      ? FontWeight.Bold
                      : FontWeight.Medium)
                    .fontColor((!this.sendToAll && this.selectedFriendUids.includes(friend.uid))
                      ? '#FFB800'
                      : '#8E8E93')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 66 })
                }
                .onClick(() => {
                  this.toggleFriendSelection(friend.uid);
                })
              }, (friend: FriendItem) => friend.uid)
            }
            .padding({ left: 20, right: 20, top: 4, bottom: 8 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.safeTopVp, bottom: this.safeBottomVp })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#000000')
      } else {
        // Live Camera Fallback View when no photo is selected yet
        Column() {
          Row() {
            Column() {
              Image($r('app.media.ic_back'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
            }
            .width(48)
            .height(48)
            .backgroundColor('#CC1C1C1E')
            .backdropBlur(16)
            .borderRadius(24)
            .border({ width: 1, color: '#2E2E30' })
            .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
            .scale(this.pressedButtonId === 'cam_back' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .justifyContent(FlexAlign.Center)
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_back', e);
            })
            .onClick(() => {
              router.back();
            })

            Blank()

            Column() {
              Image($r('app.media.ic_flip_camera'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
            }
            .width(48)
            .height(48)
            .backgroundColor('#CC1C1C1E')
            .backdropBlur(16)
            .borderRadius(24)
            .border({ width: 1, color: '#2E2E30' })
            .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
            .scale(this.pressedButtonId === 'cam_flip' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .justifyContent(FlexAlign.Center)
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_flip', e);
            })
            .onClick(() => {
              this.flipCamera();
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          Blank()

          Stack({ alignContent: Alignment.Bottom }) {
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
                Column({ space: 10 }) {
                  Image($r('app.media.ic_heart_locket'))
                    .width(44)
                    .height(44)
                    .fillColor('#FFB800')
                  Text('Đang khởi động camera...')
                    .fontSize(14)
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

            Row() {
              Text(this.formatZoomLabel())
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFB800')
            }
            .height(34)
            .padding({ left: 16, right: 16 })
            .borderRadius(17)
            .backgroundColor('#991C1C1E')
            .border({ width: 1, color: '#44FFFFFF' })
            .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
            .scale(this.pressedButtonId === 'cam_zoom' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .justifyContent(FlexAlign.Center)
            .margin({ bottom: 16 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_zoom', e);
            })
            .onClick(() => {
              this.toggleZoom();
            })
          }
          .width('94%')
          .constraintSize({ maxWidth: 400 })
          .gesture(
            PinchGesture()
              .onActionStart(() => {
                this.pinchStartZoom = this.zoomRatio;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.zoomRatio = this.liveCamera.setZoomRatio(this.pinchStartZoom * event.scale);
              })
          )

          Row() {
            Column() {
              Image($r('app.media.ic_gallery'))
                .width(26)
                .height(26)
                .fillColor('#FFFFFF')
            }
            .width(52)
            .height(52)
            .borderRadius(26)
            .backgroundColor('#1C1C1E')
            .border({ width: 1, color: '#2E2E30' })
            .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
            .scale(this.pressedButtonId === 'cam_gallery'
              ? { x: 0.91, y: 0.91 }
              : { x: this.galleryPulseScale, y: this.galleryPulseScale })
            .justifyContent(FlexAlign.Center)
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_gallery', e);
            })
            .onClick(() => {
              this.pickFromGallery();
            })

            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(84)
                .height(84)
                .borderRadius(42)
                .backgroundColor('#000000')
                .border({ width: 4.5, color: '#FFB800' })
                .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })

              Column()
                .width(66)
                .height(66)
                .borderRadius(33)
                .backgroundColor(this.isCapturing ? '#FFB800' : '#FFFFFF')
            }
            .margin({ left: 32, right: 32 })
            .scale({ x: this.shutterScale, y: this.shutterScale })
            .enabled(!this.isCapturing)
            .onTouch((event: TouchEvent) => {
              this.handleShutterTouch(event);
            })
            .onClick(() => {
              this.captureFromCamera();
            })

            Column() {
              Image($r('app.media.ic_flip_camera'))
                .width(26)
                .height(26)
                .fillColor('#FFFFFF')
            }
            .width(52)
            .height(52)
            .borderRadius(26)
            .backgroundColor('#1C1C1E')
            .border({ width: 1, color: '#2E2E30' })
            .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
            .scale(this.pressedButtonId === 'cam_flip_bottom' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .justifyContent(FlexAlign.Center)
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('cam_flip_bottom', e);
            })
            .onClick(() => {
              this.flipCamera();
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 24 })

          Blank()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.safeTopVp, bottom: this.safeBottomVp })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#000000')
      }

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
