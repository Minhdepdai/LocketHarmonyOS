import { curves, promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  ConversationSummary,
  FriendItem,
  getDisplayName,
  MomentItem,
  UserProfile
} from '../models/LocketModels';
import { CacheService } from '../services/CacheService';
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
  @State showFriendFilter: boolean = false;
  @State slideDirection: string = 'right';
  @State pressedButtonId: string = '';
  @StorageProp('safe_top_vp') safeTopVp: number = 38;
  @StorageProp('safe_bottom_vp') safeBottomVp: number = 20;
  @StorageProp('locket_widget_tap_ts') @Watch('onWidgetTapChanged') widgetTapTs: number = 0;
  private pinchStartZoom: number = 1.0;
  private viewedMomentIds: Set<string> = new Set();
  private swiperController: SwiperController = new SwiperController();
  private xComponentController: XComponentController = new XComponentController();
  private liveCamera: LiveCameraController = new LiveCameraController();
  private cameraSurfaceId: string = '';

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

  private getHorizontalTabIndex(mode: string): number {
    if (mode === 'grid') {
      return 0;
    }
    if (mode === 'messages') {
      return 2;
    }
    return 1;
  }

  private buildDirectionalTransition(): TransitionEffect {
    if (this.slideDirection === 'left') {
      return TransitionEffect.asymmetric(
        TransitionEffect.translate({ x: '100%' }).combine(TransitionEffect.OPACITY),
        TransitionEffect.translate({ x: '-100%' }).combine(TransitionEffect.OPACITY)
      );
    }
    if (this.slideDirection === 'right') {
      return TransitionEffect.asymmetric(
        TransitionEffect.translate({ x: '-100%' }).combine(TransitionEffect.OPACITY),
        TransitionEffect.translate({ x: '100%' }).combine(TransitionEffect.OPACITY)
      );
    }
    if (this.slideDirection === 'up') {
      return TransitionEffect.asymmetric(
        TransitionEffect.translate({ y: '100%' }).combine(TransitionEffect.OPACITY),
        TransitionEffect.translate({ y: '-100%' }).combine(TransitionEffect.OPACITY)
      );
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ y: '-100%' }).combine(TransitionEffect.OPACITY),
      TransitionEffect.translate({ y: '100%' }).combine(TransitionEffect.OPACITY)
    );
  }

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

    // Instant hydration from CacheService (stale-while-revalidate)
    const cache = CacheService.getInstance();
    if (this.filterUid.length === 0) {
      const cachedMoments = cache.getCachedMoments();
      if (cachedMoments.length > 0) {
        this.moments = cachedMoments;
        this.isLoading = false;
      }
    }
    const cachedFriends = cache.getCachedFriends();
    if (cachedFriends.length > 0) {
      this.allFriends = cachedFriends;
      this.friendsCount = cachedFriends.length;
    }
    const cachedConvs = cache.getCachedConversations();
    if (cachedConvs.length > 0) {
      this.conversations = cachedConvs;
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
    if (this.showFriendFilter) {
      this.showFriendFilter = false;
    }
    if (this.viewMode === 'camera' && targetMode === 'feed') {
      this.slideDirection = 'up';
    } else if (this.viewMode === 'feed' && targetMode === 'camera') {
      this.slideDirection = 'down';
    } else {
      const currentIdx = this.getHorizontalTabIndex(this.viewMode);
      const targetIdx = this.getHorizontalTabIndex(targetMode);
      this.slideDirection = targetIdx > currentIdx ? 'left' : 'right';
    }
    animateTo({ curve: curves.springMotion(0.52, 0.86) }, () => {
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
      animateTo({ curve: curves.springMotion(0.35, 0.65) }, () => {
        this.shutterScale = 0.91;
      });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      animateTo({ curve: curves.springMotion(0.45, 0.72) }, () => {
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
    const context = getContext(this) as common.UIAbilityContext;
    if (!this.isCameraReady) {
      await this.startLiveCamera();
    }
    this.isCapturing = true;
    try {
      let filePath = '';
      if (this.isCameraReady) {
        try {
          filePath = await this.liveCamera.capturePhotoToFile(context);
          await this.stopLiveCamera();
        } catch (_captureErr) {
          this.isCameraReady = false;
          this.zoomRatio = 1.0;
          filePath = await this.liveCamera.pickPhotoWithSystemCamera(context, this.isFrontCamera);
        }
      } else {
        filePath = await this.liveCamera.pickPhotoWithSystemCamera(context, this.isFrontCamera);
      }

      if (filePath.length === 0) {
        this.isCapturing = false;
        if (this.viewMode === 'camera' && this.cameraSurfaceId.length > 0) {
          this.startLiveCamera();
        }
        return;
      }

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
      if (this.viewMode === 'camera' && this.cameraSurfaceId.length > 0) {
        this.startLiveCamera();
      }
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
    const hasCached = this.moments.length > 0;
    if (!hasCached) {
      this.isLoading = true;
    }
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
      if (this.filterUid.length === 0) {
        CacheService.getInstance().saveMoments(feed.moments);
      }
      if (this.moments.length > 0) {
        this.markAsViewedSilently(this.moments[0].canonicalUid);
      }
      this.loadFriendsCountSilently();
    } catch (err) {
      if (!hasCached) {
        const msg = err instanceof Error ? err.message : 'Không thể tải dữ liệu';
        this.errorMessage = msg;
      }
    } finally {
      this.isLoading = false;
    }
  }

  private loadFriendsCountSilently(): void {
    LocketApiClient.getInstance().getAllFriends().then((list) => {
      this.allFriends = list;
      this.friendsCount = list.length;
      CacheService.getInstance().saveFriends(list);
    }).catch(() => {
      // Non-critical count fetch
    });
  }

  private selectFriendFilter(uid: string, label: string): void {
    this.filterUid = uid;
    this.filterLabel = label;
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showFriendFilter = false;
    });
    this.reloadFilteredMoments();
  }

  private async reloadFilteredMoments(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.currentIndex = 0;
    this.replyText = '';
    try {
      const feed = await LocketApiClient.getInstance().getLatestMoments(undefined, this.filterUid);
      this.moments = feed.moments;
      this.syncToken = feed.syncToken;
      if (this.moments.length > 0) {
        this.markAsViewedSilently(this.moments[0].canonicalUid);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Không thể tải khoảnh khắc';
      this.errorMessage = msg;
    } finally {
      this.isLoading = false;
    }
  }

  private async loadMessagesTab(): Promise<void> {
    const hasCached = this.conversations.length > 0 || this.allFriends.length > 0;
    if (!hasCached) {
      this.isLoadingMessages = true;
    }
    try {
      const api = LocketApiClient.getInstance();
      const convs = await api.getConversations();
      this.conversations = convs;
      CacheService.getInstance().saveConversations(convs);
      if (this.allFriends.length === 0) {
        const friendsList = await api.getAllFriends();
        this.allFriends = friendsList;
        this.friendsCount = friendsList.length;
        CacheService.getInstance().saveFriends(friendsList);
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
      if (this.filterUid.length === 0) {
        CacheService.getInstance().saveMoments(this.moments);
      }
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
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .border({ width: 2, color: '#FFB800' })
          .shadow({ radius: 14, color: '#66FFB800', offsetX: 0, offsetY: 2 })
      } else {
        Column() {
          Text(this.getMyInitial())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor('#2C2C2E')
        .border({ width: 2, color: '#FFB800' })
        .shadow({ radius: 14, color: '#66FFB800', offsetX: 0, offsetY: 2 })
        .justifyContent(FlexAlign.Center)
      }
    }
    .scale(this.pressedButtonId === 'home_profile' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
    .onTouch((e: TouchEvent) => {
      this.handleButtonTouch('home_profile', e);
    })
    .onClick(() => {
      router.pushUrl({ url: 'pages/ProfilePage' });
    })
  }

  @Builder
  private buildTopBar() {
    Row() {
      // Left: 48x48 circle megaphone icon
      Column() {
        Image($r('app.media.ic_megaphone'))
          .width(24)
          .height(24)
          .fillColor('#FFFFFF')
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#1A1A1C')
      .border({ width: 1, color: '#2E2E30' })
      .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
      .scale(this.pressedButtonId === 'home_megaphone' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
      .justifyContent(FlexAlign.Center)
      .onTouch((e: TouchEvent) => {
        this.handleButtonTouch('home_megaphone', e);
      })
      .onClick(() => {
        this.loadInitialData();
        promptAction.showToast({ message: 'Đã làm mới khoảnh khắc' });
      })

      Blank()

      // Center: Mode-aware Friends / In-Place Filter pill
      Row({ space: 8 }) {
        if (this.viewMode === 'camera') {
          Image($r('app.media.ic_friends'))
            .width(24)
            .height(24)
            .fillColor('#FFFFFF')
          Text(`${this.friendsCount} Bạn bè`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        } else {
          Text(this.filterLabel)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.filterUid.length > 0 ? '#FFB800' : '#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 165 })
          Text('⌄')
            .fontSize(16)
            .fontColor(this.showFriendFilter ? '#FFB800' : '#8E8E93')
        }
      }
      .height(48)
      .padding({ left: 20, right: 20 })
      .borderRadius(24)
      .backgroundColor('#1A1A1C')
      .border({ width: 1, color: this.showFriendFilter ? '#FFB800' : '#2E2E30' })
      .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
      .scale(this.pressedButtonId === 'home_friends_pill' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
      .justifyContent(FlexAlign.Center)
      .onTouch((e: TouchEvent) => {
        this.handleButtonTouch('home_friends_pill', e);
      })
      .onClick(() => {
        if (this.viewMode === 'camera') {
          router.pushUrl({ url: 'pages/FriendsPage' });
        } else {
          if (this.allFriends.length === 0) {
            this.loadFriendsCountSilently();
          }
          animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
            this.showFriendFilter = !this.showFriendFilter;
          });
        }
      })

      Blank()

      // Right: 48x48 circular user avatar -> ProfilePage
      this.buildProfileAvatarButton()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private buildCameraMode() {
    Column() {
      Blank()

      // Centered 1:1 rounded live viewfinder (94% width, max 400vp, radius 48)
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
            .borderRadius(48)
            .clip(true)

          if (!this.isCameraReady) {
            Column() {
              Image($r('app.media.ic_heart_locket'))
                .width(44)
                .height(44)
                .fillColor('#FFB800')
                .opacity(0.85)
              Text(this.isFrontCamera ? 'Camera trước • Chạm để chụp' : 'Chạm để chụp hoặc vuốt lên xem lịch sử')
                .fontSize(14)
                .fontColor('#8E8E93')
                .margin({ top: 10 })
            }
            .width('100%')
            .aspectRatio(1)
            .borderRadius(48)
            .backgroundColor('#141416')
            .border({ width: 1, color: '#2E2E30' })
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .aspectRatio(1)
        .borderRadius(48)
        .clip(true)
        .border({ width: 1, color: '#2E2E30' })

        // Interactive circular dark pill zoom toggle (1x / 2x)
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
        .scale(this.pressedButtonId === 'home_zoom' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 16 })
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('home_zoom', e);
        })
        .onClick(() => {
          this.toggleZoom();
        })
      }
      .width('94%')
      .constraintSize({ maxWidth: 400 })
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

      // Shutter Row: Gallery 52x52 | Shutter 84x84 | Flip 52x52
      Row() {
        // Left Gallery button
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
        .scale(this.pressedButtonId === 'home_gallery'
          ? { x: 0.91, y: 0.91 }
          : { x: this.galleryPulseScale, y: this.galleryPulseScale })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('home_gallery', e);
        })
        .onClick(() => {
          this.pickFromGallery();
        })

        // Center 84x84 Shutter circle (#FFB800 4.5vp ring + golden glow + elastic press-scale)
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
        .onTouch((event: TouchEvent) => {
          this.handleShutterTouch(event);
        })
        .onClick(() => {
          this.handleShutterCapture();
        })

        // Right Flip icon
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
        .scale(this.pressedButtonId === 'home_flip' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('home_flip', e);
        })
        .onClick(() => {
          this.flipCamera();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 22 })

      // History cue below shutter
      Row({ space: 10 }) {
        Column() {
          Text(`${this.moments.length}+`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFB800')
        }
        .height(28)
        .padding({ left: 10, right: 10 })
        .borderRadius(14)
        .backgroundColor('#6E5200')
        .justifyContent(FlexAlign.Center)

        Text('Lịch sử ⌄')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .margin({ top: 14 })
      .scale(this.pressedButtonId === 'home_history_cue' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
      .onTouch((e: TouchEvent) => {
        this.handleButtonTouch('home_history_cue', e);
      })
      .onClick(() => {
        this.switchViewMode('feed');
      })

      Blank()

      // Bottom floating pill nav (height 58, borderRadius 29, icons 24x24)
      Row({ space: 8 }) {
        // Grid / Calendar icon
        Column() {
          Image($r('app.media.ic_grid'))
            .width(24)
            .height(24)
            .fillColor('#8E8E93')
        }
        .width(56)
        .height(44)
        .borderRadius(22)
        .scale(this.pressedButtonId === 'cam_tab_grid' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('cam_tab_grid', e);
        })
        .onClick(() => {
          this.switchViewMode('grid');
        })

        // Home highlighted pill
        Column() {
          Image($r('app.media.ic_home'))
            .width(24)
            .height(24)
            .fillColor('#FFFFFF')
        }
        .width(68)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#262628')
        .scale(this.pressedButtonId === 'cam_tab_home' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('cam_tab_home', e);
        })
        .onClick(() => {
          this.switchViewMode('camera');
        })

        // Chat icon -> Messages tab
        Column() {
          Image($r('app.media.ic_chat'))
            .width(24)
            .height(24)
            .fillColor('#8E8E93')
        }
        .width(56)
        .height(44)
        .borderRadius(22)
        .scale(this.pressedButtonId === 'cam_tab_chat' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('cam_tab_chat', e);
        })
        .onClick(() => {
          this.switchViewMode('messages');
        })
      }
      .height(58)
      .padding({ left: 8, right: 8 })
      .borderRadius(29)
      .backgroundColor('#141416')
      .border({ width: 1, color: '#2E2E30' })
      .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
      .margin({ bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .transition(this.buildDirectionalTransition())
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
            .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
            .scale(this.pressedButtonId === 'feed_retry' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .padding({ left: 26, right: 26 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('feed_retry', e);
            })
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
            .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
            .scale(this.pressedButtonId === 'feed_refresh' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .padding({ left: 26, right: 26 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('feed_refresh', e);
            })
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
                // Large 1:1 Photo Card (94% width, max 400vp, borderRadius 48) + translucent caption pill
                Stack({ alignContent: Alignment.Bottom }) {
                  Image(item.thumbnailUrl)
                    .width('100%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(48)
                    .backgroundColor('#141416')

                  if (item.caption.length > 0) {
                    Text(item.caption)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                      .backgroundColor('#993A3A3C')
                      .borderRadius(20)
                      .margin({ bottom: 16, left: 18, right: 18 })
                  }
                }
                .width('94%')
                .constraintSize({ maxWidth: 400 })

                // Sender row: 28x28 avatar + bold white name + muted short relative time
                Row({ space: 8 }) {
                  if (item.senderAvatar.length > 0) {
                    Image(item.senderAvatar)
                      .width(26)
                      .height(26)
                      .borderRadius(13)
                      .objectFit(ImageFit.Cover)
                  } else {
                    Column() {
                      Text(item.senderName.length > 0 ? item.senderName.substring(0, 1).toUpperCase() : 'L')
                        .fontSize(12)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                    }
                    .width(26)
                    .height(26)
                    .borderRadius(13)
                    .backgroundColor('#2C2C2E')
                    .justifyContent(FlexAlign.Center)
                  }

                  Text(item.senderName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                    .maxLines(1)

                  Text(this.formatShortRelativeTime(item.createdAtSeconds))
                    .fontSize(13)
                    .fontColor('#8E8E93')
                }
                .margin({ top: 12 })
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .height('100%')
              .alignItems(HorizontalAlign.Center)
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

        // Combined Reply + Reaction Pill Bar (94% width, height 54, radius 27, fontSize 16)
        Row({ space: 6 }) {
          TextInput({ placeholder: 'Gửi tin nhắn...', text: this.replyText })
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .placeholderColor('#8E8E93')
            .caretColor('#FFB800')
            .backgroundColor(Color.Transparent)
            .padding({ left: 12, right: 6 })
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
            .width(42)
            .height(42)
            .backgroundColor('#FFB800')
            .borderRadius(21)
            .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
            .scale(this.pressedButtonId === 'feed_send_reply' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .justifyContent(FlexAlign.Center)
            .enabled(!this.isSendingReply)
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('feed_send_reply', e);
            })
            .onClick(() => {
              const current = this.getCurrentMoment();
              if (current !== null) {
                this.handleSendQuickReply(current);
              }
            })
          } else {
            Text('💛')
              .fontSize(22)
              .padding({ left: 4, right: 4 })
              .scale(this.pressedButtonId === 'feed_react_heart' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
              .onTouch((e: TouchEvent) => {
                this.handleButtonTouch('feed_react_heart', e);
              })
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleReact(current.canonicalUid, '💛');
                }
              })
            Text('🔥')
              .fontSize(22)
              .padding({ left: 4, right: 4 })
              .scale(this.pressedButtonId === 'feed_react_fire' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
              .onTouch((e: TouchEvent) => {
                this.handleButtonTouch('feed_react_fire', e);
              })
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleReact(current.canonicalUid, '🔥');
                }
              })
            Text('😍')
              .fontSize(22)
              .padding({ left: 4, right: 4 })
              .scale(this.pressedButtonId === 'feed_react_love' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
              .onTouch((e: TouchEvent) => {
                this.handleButtonTouch('feed_react_love', e);
              })
              .onClick(() => {
                const current = this.getCurrentMoment();
                if (current !== null) {
                  this.handleReact(current.canonicalUid, '😍');
                }
              })
            Column() {
              Image($r('app.media.ic_emoji_add'))
                .width(22)
                .height(22)
                .fillColor('#FFFFFF')
            }
            .width(36)
            .height(36)
            .scale(this.pressedButtonId === 'feed_react_more' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .justifyContent(FlexAlign.Center)
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('feed_react_more', e);
            })
            .onClick(() => {
              const current = this.getCurrentMoment();
              if (current !== null) {
                this.handleReact(current.canonicalUid, '😂');
              }
            })
          }
        }
        .width('94%')
        .height(54)
        .padding({ left: 10, right: 10 })
        .margin({ bottom: 12 })
        .borderRadius(27)
        .backgroundColor('#1C1C1E')
        .border({ width: 1, color: '#2E2E30' })
        .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
      }

      // Bottom Controls Row (side circles 52x52, center pill height 58, icons 24x24)
      Row() {
        // Left 52x52 circle: 4-squares Grid icon
        Column() {
          Image($r('app.media.ic_grid'))
            .width(24)
            .height(24)
            .fillColor('#FFFFFF')
        }
        .width(52)
        .height(52)
        .borderRadius(26)
        .backgroundColor('#1A1A1C')
        .border({ width: 1, color: '#2E2E30' })
        .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
        .scale(this.pressedButtonId === 'feed_grid_btn' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('feed_grid_btn', e);
        })
        .onClick(() => {
          this.switchViewMode('grid');
        })

        Blank()

        // Center pill (height 58, radius 29): Calendar | 42x42 mini shutter | Chat
        Row({ space: 20 }) {
          Image($r('app.media.ic_calendar'))
            .width(24)
            .height(24)
            .fillColor('#FFFFFF')
            .scale(this.pressedButtonId === 'feed_pill_cal' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('feed_pill_cal', e);
            })
            .onClick(() => {
              this.switchViewMode('grid');
            })

          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(42)
              .height(42)
              .borderRadius(21)
              .backgroundColor('#000000')
              .border({ width: 3.5, color: '#FFB800' })
              .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
            Column()
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor('#FFFFFF')
          }
          .scale(this.pressedButtonId === 'feed_pill_cam' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
          .onTouch((e: TouchEvent) => {
            this.handleButtonTouch('feed_pill_cam', e);
          })
          .onClick(() => {
            this.switchViewMode('camera');
          })

          Image($r('app.media.ic_chat'))
            .width(24)
            .height(24)
            .fillColor('#FFFFFF')
            .scale(this.pressedButtonId === 'feed_pill_chat' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
            .onTouch((e: TouchEvent) => {
              this.handleButtonTouch('feed_pill_chat', e);
            })
            .onClick(() => {
              this.switchViewMode('messages');
            })
        }
        .height(58)
        .padding({ left: 22, right: 22 })
        .borderRadius(29)
        .backgroundColor('#1A1A1C')
        .border({ width: 1, color: '#2E2E30' })
        .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })

        Blank()

        // Right 52x52 circle: Share/Delete icon
        Column() {
          if (this.isOwnMoment(this.getCurrentMoment())) {
            Image($r('app.media.ic_trash'))
              .width(24)
              .height(24)
              .fillColor('#FF453A')
          } else {
            Image($r('app.media.ic_share'))
              .width(24)
              .height(24)
              .fillColor('#FFFFFF')
          }
        }
        .width(52)
        .height(52)
        .borderRadius(26)
        .backgroundColor('#1A1A1C')
        .border({ width: 1, color: '#2E2E30' })
        .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
        .scale(this.pressedButtonId === 'feed_action_btn' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('feed_action_btn', e);
        })
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
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .transition(this.buildDirectionalTransition())
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
        .padding({ left: 8, right: 8, top: 4, bottom: this.safeBottomVp + 96 })
        .scrollBar(BarState.Off)
      }

      // Bottom-up Progressive Frosted Blur Scrim behind floating pill
      Column()
        .width('100%')
        .height(this.safeBottomVp + 108)
        .hitTestBehavior(HitTestMode.Transparent)
        .backdropBlur(22)
        .linearGradient({
          direction: GradientDirection.Top,
          colors: [['#F0000000', 0.0], ['#A6000000', 0.52], ['#00000000', 1.0]]
        })

      // Floating bottom center pill overlay (#CC1C1C1E, height 58, radius 29, icons 24x24)
      Row({ space: 22 }) {
        Image($r('app.media.ic_grid'))
          .width(24)
          .height(24)
          .fillColor('#FFB800')
          .scale(this.pressedButtonId === 'grid_tab_grid' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
          .onTouch((e: TouchEvent) => {
            this.handleButtonTouch('grid_tab_grid', e);
          })
          .onClick(() => {
            this.switchViewMode('grid');
          })

        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(42)
            .height(42)
            .borderRadius(21)
            .backgroundColor('#000000')
            .border({ width: 3.5, color: '#FFB800' })
            .shadow({ radius: 24, color: '#73FFB800', offsetX: 0, offsetY: 5 })
          Column()
            .width(32)
            .height(32)
            .borderRadius(16)
            .backgroundColor('#FFFFFF')
        }
        .scale(this.pressedButtonId === 'grid_tab_cam' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('grid_tab_cam', e);
        })
        .onClick(() => {
          this.switchViewMode('camera');
        })

        Image($r('app.media.ic_chat'))
          .width(24)
          .height(24)
          .fillColor('#FFFFFF')
          .scale(this.pressedButtonId === 'grid_tab_chat' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
          .onTouch((e: TouchEvent) => {
            this.handleButtonTouch('grid_tab_chat', e);
          })
          .onClick(() => {
            this.switchViewMode('messages');
          })
      }
      .height(58)
      .padding({ left: 22, right: 22 })
      .borderRadius(29)
      .backgroundColor('#CC1C1C1E')
      .backdropBlur(20)
      .border({ width: 1, color: '#2E2E30' })
      .shadow({ radius: 20, color: '#80000000', offsetX: 0, offsetY: 6 })
      .margin({ bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .transition(this.buildDirectionalTransition())
  }

  @Builder
  private buildMessagesMode() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // Dedicated Messages Header: centered bold "Trò chuyện" + right circular user avatar
        Row() {
          Column()
            .width(48)
            .height(48)

          Blank()

          Text('Trò chuyện')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')

          Blank()

          this.buildProfileAvatarButton()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 10 })

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

      // Bottom bar: clean centered 3-icon floating pill (height 58, borderRadius 29, icons 24x24)
      Row({ space: 8 }) {
        Column() {
          Image($r('app.media.ic_grid'))
            .width(24)
            .height(24)
            .fillColor('#8E8E93')
        }
        .width(56)
        .height(44)
        .borderRadius(22)
        .scale(this.pressedButtonId === 'msg_tab_grid' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('msg_tab_grid', e);
        })
        .onClick(() => {
          this.switchViewMode('grid');
        })

        Column() {
          Image($r('app.media.ic_home'))
            .width(24)
            .height(24)
            .fillColor('#8E8E93')
        }
        .width(56)
        .height(44)
        .borderRadius(22)
        .scale(this.pressedButtonId === 'msg_tab_home' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('msg_tab_home', e);
        })
        .onClick(() => {
          this.switchViewMode('camera');
        })

        // Highlighted Chat pill
        Column() {
          Image($r('app.media.ic_chat'))
            .width(24)
            .height(24)
            .fillColor('#FFFFFF')
        }
        .width(68)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#262628')
        .scale(this.pressedButtonId === 'msg_tab_chat' ? { x: 0.91, y: 0.91 } : { x: 1, y: 1 })
        .justifyContent(FlexAlign.Center)
        .onTouch((e: TouchEvent) => {
          this.handleButtonTouch('msg_tab_chat', e);
        })
        .onClick(() => {
          this.loadMessagesTab();
        })
      }
      .height(58)
      .padding({ left: 8, right: 8 })
      .borderRadius(29)
      .backgroundColor('#141416')
      .border({ width: 1, color: '#2E2E30' })
      .shadow({ radius: 14, color: '#59000000', offsetX: 0, offsetY: 4 })
      .margin({ bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .transition(this.buildDirectionalTransition())
  }

  @Builder
  private buildFriendFilterSheet() {
    Stack({ alignContent: Alignment.Top }) {
      // Semi-transparent backdrop tapping to dismiss
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
            this.showFriendFilter = false;
          });
        })

      // Centered floating dark dropdown card right below the top bar
      Column() {
        Text('Lọc ảnh theo bạn bè')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#8E8E93')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 12 })

        Divider().color('#2E2E30')

        Scroll() {
          Column({ space: 4 }) {
            // First option: Tất cả bạn bè
            Row({ space: 12 }) {
              Column() {
                Image($r('app.media.ic_friends'))
                  .width(18)
                  .height(18)
                  .fillColor(this.filterUid === '' ? '#000000' : '#FFFFFF')
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor(this.filterUid === '' ? '#FFB800' : '#2C2C2E')
              .justifyContent(FlexAlign.Center)

              Text('Tất cả bạn bè')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.filterUid === '' ? '#FFB800' : '#FFFFFF')
                .layoutWeight(1)

              if (this.filterUid === '') {
                Text('✓')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFB800')
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(14)
            .backgroundColor(this.filterUid === '' ? '#262628' : Color.Transparent)
            .onClick(() => {
              this.selectFriendFilter('', 'Tất cả bạn bè');
            })

            // Friend list options
            ForEach(this.allFriends, (friend: FriendItem) => {
              Row({ space: 12 }) {
                if (friend.profilePictureUrl.length > 0) {
                  Image(friend.profilePictureUrl)
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .objectFit(ImageFit.Cover)
                    .border({
                      width: this.filterUid === friend.uid ? 2 : 1,
                      color: this.filterUid === friend.uid ? '#FFB800' : '#3A3A3C'
                    })
                } else {
                  Column() {
                    Text(getDisplayName(friend).substring(0, 1).toUpperCase())
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                  }
                  .width(36)
                  .height(36)
                  .borderRadius(18)
                  .backgroundColor('#2C2C2E')
                  .border({
                    width: this.filterUid === friend.uid ? 2 : 1,
                    color: this.filterUid === friend.uid ? '#FFB800' : '#3A3A3C'
                  })
                  .justifyContent(FlexAlign.Center)
                }

                Text(getDisplayName(friend))
                  .fontSize(15)
                  .fontWeight(this.filterUid === friend.uid ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.filterUid === friend.uid ? '#FFB800' : '#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                if (this.filterUid === friend.uid) {
                  Column()
                    .width(10)
                    .height(10)
                    .borderRadius(5)
                    .backgroundColor('#FFB800')
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(14)
              .backgroundColor(this.filterUid === friend.uid ? '#262628' : Color.Transparent)
              .onClick(() => {
                this.selectFriendFilter(friend.uid, getDisplayName(friend));
              })
            }, (friend: FriendItem) => friend.uid)
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 8, bottom: 10 })
        }
        .width('100%')
        .constraintSize({ maxHeight: 340 })
        .scrollBar(BarState.Off)
      }
      .width('84%')
      .constraintSize({ maxHeight: '60%' })
      .backgroundColor('#1C1C1E')
      .borderRadius(24)
      .border({ width: 1, color: '#2E2E30' })
      .shadow({ radius: 28, color: '#88000000', offsetX: 0, offsetY: 10 })
      .margin({ top: this.safeTopVp + 64 })
      .transition(
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -12 }))
          .animation({ duration: 220, curve: Curve.EaseOut })
      )
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
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
      .padding({ top: this.safeTopVp, bottom: this.safeBottomVp })

      if (this.showFriendFilter && (this.viewMode === 'feed' || this.viewMode === 'grid')) {
        this.buildFriendFilterSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
