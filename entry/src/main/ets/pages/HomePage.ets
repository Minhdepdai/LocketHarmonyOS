import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  ConversationSummary,
  FriendItem,
  getDisplayName,
  MomentItem,
  UserProfile
} from '../models/LocketModels';
import { LiveCameraController } from '../services/LiveCameraController';
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
  @State allFriends: FriendItem[] = [];
  @State conversations: ConversationSummary[] = [];
  @State isLoadingMessages: boolean = false;
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
  @State isCameraReady: boolean = false;
  @State isCapturing: boolean = false;
  @State zoomRatio: number = 1.0;
  @State shutterScale: number = 1.0;
  @State captureFlyScale: number = 1.0;
  @State captureFlyX: number = 0;
  @State captureFlyY: number = 0;
  @State captureFlyOpacity: number = 1.0;
  @State galleryPulseScale: number = 1.0;
  @State burstEmoji: string = '';
  @State burstOffsetY: number = 0;
  @State burstOpacity: number = 0;
  @State burstScale: number = 0.6;
  @StorageProp('locket_widget_tap_ts') @Watch('onWidgetTapChanged') widgetTapTs: number = 0;
  private pinchStartZoom: number = 1.0;
  private viewedMomentIds: Set<string> = new Set();
  private swiperController: SwiperController = new SwiperController();
  private xComponentController: XComponentController = new XComponentController();
  private liveCamera: LiveCameraController = new LiveCameraController();
  private cameraSurfaceId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as HomeRouteParams | undefined;
    if (params !== undefined && params.filterUserUid !== undefined && params.filterUserUid.length > 0) {
      this.filterUid = params.filterUserUid;
      this.filterLabel = params.filterUserName ?? 'Đã lọc';
      this.viewMode = 'feed';
    } else {
      const pendingMode = AppStorage.get<string>('locket_pending_view_mode');
      if (pendingMode !== undefined && pendingMode.length > 0) {
        this.viewMode = pendingMode;
        AppStorage.setOrCreate<string>('locket_pending_view_mode', '');
      }
    }
    this.loadInitialData();
  }

  onWidgetTapChanged(): void {
    const pendingMode = AppStorage.get<string>('locket_pending_view_mode');
    if (pendingMode !== undefined && pendingMode.length > 0) {
      AppStorage.setOrCreate<string>('locket_pending_view_mode', '');
      this.switchViewMode(pendingMode);
      this.loadInitialData();
    }
  }

  onPageShow(): void {
    if (!SessionManager.getInstance().isLoggedIn()) {
      router.clear();
      router.replaceUrl({ url: 'pages/LoginPage' });
      return;
    }
    const pendingMode = AppStorage.get<string>('locket_pending_view_mode');
    if (pendingMode !== undefined && pendingMode.length > 0) {
      AppStorage.setOrCreate<string>('locket_pending_view_mode', '');
      this.switchViewMode(pendingMode);
    }
    if (this.viewMode === 'camera' && this.cameraSurfaceId.length > 0 && !this.liveCamera.isSessionRunning()) {
      this.startLiveCamera();
    } else if (this.viewMode === 'messages') {
      this.loadMessagesTab();
    }
  }

  onPageHide(): void {
    this.stopLiveCamera();
  }

  aboutToDisappear(): void {
    this.stopLiveCamera();
  }

  private switchViewMode(targetMode: string): void {
    if (this.viewMode === targetMode) {
      return;
    }
    if (this.viewMode === 'camera' && targetMode !== 'camera') {
      this.stopLiveCamera();
    }
    animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
      this.viewMode = targetMode;
    });
    if (targetMode === 'messages') {
      this.loadMessagesTab();
    }
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

  private triggerReactionBurst(emoji: string): void {
    this.burstEmoji = emoji;
    this.burstOffsetY = 0;
    this.burstOpacity = 1;
    this.burstScale = 0.85;
    animateTo({ duration: 680, curve: Curve.EaseOut }, () => {
      this.burstOffsetY = -120;
      this.burstOpacity = 0;
      this.burstScale = 1.65;
    });
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

  private async startLiveCamera(): Promise<void> {
    if (this.cameraSurfaceId.length === 0 || this.viewMode !== 'camera') {
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

  private async flipCamera(): Promise<void> {
    this.isFrontCamera = !this.isFrontCamera;
    if (this.viewMode === 'camera' && this.cameraSurfaceId.length > 0) {
      await this.startLiveCamera();
    }
    promptAction.showToast({ message: this.isFrontCamera ? 'Đã chuyển camera trước' : 'Đã chuyển camera sau' });
  }

  private async handleShutterCapture(): Promise<void> {
    if (this.isCapturing) {
      return;
    }
    if (!this.isCameraReady) {
      await this.startLiveCamera();
      if (!this.isCameraReady) {
        router.pushUrl({ url: 'pages/CameraPage' });
        return;
      }
    }
    this.isCapturing = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const filePath = await this.liveCamera.capturePhotoToFile(context);
      await this.stopLiveCamera();

      // Animate 1:1 photo card shrinking & flying down-left toward Gallery button
      animateTo({ duration: 380, curve: Curve.EaseInOut }, () => {
        this.captureFlyScale = 0.14;
        this.captureFlyX = -115;
        this.captureFlyY = 250;
        this.captureFlyOpacity = 0;
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
      }, 300);

      setTimeout(() => {
        this.captureFlyScale = 1.0;
        this.captureFlyX = 0;
        this.captureFlyY = 0;
        this.captureFlyOpacity = 1.0;
        this.isCapturing = false;
        router.pushUrl({
          url: 'pages/CameraPage',
          params: { capturedPhotoPath: filePath }
        });
      }, 460);
    } catch (err) {
      this.isCapturing = false;
      const msg = err instanceof Error ? err.message : 'Không thể chụp ảnh';
      promptAction.showToast({ message: msg });
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
        router.pushUrl({
          url: 'pages/CameraPage',
          params: { capturedPhotoPath: result.photoUris[0] }
        });
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể mở thư viện ảnh';
      promptAction.showToast({ message: msg });
    }
  }

  private async loadInitialData(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.currentIndex = 0;
    this.replyText = '';
    try {
      const session = SessionManager.getInstance().getSession();
      if (session === null) {
        router.clear();
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
      this.allFriends = list;
      this.friendsCount = list.length;
    }).catch(() => {
      // Non-critical count fetch
    });
  }

  private async loadMessagesTab(): Promise<void> {
    this.isLoadingMessages = true;
    try {
      const api = LocketApiClient.getInstance();
      const convs = await api.getConversations();
      this.conversations = convs;
      if (this.allFriends.length === 0) {
        const friendsList = await api.getAllFriends();
        this.allFriends = friendsList;
        this.friendsCount = friendsList.length;
      }
    } catch (_err) {
      // Keep existing list on transient error
    } finally {
      this.isLoadingMessages = false;
    }
  }

  private getFriendsWithoutConversation(): FriendItem[] {
    const activeUids: Set<string> = new Set();
    for (let i = 0; i < this.conversations.length; i++) {
      activeUids.add(this.conversations[i].friendUid);
    }
    return this.allFriends.filter((f: FriendItem) => !activeUids.has(f.uid));
  }

  private formatVietnameseDate(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d = new Date(ms);
    const day = d.getDate();
    const month = d.getMonth() + 1;
    return `Ngày ${day} tháng ${month}`;
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
    this.triggerReactionBurst(emoji);
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
  private buildProfileAvatarButton() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.myProfile !== null && this.myProfile.profilePictureUrl.length > 0) {
        Image(this.myProfile.profilePictureUrl)
          .width(44)
          .height(44)
          .borderRadius(22)
          .objectFit(ImageFit.Cover)
          .border({ width: 2, color: '#FFB800' })
          .shadow({ radius: 16, color: '#66FFB800', offsetX: 0, offsetY: 2 })
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
        .border({ width: 2, color: '#FFB800' })
        .shadow({ radius: 16, color: '#66FFB800', offsetX: 0, offsetY: 2 })
        .justifyContent(FlexAlign.Center)
      }
    }
    .onClick(() => {
      router.pushUrl({ url: 'pages/ProfilePage' });
    })
  }

  @Builder
  private buildTopBar() {
    Row() {
      // Left: 44x44 circle megaphone icon
      Column() {
        Image($r('app.media.ic_megaphone'))
          .width(20)
          .height(20)
          .fillColor('#FFFFFF')
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
          Image($r('app.media.ic_friends'))
            .width(18)
            .height(18)
            .fillColor('#FFFFFF')
          Text(`${this.friendsCount} Bạn bè`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        } else {
          Text(this.filterLabel)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
          if (this.filterUid.length > 0) {
            Image($r('app.media.ic_close'))
              .width(14)
              .height(14)
              .fillColor('#8E8E93')
          } else {
            Text('⌄')
              .fontSize(15)
              .fontColor('#8E8E93')
          }
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
      this.buildProfileAvatarButton()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 10 })
  }

  @Builder
  private buildCameraMode() {
    Column() {
      // Large 1:1 rounded live viewfinder with vertical swipe-up + pinch-to-zoom gestures
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: 'locket_home_camera',
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
            .borderRadius(56)
            .clip(true)

          if (!this.isCameraReady) {
            Column() {
              Image($r('app.media.ic_heart_locket'))
                .width(44)
                .height(44)
                .fillColor('#FFB800')
                .opacity(0.8)
              Text(this.isFrontCamera ? 'Camera trước • Chạm để chụp' : 'Chạm để chụp hoặc vuốt lên xem lịch sử')
                .fontSize(14)
                .fontColor('#8E8E93')
                .margin({ top: 12 })
            }
            .width('100%')
            .aspectRatio(1)
            .borderRadius(56)
            .backgroundColor('#141416')
            .border({ width: 1, color: '#2E2E30' })
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .aspectRatio(1)
        .borderRadius(56)
        .clip(true)
        .border({ width: 1, color: '#2E2E30' })

        // Interactive circular dark pill zoom toggle (1x / 2x)
        Row() {
          Text(this.formatZoomLabel())
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFB800')
        }
        .height(34)
        .padding({ left: 14, right: 14 })
        .borderRadius(17)
        .backgroundColor('#991C1C1E')
        .border({ width: 1, color: '#44FFFFFF' })
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 18 })
        .onClick(() => {
          this.toggleZoom();
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .margin({ top: 8 })
      .scale({ x: this.captureFlyScale, y: this.captureFlyScale })
      .translate({ x: this.captureFlyX, y: this.captureFlyY })
      .opacity(this.captureFlyOpacity)
      .gesture(
        GestureGroup(
          GestureMode.Parallel,
          PanGesture({ direction: PanDirection.Vertical })
            .onActionEnd((event: GestureEvent) => {
              if (event.offsetY < -45) {
                this.switchViewMode('feed');
              }
            }),
          PinchGesture()
            .onActionStart(() => {
              this.pinchStartZoom = this.zoomRatio;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.zoomRatio = this.liveCamera.setZoomRatio(this.pinchStartZoom * event.scale);
            })
        )
      )
      .onClick(() => {
        this.handleShutterCapture();
      })

      Blank()

      // Shutter Row: Gallery | Big 84x84 Shutter | Flip
      Row() {
        // Left Gallery button
        Column() {
          Image($r('app.media.ic_gallery'))
            .width(22)
            .height(22)
            .fillColor('#FFFFFF')
        }
        .width(50)
        .height(50)
        .borderRadius(25)
        .backgroundColor('#1C1C1E')
        .border({ width: 1, color: '#2E2E30' })
        .scale({ x: this.galleryPulseScale, y: this.galleryPulseScale })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.pickFromGallery();
        })

        // Center big 84x84 Shutter circle (#FFB800 4vp ring + golden glow + press-scale)
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(84)
            .height(84)
            .borderRadius(42)
            .backgroundColor('#000000')
            .border({ width: 4, color: '#FFB800' })
            .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })

          Column()
            .width(68)
            .height(68)
            .borderRadius(34)
            .backgroundColor(this.isCapturing ? '#FFB800' : '#FFFFFF')
        }
        .margin({ left: 36, right: 36 })
        .scale({ x: this.shutterScale, y: this.shutterScale })
        .onTouch((event: TouchEvent) => {
          this.handleShutterTouch(event);
        })
        .onClick(() => {
          this.handleShutterCapture();
        })

        // Right Flip icon
        Column() {
          Image($r('app.media.ic_flip_camera'))
            .width(22)
            .height(22)
            .fillColor('#FFFFFF')
        }
        .width(50)
        .height(50)
        .borderRadius(25)
        .backgroundColor('#1C1C1E')
        .border({ width: 1, color: '#2E2E30' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.flipCamera();
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
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .margin({ top: 14 })
      .onClick(() => {
        this.switchViewMode('feed');
      })

      // Bottom floating pill nav
      Row({ space: 8 }) {
        // Grid / Calendar icon
        Column() {
          Image($r('app.media.ic_grid'))
            .width(20)
            .height(20)
            .fillColor('#8E8E93')
        }
        .width(54)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.switchViewMode('grid');
        })

        // Home highlighted pill
        Column() {
          Image($r('app.media.ic_home'))
            .width(22)
            .height(22)
            .fillColor('#FFFFFF')
        }
        .width(68)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#262628')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.switchViewMode('camera');
        })

        // Chat icon -> Messages tab
        Column() {
          Image($r('app.media.ic_chat'))
            .width(20)
            .height(20)
            .fillColor('#8E8E93')
        }
        .width(54)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.switchViewMode('messages');
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
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 })).animation({ duration: 240, curve: Curve.EaseOut }))
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
            .height(44)
            .fontSize(16)
            .fontColor('#000000')
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#FFB800')
            .borderRadius(22)
            .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
            .padding({ left: 26, right: 26 })
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
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ bottom: 14 })
          Button('Làm mới')
            .height(44)
            .fontSize(16)
            .fontColor('#000000')
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#FFB800')
            .borderRadius(22)
            .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
            .padding({ left: 26, right: 26 })
            .onClick(() => {
              this.loadInitialData();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // Vertical Swiper of moments with floating reaction burst overlay
        Stack({ alignContent: Alignment.Center }) {
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
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                      .backgroundColor('#993A3A3C')
                      .borderRadius(22)
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
                    .fontSize(16)
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
          .width('100%')
          .height('100%')
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

          // Floating reaction burst animation over the photo card
          if (this.burstEmoji.length > 0) {
            Text(this.burstEmoji)
              .fontSize(64)
              .opacity(this.burstOpacity)
              .scale({ x: this.burstScale, y: this.burstScale })
              .translate({ y: this.burstOffsetY })
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .layoutWeight(1)
        .width('100%')

        // Combined Reply + Reaction Pill Bar
        Row({ space: 4 }) {
          TextInput({ placeholder: 'Gửi tin nh...', text: this.replyText })
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
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
            Column() {
              if (this.isSendingReply) {
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
            .width(40)
            .height(40)
            .backgroundColor('#FFB800')
            .borderRadius(20)
            .shadow({ radius: 18, color: '#66FFB800', offsetX: 0, offsetY: 4 })
            .justifyContent(FlexAlign.Center)
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
            Column() {
              Image($r('app.media.ic_emoji_add'))
                .width(20)
                .height(20)
                .fillColor('#FFFFFF')
            }
            .width(34)
            .height(34)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              const current = this.getCurrentMoment();
              if (current !== null) {
                this.handleReact(current.canonicalUid, '😂');
              }
            })
          }
        }
        .height(54)
        .padding({ left: 10, right: 10 })
        .margin({ left: 16, right: 16, bottom: 12 })
        .borderRadius(27)
        .backgroundColor('#1C1C1E')
        .border({ width: 1, color: '#2E2E30' })
      }

      // Bottom Controls Row
      Row() {
        // Left 48x48 circle: 4-squares Grid icon
        Column() {
          Image($r('app.media.ic_grid'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF')
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor('#1A1A1C')
        .border({ width: 1, color: '#2E2E30' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.switchViewMode('grid');
        })

        Blank()

        // Center pill: Calendar | 44x44 white circle with #FFB800 ring | Chat
        Row({ space: 18 }) {
          Image($r('app.media.ic_calendar'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF')
            .onClick(() => {
              this.switchViewMode('grid');
            })

          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor('#000000')
              .border({ width: 3, color: '#FFB800' })
              .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
            Column()
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor('#FFFFFF')
          }
          .onClick(() => {
            this.switchViewMode('camera');
          })

          Image($r('app.media.ic_chat'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF')
            .onClick(() => {
              this.switchViewMode('messages');
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
          if (this.isOwnMoment(this.getCurrentMoment())) {
            Image($r('app.media.ic_trash'))
              .width(20)
              .height(20)
              .fillColor('#FF453A')
          } else {
            Image($r('app.media.ic_share'))
              .width(20)
              .height(20)
              .fillColor('#FFFFFF')
          }
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
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 })).animation({ duration: 240, curve: Curve.EaseOut }))
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
            .fontSize(16)
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
                  this.switchViewMode('feed');
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
        Image($r('app.media.ic_grid'))
          .width(22)
          .height(22)
          .fillColor('#FFB800')
          .onClick(() => {
            this.switchViewMode('grid');
          })

        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor('#000000')
            .border({ width: 3, color: '#FFB800' })
            .shadow({ radius: 24, color: '#66FFB800', offsetX: 0, offsetY: 4 })
          Column()
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor('#FFFFFF')
        }
        .onClick(() => {
          this.switchViewMode('camera');
        })

        Image($r('app.media.ic_chat'))
          .width(22)
          .height(22)
          .fillColor('#FFFFFF')
          .onClick(() => {
            this.switchViewMode('messages');
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
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 })).animation({ duration: 240, curve: Curve.EaseOut }))
  }

  @Builder
  private buildMessagesMode() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // Dedicated Messages Header: centered bold "Trò chuyện" + right circular user avatar
        Row() {
          Column()
            .width(44)
            .height(44)

          Blank()

          Text('Trò chuyện')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')

          Blank()

          this.buildProfileAvatarButton()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 14 })

        if (this.isLoadingMessages && this.conversations.length === 0 && this.allFriends.length === 0) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color('#FFB800')
            Text('Đang tải cuộc trò chuyện...')
              .fontSize(14)
              .fontColor('#8E8E93')
              .margin({ top: 10 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 6 }) {
              // Active conversations
              ForEach(this.conversations, (conv: ConversationSummary) => {
                Row({ space: 14 }) {
                  if (conv.friendAvatar.length > 0) {
                    Image(conv.friendAvatar)
                      .width(56)
                      .height(56)
                      .borderRadius(28)
                      .objectFit(ImageFit.Cover)
                      .border({ width: 1.5, color: '#2C2C2E' })
                  } else {
                    Column() {
                      Text(conv.friendName.length > 0 ? conv.friendName.substring(0, 1).toUpperCase() : 'L')
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                    }
                    .width(56)
                    .height(56)
                    .borderRadius(28)
                    .backgroundColor('#262628')
                    .border({ width: 1.5, color: '#2C2C2E' })
                    .justifyContent(FlexAlign.Center)
                  }

                  Column({ space: 4 }) {
                    Row() {
                      Text(conv.friendName)
                        .fontSize(17)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)

                      if (conv.lastUpdatedMs > 0) {
                        Text(this.formatVietnameseDate(conv.lastUpdatedMs))
                          .fontSize(13)
                          .fontColor('#8E8E93')
                          .margin({ left: 8 })
                      }
                    }
                    .width('100%')

                    Text(conv.lastMessage.length > 0 ? conv.lastMessage : 'Đã gửi một khoảnh khắc')
                      .fontSize(14)
                      .fontColor('#8E8E93')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/ChatPage',
                    params: {
                      friendUid: conv.friendUid,
                      friendName: conv.friendName,
                      friendAvatar: conv.friendAvatar
                    }
                  });
                })
              }, (conv: ConversationSummary) => conv.conversationId)

              // Remaining friends without conversations
              ForEach(this.getFriendsWithoutConversation(), (friend: FriendItem) => {
                Row({ space: 14 }) {
                  if (friend.profilePictureUrl.length > 0) {
                    Image(friend.profilePictureUrl)
                      .width(56)
                      .height(56)
                      .borderRadius(28)
                      .objectFit(ImageFit.Cover)
                      .border({ width: 1.5, color: '#2C2C2E' })
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
                    .backgroundColor('#262628')
                    .border({ width: 1.5, color: '#2C2C2E' })
                    .justifyContent(FlexAlign.Center)
                  }

                  Column({ space: 4 }) {
                    Text(getDisplayName(friend))
                      .fontSize(17)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text('Bắt đầu cuộc hội thoại!')
                      .fontSize(14)
                      .fontColor('#8E8E93')
                      .maxLines(1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
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
              }, (friend: FriendItem) => friend.uid)

              if (this.conversations.length === 0 && this.allFriends.length === 0) {
                Column({ space: 10 }) {
                  Text('Chưa có cuộc trò chuyện nào')
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                  Text('Thêm bạn bè để bắt đầu nhắn tin trên Locket!')
                    .fontSize(14)
                    .fontColor('#8E8E93')
                }
                .width('100%')
                .padding({ top: 80 })
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .padding({ bottom: 104 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      // Bottom bar: clean centered 3-icon floating pill (Calendar/Grid, Home, highlighted Chat)
      Row({ space: 8 }) {
        Column() {
          Image($r('app.media.ic_grid'))
            .width(20)
            .height(20)
            .fillColor('#8E8E93')
        }
        .width(54)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.switchViewMode('grid');
        })

        Column() {
          Image($r('app.media.ic_home'))
            .width(22)
            .height(22)
            .fillColor('#8E8E93')
        }
        .width(54)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.switchViewMode('camera');
        })

        // Highlighted Chat pill
        Column() {
          Image($r('app.media.ic_chat'))
            .width(22)
            .height(22)
            .fillColor('#FFFFFF')
        }
        .width(68)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#262628')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.loadMessagesTab();
        })
      }
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .borderRadius(32)
      .backgroundColor('#141416')
      .border({ width: 1, color: '#2E2E30' })
      .margin({ bottom: 20 })
    }
    .width('100%')
    .layoutWeight(1)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 })).animation({ duration: 240, curve: Curve.EaseOut }))
  }

  build() {
    Column() {
      if (this.viewMode !== 'messages') {
        this.buildTopBar()
      }

      if (this.viewMode === 'camera') {
        this.buildCameraMode()
      } else if (this.viewMode === 'feed') {
        this.buildFeedMode()
      } else if (this.viewMode === 'grid') {
        this.buildGridMode()
      } else {
        this.buildMessagesMode()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
