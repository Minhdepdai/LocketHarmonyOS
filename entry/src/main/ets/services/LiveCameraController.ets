import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

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
    } catch (_err) {
      // Fallback to standard range
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
      } catch (_err) {
        // Ignore unsupported zoom hardware error
      }
    }
    return this.currentZoomRatio;
  }

  public async requestCameraPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
      const result = await atManager.requestPermissionsFromUser(context, permissions);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (_err) {
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
    if (surfaceId.length === 0) {
      return false;
    }
    await this.release();

    const granted = await this.requestCameraPermission(context);
    if (!granted) {
      return false;
    }

    try {
      const manager = camera.getCameraManager(context);
      this.cameraManager = manager;
      const cameras = manager.getSupportedCameras();
      const device = this.selectCameraDevice(cameras, isFront);
      if (device === null) {
        return false;
      }

      const capability = manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const previewProfile = this.selectPreviewProfile(capability.previewProfiles);
      const photoProfile = this.selectPhotoProfile(capability.photoProfiles);
      if (previewProfile === null || photoProfile === null) {
        return false;
      }

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

      await input.open();
      session.beginConfig();
      session.addInput(input);
      session.addOutput(previewOut);
      session.addOutput(photoOut);
      await session.commitConfig();
      await session.start();

      this.currentIsFront = isFront;
      this.isRunning = true;
      this.currentZoomRatio = 1.0;
      return true;
    } catch (_err) {
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
    if (err !== undefined && err !== null && err.code !== 0) {
      this.releasePhotoResources(null, photo ?? null);
      this.rejectPendingCapture(`CAMERA_CAPTURE_FALLBACK_REQUIRED: ${err.message ?? 'Không thể chụp ảnh'}`);
      return;
    }
    if (photo === undefined || photo === null) {
      this.rejectPendingCapture('CAMERA_CAPTURE_FALLBACK_REQUIRED: Không thể đọc dữ liệu ảnh');
      return;
    }
    const mainImage = photo.main;
    if (mainImage === undefined || mainImage === null) {
      this.releasePhotoResources(null, photo);
      this.rejectPendingCapture('CAMERA_CAPTURE_FALLBACK_REQUIRED: Không thể đọc dữ liệu ảnh');
      return;
    }
    const ctx = this.pendingCaptureContext;
    if (ctx === null) {
      this.releasePhotoResources(mainImage, photo);
      return;
    }

    try {
      mainImage.getComponent(image.ComponentType.JPEG, (compErr: BusinessError, component: image.Component) => {
        try {
          if (compErr !== undefined && compErr !== null && compErr.code !== 0) {
            this.rejectPendingCapture(`CAMERA_CAPTURE_FALLBACK_REQUIRED: ${compErr.message ?? 'Không thể đọc dữ liệu ảnh'}`);
            return;
          }
          if (component === undefined || component === null ||
            component.byteBuffer === undefined || component.byteBuffer.byteLength === 0) {
            this.rejectPendingCapture('CAMERA_CAPTURE_FALLBACK_REQUIRED: Không thể đọc dữ liệu ảnh');
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
          this.resolvePendingCapture(filePath);
        } catch (writeErr) {
          const msg = writeErr instanceof Error ? writeErr.message : 'Lưu ảnh thất bại';
          this.rejectPendingCapture(`CAMERA_CAPTURE_FALLBACK_REQUIRED: ${msg}`);
        } finally {
          this.releasePhotoResources(mainImage, photo);
        }
      });
    } catch (e) {
      this.releasePhotoResources(mainImage, photo);
      const msg = e instanceof Error ? e.message : 'Không thể đọc dữ liệu ảnh';
      this.rejectPendingCapture(`CAMERA_CAPTURE_FALLBACK_REQUIRED: ${msg}`);
    }
  }

  public async capturePhotoToFile(context: common.UIAbilityContext): Promise<string> {
    if (this.photoOutput === null || !this.isRunning) {
      throw new Error('CAMERA_CAPTURE_FALLBACK_REQUIRED: Camera chưa sẵn sàng');
    }
    if (this.isCapturing) {
      throw new Error('Đang chụp ảnh...');
    }
    this.isCapturing = true;
    const output = this.photoOutput;

    return new Promise<string>((resolve, reject) => {
      this.pendingCaptureContext = context;
      this.pendingResolve = resolve;
      this.pendingReject = reject;
      this.captureTimeoutId = setTimeout(() => {
        this.rejectPendingCapture('CAMERA_CAPTURE_FALLBACK_REQUIRED: Chụp ảnh quá thời gian chờ');
      }, 10000);

      try {
        const setting: camera.PhotoCaptureSetting = {
          quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
          rotation: camera.ImageRotation.ROTATION_0,
          mirror: this.currentIsFront
        };
        output.capture(setting).catch((capErr: BusinessError) => {
          this.rejectPendingCapture(`CAMERA_CAPTURE_FALLBACK_REQUIRED: ${capErr.message ?? 'Chụp ảnh thất bại'}`);
        });
      } catch (e) {
        const msg = e instanceof Error ? e.message : 'Lỗi camera';
        this.rejectPendingCapture(`CAMERA_CAPTURE_FALLBACK_REQUIRED: ${msg}`);
      }
    });
  }

  public async pickPhotoWithSystemCamera(context: common.UIAbilityContext, isFront: boolean): Promise<string> {
    await this.release();
    const pickerProfile: cameraPicker.PickerProfile = {
      cameraPosition: isFront
        ? camera.CameraPosition.CAMERA_POSITION_FRONT
        : camera.CameraPosition.CAMERA_POSITION_BACK
    };
    const pickerResult: cameraPicker.PickerResult = await cameraPicker.pick(
      context,
      [cameraPicker.PickerMediaType.PHOTO],
      pickerProfile
    );
    if (pickerResult.resultCode === 0 && pickerResult.resultUri.length > 0) {
      return pickerResult.resultUri;
    }
    return '';
  }

  public async release(): Promise<void> {
    this.isRunning = false;
    this.rejectPendingCapture('Camera đã đóng');
    this.currentZoomRatio = 1.0;
    if (this.photoOutput !== null) {
      try {
        this.photoOutput.off('photoAvailable');
      } catch (_err) {
        // Ignore
      }
    }
    if (this.photoSession !== null) {
      try {
        await this.photoSession.stop();
      } catch (_err) {
        // Ignore
      }
      try {
        await this.photoSession.release();
      } catch (_err) {
        // Ignore
      }
      this.photoSession = null;
    }
    if (this.cameraInput !== null) {
      try {
        await this.cameraInput.close();
      } catch (_err) {
        // Ignore
      }
      this.cameraInput = null;
    }
    if (this.previewOutput !== null) {
      try {
        await this.previewOutput.release();
      } catch (_err) {
        // Ignore
      }
      this.previewOutput = null;
    }
    if (this.photoOutput !== null) {
      try {
        await this.photoOutput.release();
      } catch (_err) {
        // Ignore
      }
      this.photoOutput = null;
    }
    this.cameraManager = null;
  }
}
