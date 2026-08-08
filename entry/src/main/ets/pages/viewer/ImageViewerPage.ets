// 图片查看器页面
// 基于 @rv/image-preview 三方库实现缩放/平移/双击等手势交互
// 调用方：RouterUtil.pushImageViewer(urls, index)
//
// 保存到相册流程：
// - 长按图片 → 异步下载到应用沙箱临时文件（filesDir/imgviewer_<ts>.<ext>）
// - 下载完成后弹出系统 AlertDialog 确认保存
// - 用户确认后通过 MediaAssetChangeRequest 创建相册资产
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

// AlertDialog 返回结果类型
interface SaveDialogResult {
  index: number;
}

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
  // 沙箱临时文件路径
  private sandboxFilePath: string = '';
  // 生命周期守护
  private isDestroyed: boolean = false;
  // 防止重复触发保存流程
  private isSaving: boolean = false;

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

  /**
   * 长按保存图片：下载到沙箱 → 弹出系统 AlertDialog 确认 → 保存到相册
   * 对齐 HomePage.deleteRecentForum 的 AlertDialog 交互模式
   */
  async handleLongPress(url: string): Promise<void> {
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    try {
      const imageData = await this.downloadImage(url);
      if (this.isDestroyed) {
        return;
      }
      if (!imageData || imageData.byteLength === 0) {
        this.showToast(getResourceString($r('app.string.save_image_failed')));
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

      if (this.isDestroyed) {
        return;
      }

      // 弹出系统 AlertDialog 确认保存（对齐 HomePage 删除确认弹窗风格）
      this.getUIContext().getPromptAction().showDialog({
        title: getResourceString($r('app.string.save_image_title')),
        message: getResourceString($r('app.string.save_image_confirm')),
        buttons: [
          { text: getResourceString($r('app.string.cancel_button')), color: $r('app.color.text_secondary') },
          { text: getResourceString($r('app.string.save_button')), color: $r('app.color.primary') }
        ]
      }).then((result: SaveDialogResult) => {
        if (result.index === 1) {
          this.doSaveImage();
        } else {
          this.cleanupSandboxFile();
        }
      }).catch((err: Error) => {
        console.error(`[ImageViewer] save dialog failed: ${err.message}`);
        this.cleanupSandboxFile();
      });
    } catch (err) {
      console.error(`[ImageViewer] download to sandbox failed: ${(err as Error).message}`);
      if (!this.isDestroyed) {
        this.showToast(getResourceString($r('app.string.save_image_failed')));
      }
    } finally {
      this.isSaving = false;
    }
  }

  /**
   * 执行保存到相册
   * 使用 MediaAssetChangeRequest 创建相册资产（对齐系统相册保存规范）
   */
  private async doSaveImage(): Promise<void> {
    if (this.sandboxFilePath.length === 0) {
      return;
    }
    try {
      this.showToast(getResourceString($r('app.string.saving_image')));
      await this.createImageAssetWithMediaChangeRequest();
      if (this.isDestroyed) {
        return;
      }
      VibratorUtil.light();
      this.showToast(getResourceString($r('app.string.save_image_success')));
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[ImageViewer] save failed: code=${error.code}, message=${error.message}`);
      if (!this.isDestroyed) {
        this.showToast(`${getResourceString($r('app.string.save_image_failed'))}: ${error.message}`);
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