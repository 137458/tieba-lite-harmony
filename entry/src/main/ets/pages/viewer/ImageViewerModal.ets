// #132 图片查看器模态（bindContentCover + geometryTransition 共享元素转场）
// 替代原 ImageViewerPage 的 RouterUtil.push 跳转方式，改用全局模态弹出
// 由 Index.ets 的 bindContentCover 触发，监听 ImageViewerState.isVisible
//
// 与 ImageViewerPage 的区别：
// - ImageViewerPage 是 NavDestination，通过 RouterUtil.push 跳转（保留作为 fallback）
// - ImageViewerModal 是 bindContentCover 模态，通过全局状态触发（#132 主入口）
// - ImageViewerModal 支持共享元素转场（geometryTransition）
// - ImageViewerModal 转场期间显示缩略图，转场结束后加载大图
//
// 复用 ImageViewerItem（export struct），避免图片展示和手势逻辑重复

import { curves } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { ImageViewerItem } from './ImageViewerPage';
import { connectImageViewer, ImageViewerState } from '../../model/AppStorageV2Models';

// 长按手势识别时长（ms），超过此时长触发保存菜单
const LONG_PRESS_DURATION_MS: number = 500;
// Swiper 切换动画时长（ms）
const SWIPER_ANIM_DURATION_MS: number = 200;

/**
 * #132 图片查看器模态组件
 *
 * 作为 Index.ets bindContentCover 的 builder 内容，由全局 ImageViewerState 驱动显示/隐藏
 * 支持：
 *   - 共享元素转场（geometryTransition）：列表端 Image 与当前页 Image 绑定同 shareId
 *   - 转场期间显示缩略图，转场结束后加载大图（避免缩略图→大图闪烁）
 *   - Swiper 左右滑动切换多图
 *   - 双指/双击缩放（ImageViewerItem 内部实现）
 *   - 长按保存到相册（复用 ImageViewerPage 的保存逻辑）
 *   - springMotion 弹性回弹关闭动画
 */
@ComponentV2
export struct ImageViewerModal {
  // 全局图片查看器状态（与 Index.ets bindContentCover 共享）
  @Local imageViewerState: ImageViewerState = connectImageViewer();
  // 长按后显示保存按钮浮层
  @Local showSaveButton: boolean = false;
  @Local pendingSaveUrl: string = '';
  // 下载中状态：长按后先下载到沙箱，下载完成后才显示 SaveButton
  @Local isDownloadingForSave: boolean = false;
  // 沙箱临时文件路径
  private sandboxFilePath: string = '';
  // 生命周期守护：异步任务在 await 返回后可能写入已销毁组件的 @State
  private isDestroyed: boolean = false;

  // Toast 提示 helper
  // getUIContext 加可选链防御组件销毁后调用返回 undefined（与 close() 方法一致）
  private showToast(message: string): void {
    this.getUIContext()?.getPromptAction().showToast({ message });
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    this.cleanupSandboxFile();
  }

  /** 关闭模态：springMotion 弹性回弹动画 */
  private close(): void {
    this.getUIContext()?.animateTo({
      duration: 350,
      curve: curves.springMotion()
    }, () => {
      this.imageViewerState.isVisible = false;
    });
  }

  // ========== 长按保存逻辑（复用自 ImageViewerPage） ==========

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
      console.error(`[ImageViewerModal] download to sandbox failed: ${(err as Error).message}`);
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
      console.error(`[ImageViewerModal] save failed: code=${error.code}, message=${error.message}`);
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
      console.warn(`[ImageViewerModal] cleanup sandbox file failed: ${(err as Error).message}`);
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
    Stack() {
      // Swiper 左右滑动切换多图
      Swiper() {
        ForEach(this.imageViewerState.urls, (url: string, index: number) => {
          ImageViewerItem({
            url: url,
            // #132 只有当前页传 shareId，其他页传空字符串
            // 当前页的 Image 绑定 geometryTransition(shareId) 实现共享元素转场
            shareId: index === this.imageViewerState.index ? this.imageViewerState.shareId : '',
            onLongPress: (clickedUrl: string) => this.handleLongPress(clickedUrl)
          })
        }, (url: string, index: number) => `${index}_${url}`)
      }
      .index(this.imageViewerState.index)
      .indicator(false)
      .loop(false)
      .duration(SWIPER_ANIM_DURATION_MS)
      .width('100%')
      .height('100%')

      // 顶部关闭按钮（左上角，返回箭头）
      Row() {
        Image($r('app.media.ic_back'))
          .width(28)
          .height(28)
          .fillColor(Color.White)
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
          .onClick(() => {
            this.close();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)

      // 长按后显示的浮层（底部居中）
      if (this.isDownloadingForSave) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(Color.White)
            .margin({ bottom: 8 })
          Text(getResourceString($r('app.string.saving_image')))
            .fontSize(14)
            .fontColor(Color.White)
        }
        .padding(20)
        .borderRadius(12)
        .backgroundColor('rgba(0, 0, 0, 0.7)')
        .position({ x: '50%', y: '80%' })
        .translate({ x: '-50%' })
      } else if (this.showSaveButton) {
        Column() {
          Text(getResourceString($r('app.string.save_image_confirm')))
            .fontSize(14)
            .fontColor(Color.White)
            .margin({ bottom: 8 })

          SaveButton({
            text: SaveDescription.DOWNLOAD,
            icon: SaveIconStyle.FULL_FILLED,
            buttonType: ButtonType.Capsule
          })
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              this.onSaveButtonClick(result).catch((err: BusinessError) => {
                console.error(`[ImageViewerModal] onSaveButtonClick failed: ${err.message}`);
              });
            })

          Text(getResourceString($r('app.string.cancel_button')))
            .fontSize(13)
            .fontColor(Color.White)
            .opacity(0.8)
            .margin({ top: 8 })
            .onClick(() => {
              this.showSaveButton = false;
              this.cleanupSandboxFile();
            })
        }
        .padding(16)
        .borderRadius(12)
        .backgroundColor('rgba(0, 0, 0, 0.7)')
        .position({ x: '50%', y: '80%' })
        .translate({ x: '-50%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // #132 模态根容器转场效果（参考 template7 官方示例）
    // asymmetric: 出现时 opacity(0.99)（配合 geometryTransition），消失时 OPACITY
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.opacity(0.99),
      TransitionEffect.OPACITY
    ))
  }
}
