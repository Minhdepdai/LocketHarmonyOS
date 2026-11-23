import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const CAMERA_LOG_DOMAIN = 0x0000;
const CAMERA_LOG_TAG = 'LocketCamera';

export class LiveCameraController {
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private photoSession: camera.PhotoSession | null = null;
  private isRunning: boolean = false;
  private isCapturing: boolean = false;
  private currentIsFront: boolean = false;
  private pendingCaptureContext: common.UIAbilityContext | null = null;
  private pendingResolve: ((path: string) => void) | null = null;
  private pendingReject: ((err: Error) => void) | null = null;
  private captureTimeoutId: number = -1;
  public currentZoomRatio: number = 1.0;

  private formatBizError(err: BusinessError | Error | Object): string {
    if (err instanceof Error) {
      const biz = err as BusinessError;
      const codeStr = biz.code !== undefined ? `${biz.code}` : 'none';
      return `code=${codeStr}, message=${err.message}`;
    }
    const biz = err as BusinessError;
    return `code=${biz.code !== undefined ? `${biz.code}` : 'none'}, message=${biz.message ?? String(err)}`;
  }

  public isSessionRunning(): boolean {
    return this.isRunning;
  }

  public getZoomRange(): number[] {
    if (this.photoSession === null || !this.isRunning) {
      return [1.0, 4.0];
    }
    try {
      const range = this.photoSession.getZoomRatioRange();
      if (range !== undefined && range.length >= 2) {
        return [range[0], range[1]];
      }
    } catch (err) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `getZoomRange failed: ${this.formatBizError(err as BusinessError)}`);
    }
    return [1.0, 4.0];
  }

  public setZoomRatio(ratio: number): number {
    const range = this.getZoomRange();
    const minZoom = range[0];
    const maxZoom = range[1];
    const clamped = Math.min(maxZoom, Math.max(minZoom, ratio));
    const rounded = Math.round(clamped * 100) / 100;
    this.currentZoomRatio = rounded;
    if (this.photoSession !== null && this.isRunning) {
      try {
        this.photoSession.setZoomRatio(rounded);
      } catch (err) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `setZoomRatio(${rounded}) failed: ${this.formatBizError(err as BusinessError)}`);
      }
    }
    return this.currentZoomRatio;
  }

  public async requestCameraPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
      const result = await atManager.requestPermissionsFromUser(context, permissions);
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `init: permission result granted=${granted}`);
      return granted;
    } catch (err) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `init: requestCameraPermission failed: ${this.formatBizError(err as BusinessError)}`);
      return false;
    }
  }

  private selectCameraDevice(cameras: Array<camera.CameraDevice>, isFront: boolean): camera.CameraDevice | null {
    if (cameras.length === 0) {
      return null;
    }
    const targetPosition = isFront
      ? camera.CameraPosition.CAMERA_POSITION_FRONT
      : camera.CameraPosition.CAMERA_POSITION_BACK;
    for (let i = 0; i < cameras.length; i++) {
      if (cameras[i].cameraPosition === targetPosition) {
        return cameras[i];
      }
    }
    return cameras[0];
  }

  private selectPreviewProfile(profiles: Array<camera.Profile>): camera.Profile | null {
    if (profiles.length === 0) {
      return null;
    }
    for (let i = 0; i < profiles.length; i++) {
      const p = profiles[i];
      if (p.size.width >= 720 && p.size.height >= 720) {
        return p;
      }
    }
    return profiles[0];
  }

  private selectPhotoProfile(profiles: Array<camera.Profile>): camera.Profile | null {
    if (profiles.length === 0) {
      return null;
    }
    for (let i = 0; i < profiles.length; i++) {
      const p = profiles[i];
      if (p.format === camera.CameraFormat.CAMERA_FORMAT_JPEG && p.size.width >= 720) {
        return p;
      }
    }
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].format === camera.CameraFormat.CAMERA_FORMAT_JPEG) {
        return profiles[i];
      }
    }
    return profiles[0];
  }

  public async startSession(
    context: common.UIAbilityContext,
    surfaceId: string,
    isFront: boolean
  ): Promise<boolean> {
    hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
      `init: startSession called (isFront=${isFront}, surfaceIdLen=${surfaceId.length})`);
    if (surfaceId.length === 0) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'init: aborted because surfaceId is empty');
      return false;
    }
    await this.release();

    const granted = await this.requestCameraPermission(context);
    if (!granted) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'init: camera permission denied');
      return false;
    }

    try {
      const manager = camera.getCameraManager(context);
      this.cameraManager = manager;
      const cameras = manager.getSupportedCameras();
      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `init: supportedCameras count=${cameras.length}`);
      const device = this.selectCameraDevice(cameras, isFront);
      if (device === null) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          'init: no camera device found');
        return false;
      }
      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `init: selected cameraId=${device.cameraId}, position=${device.cameraPosition}`);

      const capability = manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const previewProfile = this.selectPreviewProfile(capability.previewProfiles);
      const photoProfile = this.selectPhotoProfile(capability.photoProfiles);
      if (previewProfile === null || photoProfile === null) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `init: missing profile (preview=${previewProfile !== null}, photo=${photoProfile !== null})`);
        return false;
      }
      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `session config: preview=${previewProfile.size.width}x${previewProfile.size.height}, photo=${photoProfile.size.width}x${photoProfile.size.height}, photoFormat=${photoProfile.format}`);

      const previewOut = manager.createPreviewOutput(previewProfile, surfaceId);
      const photoOut = manager.createPhotoOutput(photoProfile);
      photoOut.on('photoAvailable', (err: BusinessError, photo: camera.Photo) => {
        this.handlePhotoAvailable(err, photo);
      });
      const input = manager.createCameraInput(device);
      const session = manager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;

      this.previewOutput = previewOut;
      this.photoOutput = photoOut;
      this.cameraInput = input;
      this.photoSession = session;

      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'session config: opening cameraInput and committing session config');
      await input.open();
      session.beginConfig();
      session.addInput(input);
      session.addOutput(previewOut);
      session.addOutput(photoOut);
      await session.commitConfig();
      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'start: commitConfig succeeded, starting photoSession');
      await session.start();

      this.currentIsFront = isFront;
      this.isRunning = true;
      this.currentZoomRatio = 1.0;
      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `start: photoSession started successfully (isFront=${isFront})`);
      return true;
    } catch (err) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `startSession failed: ${this.formatBizError(err as BusinessError)}`);
      await this.release();
      return false;
    }
  }

  private clearPendingCapture(): void {
    if (this.captureTimeoutId !== -1) {
      clearTimeout(this.captureTimeoutId);
      this.captureTimeoutId = -1;
    }
    this.isCapturing = false;
    this.pendingCaptureContext = null;
    this.pendingResolve = null;
    this.pendingReject = null;
  }

  private rejectPendingCapture(message: string): void {
    const rejectFn = this.pendingReject;
    this.clearPendingCapture();
    if (rejectFn !== null) {
      rejectFn(new Error(message));
    }
  }

  private resolvePendingCapture(filePath: string): void {
    const resolveFn = this.pendingResolve;
    this.clearPendingCapture();
    if (resolveFn !== null) {
      resolveFn(filePath);
    }
  }

  private releasePhotoResources(mainImage: image.Image | null, photo: camera.Photo | null): void {
    if (mainImage !== null) {
      try {
        mainImage.release();
      } catch (_e) {
        // Ignore
      }
    }
    if (photo !== null) {
      try {
        photo.release();
      } catch (_e) {
        // Ignore
      }
    }
  }

  private handlePhotoAvailable(err: BusinessError, photo: camera.Photo): void {
    hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
      `photoAvailable received (hasErr=${err !== undefined && err !== null && err.code !== 0})`);
    if (err !== undefined && err !== null && err.code !== 0) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `photoAvailable callback error: code=${err.code}, message=${err.message ?? ''}`);
      this.releasePhotoResources(null, photo ?? null);
      this.rejectPendingCapture(`${err.message ?? 'Không thể chụp ảnh'} (code: ${err.code})`);
      return;
    }
    if (photo === undefined || photo === null) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'photoAvailable error: photo object is null/undefined');
      this.rejectPendingCapture('Không thể đọc dữ liệu ảnh');
      return;
    }
    const mainImage = photo.main;
    if (mainImage === undefined || mainImage === null) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'photoAvailable error: photo.main is null/undefined');
      this.releasePhotoResources(null, photo);
      this.rejectPendingCapture('Không thể đọc dữ liệu ảnh');
      return;
    }
    const ctx = this.pendingCaptureContext;
    if (ctx === null) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'photoAvailable ignored: pendingCaptureContext is null');
      this.releasePhotoResources(mainImage, photo);
      return;
    }

    try {
      hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'image read: calling mainImage.getComponent(JPEG)');
      mainImage.getComponent(image.ComponentType.JPEG, (compErr: BusinessError, component: image.Component) => {
        try {
          if (compErr !== undefined && compErr !== null && compErr.code !== 0) {
            hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
              `image read getComponent error: code=${compErr.code}, message=${compErr.message ?? ''}`);
            this.rejectPendingCapture(`${compErr.message ?? 'Không thể đọc dữ liệu ảnh'} (code: ${compErr.code})`);
            return;
          }
          if (component === undefined || component === null ||
            component.byteBuffer === undefined || component.byteBuffer.byteLength === 0) {
            hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
              'image read error: empty JPEG byteBuffer');
            this.rejectPendingCapture('Không thể đọc dữ liệu ảnh');
            return;
          }
          const copied = new Uint8Array(component.byteBuffer).slice().buffer;
          const filePath = `${ctx.cacheDir}/locket_capture_${Date.now()}.jpg`;
          const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
          try {
            fileIo.writeSync(file.fd, copied);
          } finally {
            fileIo.closeSync(file);
          }
          hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
            `image read success: bytes=${copied.byteLength}, filePath=${filePath}`);
          this.resolvePendingCapture(filePath);
        } catch (writeErr) {
          hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
            `image read/write failed: ${this.formatBizError(writeErr as BusinessError)}`);
          const msg = writeErr instanceof Error ? writeErr.message : 'Lưu ảnh thất bại';
          this.rejectPendingCapture(msg);
        } finally {
          this.releasePhotoResources(mainImage, photo);
        }
      });
    } catch (e) {
      this.releasePhotoResources(mainImage, photo);
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        `image read exception: ${this.formatBizError(e as BusinessError)}`);
      const msg = e instanceof Error ? e.message : 'Không thể đọc dữ liệu ảnh';
      this.rejectPendingCapture(msg);
    }
  }

  public async capturePhotoToFile(context: common.UIAbilityContext): Promise<string> {
    hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
      `capture called: isRunning=${this.isRunning}, isCapturing=${this.isCapturing}, isFront=${this.currentIsFront}`);
    if (this.photoOutput === null || !this.isRunning) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'capture error: camera session is not ready');
      throw new Error('Camera chưa sẵn sàng');
    }
    if (this.isCapturing) {
      hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
        'capture error: capture already in progress');
      throw new Error('Đang chụp ảnh...');
    }
    this.isCapturing = true;
    const output = this.photoOutput;

    return new Promise<string>((resolve, reject) => {
      this.pendingCaptureContext = context;
      this.pendingResolve = resolve;
      this.pendingReject = reject;
      this.captureTimeoutId = setTimeout(() => {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          'capture timeout after 10000ms');
        this.rejectPendingCapture('Chụp ảnh quá thời gian chờ');
      }, 10000);

      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: camera.ImageRotation.ROTATION_0
      };
      let mirrorSupported = false;
      try {
        mirrorSupported = output.isMirrorSupported();
        hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `capture called: isMirrorSupported=${mirrorSupported}`);
      } catch (mirrorErr) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `capture: isMirrorSupported error: ${this.formatBizError(mirrorErr as BusinessError)}`);
      }
      if (mirrorSupported) {
        setting.mirror = this.currentIsFront;
      }

      const executeCapture = async (): Promise<void> => {
        try {
          hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
            `capture called: invoking photoOutput.capture(setting) mirror=${setting.mirror !== undefined ? String(setting.mirror) : 'omitted'}`);
          await output.capture(setting);
        } catch (capErr) {
          hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
            `capture(setting) failed: ${this.formatBizError(capErr as BusinessError)}; retrying photoOutput.capture() without args`);
          await output.capture();
        }
      };

      executeCapture().catch((retryErr: BusinessError) => {
        const code = retryErr?.code ?? -1;
        const msg = retryErr?.message ?? 'Chụp ảnh thất bại';
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `capture() retry failed: code=${code}, message=${msg}`);
        this.rejectPendingCapture(`${msg} (code: ${code})`);
      });
    });
  }

  public async release(): Promise<void> {
    hilog.info(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s', 'release: stopping camera session');
    this.isRunning = false;
    if (this.pendingReject !== null || this.isCapturing) {
      this.rejectPendingCapture('Camera đã đóng');
    } else {
      this.clearPendingCapture();
    }
    this.currentZoomRatio = 1.0;
    if (this.photoOutput !== null) {
      try {
        this.photoOutput.off('photoAvailable');
      } catch (err) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `release photoOutput.off error: ${this.formatBizError(err as BusinessError)}`);
      }
    }
    if (this.photoSession !== null) {
      try {
        await this.photoSession.stop();
      } catch (err) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `release photoSession.stop error: ${this.formatBizError(err as BusinessError)}`);
      }
      try {
        await this.photoSession.release();
      } catch (err) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `release photoSession.release error: ${this.formatBizError(err as BusinessError)}`);
      }
      this.photoSession = null;
    }
    if (this.cameraInput !== null) {
      try {
        await this.cameraInput.close();
      } catch (err) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `release cameraInput.close error: ${this.formatBizError(err as BusinessError)}`);
      }
      this.cameraInput = null;
    }
    if (this.previewOutput !== null) {
      try {
        await this.previewOutput.release();
      } catch (err) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `release previewOutput.release error: ${this.formatBizError(err as BusinessError)}`);
      }
      this.previewOutput = null;
    }
    if (this.photoOutput !== null) {
      try {
        await this.photoOutput.release();
      } catch (err) {
        hilog.error(CAMERA_LOG_DOMAIN, CAMERA_LOG_TAG, '%{public}s',
          `release photoOutput.release error: ${this.formatBizError(err as BusinessError)}`);
      }
      this.photoOutput = null;
    }
    this.cameraManager = null;
  }
}
