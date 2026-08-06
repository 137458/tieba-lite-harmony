// 图片查看器页面
// 基于 @rv/image-preview 三方库实现缩放/平移/双击等手势交互
// 调用方：RouterUtil.pushImageViewer(urls, index)
//
// 保存到相册流程：
// - 长按图片 → 异步下载到应用沙箱临时文件（filesDir/imgviewer_<ts>.<ext>）
// - 下载完成后显示 SaveButton 浮层（用户点击授予 5 秒临时授权）
// - 授权后调用 MediaAssetChangeRequest.createImageAssetRequest + applyChanges 创建相册资产
// - 保存完成或失败后清理沙箱临时文件

import { HdsNavDestination } from '@kit.UIDesignKit';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { RouterUtil, ImageViewerNavParams } from '../../utils/RouterUtil';
import { ImagePreview, PreviewDirection } from '@rv/image-preview';

// Swiper 切换动画时长（ms）
const SWIPER_ANIM_DURATION_MS: number = 200;

// #165 [A4-S5] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function ImageViewerPageBuilder() {
  ImageViewerPage()
}

@ComponentV2
export struct ImageViewerPage {
  @Local imageUrls: string[] = [];
  @Local currentIndex: number = 0;
  // 共享元素转场 ID（源端 Image 与目标端 Image 绑定同 id）
  @Local shareId: string = '';
  // 长按后显示保存按钮浮层
  @Local showSaveButton: boolean = false;
  @Local pendingSaveUrl: string = '';
  // 下载中状态
  @Local isDownloadingForSave: boolean = false;
  // 沙箱临时文件路径
  private sandboxFilePath: string = '';
  // 生命周期守护
  private isDestroyed: boolean = false;

  private showToast(message: string): void {
    this.getUIContext()?.getPromptAction().showToast({ message });
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    this.cleanupSandboxFile();
  }

  async aboutToAppear() {
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_IMAGE_VIEWER_PAGE) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as ImageViewerNavParams;
      if (params && params.urls && params.urls.length > 0) {
        this.imageUrls = params.urls;
        const rawIdx: number = params.index;
        const maxIdx: number = this.imageUrls.length - 1;
        this.currentIndex = Math.max(0, Math.min(rawIdx, maxIdx));
        this.shareId = params.shareId;
      }
    }
  }

  private closeViewer(): void {
    RouterUtil.backWithTransition(this.getUIContext());
  }

  async handleLongPress(url: string): Promise<void> {
    if (this.isDownloadingForSave || this.showSaveButton) {
      return;
    }
    this.pendingSaveUrl = url;
    this.isDownloadingForSave = true;
    try {
      const imageData = await this.downloadImage(url);
      if (this.isDestroyed) {
        return;
      }
      if (!imageData || imageData.byteLength === 0) {
        this.showToast(getResourceString($r('app.string.save_failed')));
        this.isDownloadingForSave = false;
        return;
      }
      const context = getContext(this) as common.UIAbilityContext;
      const ext: string = this.inferExtension(url);
      const fileName: string = `imgviewer_${Date.now()}.${ext}`;
      const filePath: string = `${context.filesDir}/${fileName}`;
      const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        await fs.write(file.fd, imageData);
      } finally {
        await fs.close(file);
      }
      this.sandboxFilePath = filePath;
      this.isDownloadingForSave = false;
      this.showSaveButton = true;
    } catch (err) {
      console.error(`[ImageViewer] download to sandbox failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.save_failed')));
      this.isDownloadingForSave = false;
    }
  }

  async onSaveButtonClick(result: SaveButtonOnClickResult): Promise<void> {
    if (result !== SaveButtonOnClickResult.SUCCESS) {
      this.showSaveButton = false;
      this.cleanupSandboxFile();
      return;
    }
    const url = this.pendingSaveUrl;
    this.showSaveButton = false;
    if (url.length === 0 || this.sandboxFilePath.length === 0) {
      this.cleanupSandboxFile();
      return;
    }
    try {
      this.showToast(getResourceString($r('app.string.saving_image')));
      await this.createImageAssetWithMediaChangeRequest();
      if (this.isDestroyed) {
        return;
      }
      VibratorUtil.light();
      this.showToast(getResourceString($r('app.string.save_success')));
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[ImageViewer] save failed: code=${error.code}, message=${error.message}`);
      if (!this.isDestroyed) {
        this.showToast(`${getResourceString($r('app.string.save_failed'))}: ${error.message}`);
      }
    } finally {
      this.cleanupSandboxFile();
    }
  }

  private async createImageAssetWithMediaChangeRequest(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const fileUriStr: string = fileUri.getUriFromPath(this.sandboxFilePath);
    const assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
      photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, fileUriStr);
    await helper.applyChanges(assetChangeRequest);
  }

  private async cleanupSandboxFile(): Promise<void> {
    if (this.sandboxFilePath.length === 0) {
      return;
    }
    const filePath: string = this.sandboxFilePath;
    this.sandboxFilePath = '';
    this.pendingSaveUrl = '';
    try {
      await fs.unlink(filePath);
    } catch (err) {
      console.warn(`[ImageViewer] cleanup sandbox file failed: ${(err as Error).message}`);
    }
  }

  private async downloadImage(url: string): Promise<ArrayBuffer> {
    const httpReq = http.createHttp();
    try {
      const response = await httpReq.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000
      });
      if (response.responseCode !== 200) {
        throw new Error(`下载失败，状态码: ${response.responseCode}`);
      }
      const result = response.result;
      if (!(result instanceof ArrayBuffer)) {
        throw new Error('下载失败：响应非二进制数据');
      }
      return result;
    } finally {
      httpReq.destroy();
    }
  }

  private inferExtension(url: string): string {
    const lower: string = url.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'png';
    } else if (lower.endsWith('.webp')) {
      return 'webp';
    } else if (lower.endsWith('.gif')) {
      return 'gif';
    } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'jpg';
    }
    return 'jpg';
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // Swiper 左右滑动切换多图，每页使用 ImagePreview 实现缩放/平移
        Swiper() {
          ForEach(this.imageUrls, (url: string, index: number) => {
            ImagePreview({
              config: {
                maxScale: 4.0,
                minScale: 1.0,
                doubleClickDefaultScale: 2.5,
                direction: PreviewDirection.Horizontal,
                onLongPress: () => {
                  VibratorUtil.heavy();
                  this.handleLongPress(url);
                }
              }
            }) {
              Image(url)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .draggable(false)
                .syncLoad(false)
                .interpolation(ImageInterpolation.High)
                .alt($r('app.media.startIcon'))
                .onError(() => {
                  // 大图加载失败静默处理
                })
                // 共享元素转场：只有当前页绑定 geometryTransition
                .geometryTransition(index === this.currentIndex ? this.shareId : '')
                .clip(true)
                .transition(TransitionEffect.opacity(0.99))
            }
          }, (url: string, index: number) => `${index}_${url}`)
        }
        .index(this.currentIndex)
        .indicator(false)
        .loop(false)
        .duration(SWIPER_ANIM_DURATION_MS)
        .onChange((newIndex: number) => {
          this.currentIndex = newIndex;
        })
        .width('100%')
        .height('100%')

        // 顶部关闭按钮
        Row() {
          Image($r('app.media.ic_back'))
            .width(28)
            .height(28)
            .fillColor(Color.White)
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            .onClick(() => {
              this.closeViewer();
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)

        // 保存浮层：底部居中卡片式设计
        if (this.isDownloadingForSave || this.showSaveButton) {
          Column() {
            if (this.isDownloadingForSave) {
              // 下载中状态
              LoadingProgress()
                .width(28)
                .height(28)
                .color(Color.White)
            } else {
              // 保存确认状态
              Text(getResourceString($r('app.string.save_image_confirm')))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .margin({ bottom: 16 })

              Row() {
                SaveButton({
                  text: SaveDescription.DOWNLOAD,
                  icon: SaveIconStyle.FULL_FILLED,
                  buttonType: ButtonType.Capsule
                })
                  .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                    this.onSaveButtonClick(result).catch((err: BusinessError) => {
                      console.error(`[ImageViewer] onSaveButtonClick failed: ${err.message}`);
                    });
                  })

                Text(getResourceString($r('app.string.cancel_button')))
                  .fontSize(15)
                  .fontColor('#FF453A')
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 24 })
                  .padding({ top: 8, bottom: 8, left: 12, right: 12 })
                  .onClick(() => {
                    this.showSaveButton = false;
                    this.cleanupSandboxFile();
                  })
              }
              .alignItems(VerticalAlign.Center)
            }
          }
          .padding(this.isDownloadingForSave ? 16 : 20)
          .borderRadius(16)
          .backgroundColor('rgba(28, 28, 30, 0.95)')
          .backdropBlur(10)
          .shadow({
            radius: 20,
            color: 'rgba(0, 0, 0, 0.3)',
            offsetX: 0,
            offsetY: 4
          })
          .position({ x: '50%', y: '82%' })
          .translate({ x: '-50%' })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Black)
    .onBackPressed(() => {
      this.closeViewer();
      return true;
    })
  }
}