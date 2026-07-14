// 图片查看器页面（issue #15）
// 全屏查看 + 双指缩放 + 左右滑动切换 + 双击缩放 + 长按保存到相册
// 调用方：router.pushUrl({ url: 'pages/viewer/ImageViewerPage', params: { urls: string[], index: number } })
//
// #90 保存到相册新流程（迁移到 MediaAssetChangeRequest API 11+）：
// - 长按图片 → 异步下载到应用沙箱临时文件（filesDir/imgviewer_<ts>.<ext>）
// - 下载完成后显示 SaveButton 浮层（用户点击授予 5 秒临时授权）
// - 授权后调用 MediaAssetChangeRequest.createImageAssetRequest + applyChanges 创建相册资产
// - 保存完成或失败后清理沙箱临时文件
// - 新 API 要求 fileUri 必须是应用沙箱下的 uri（非网络 URL），因此下载必须在 SaveButton 点击前完成
// - 这避免了 #85 旧方案"先 createAsset 占授权窗口 → 再 downloadImage"的竞态（旧 API createAsset 可创建空资产，新 API 不支持）

import { curves } from '@kit.ArkUI';
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

// 长按手势识别时长（ms），超过此时长触发保存菜单
const LONG_PRESS_DURATION_MS: number = 500;
// Swiper 切换动画时长（ms）
const SWIPER_ANIM_DURATION_MS: number = 200;
// #132 转场动画时长（ms），转场期间显示缩略图，转场结束后切换大图
// 略大于 springMotion 实际时长（~350ms），确保转场完成后再切换
const TRANSITION_DELAY_MS: number = 400;

/**
 * 单个可缩放图片项
 * #132 新增 thumbnailUrl/shareId 可选参数支持共享元素转场：
 * - thumbnailUrl 非空时，转场期间显示缩略图，TRANSITION_DELAY_MS 后切换为 url 大图
 * - shareId 非空时，Image 绑定 .geometryTransition(shareId) 实现共享元素转场
 * - 两个参数都为空时（原 ImageViewerPage 调用），行为不变
 */
@ComponentV2
export struct ImageViewerItem {
  @Param url: string = '';
  // #132 转场期间显示的缩略图 URL（可选，为空时直接显示 url）
  @Param thumbnailUrl: string = '';
  // #132 共享元素转场 ID（可选，为空时不绑定 geometryTransition）
  @Param shareId: string = '';
  // 缩放状态（每个 item 独立）。字段名用 scaleValue 避免与 CustomComponent 内置 scale 属性冲突
  @Local scaleValue: number = 1.0;
  // #132 转场是否完成（false=显示缩略图，true=显示大图）
  // thumbnailUrl 为空时直接为 true（无转场，原 ImageViewerPage 行为）
  @Local isTransitionDone: boolean = false;
  private startScale: number = 1.0;
  // 长按保存回调
  @Event onLongPress: (url: string) => void = () => {};

  aboutToAppear(): void {
    // #132 thumbnailUrl 为空时直接显示大图（原 ImageViewerPage 行为）
    if (this.thumbnailUrl.length === 0) {
      this.isTransitionDone = true;
      return;
    }
    // #132 转场期间显示缩略图，延迟切换为大图
    setTimeout(() => {
      this.isTransitionDone = true;
    }, TRANSITION_DELAY_MS);
  }

  build() {
    Stack() {
      // #132 转场期间显示缩略图，转场结束后显示大图
      // thumbnailUrl 为空时直接显示 url（isTransitionDone 初始为 true）
      Image(this.thumbnailUrl.length > 0 && !this.isTransitionDone ? this.thumbnailUrl : this.url)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        // #93 禁用系统拖拽默认行为：Image 默认 draggable(true) 会触发拖拽浮起，
        // 被小艺/中转站拦截导致长按保存菜单不出现。设为 false 让 LongPressGesture 正常触发。
        .draggable(false)
        // A5 图片优化：大图查看器异步加载避免阻塞 UI + 高质量插值缓解缩放锯齿 + 错误兜底
        .syncLoad(false)
        .interpolation(ImageInterpolation.High)
        .onError(() => {
          // 大图加载失败静默处理（查看器场景由调用方决定是否提示）
        })
        .scale({ x: this.scaleValue, y: this.scaleValue })
        // #97 P2 #1 双击/双指回弹缩放使用 @Local 驱动动画（对齐华为官方动画规范）：
        // scaleValue 变化时自动过渡，避免瞬时跳变。springMotion() 提供自然回弹手感
        .animation({ duration: 300, curve: curves.springMotion() })
        // #132 shareId 非空时绑定共享元素转场（空字符串不触发转场效果）
        .geometryTransition(this.shareId)
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            // 双指捏合缩放
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.startScale = this.scaleValue;
              })
              .onActionUpdate((event: GestureEvent) => {
                // event.scale 是当前捏合比例（相对于开始），限制 1.0~4.0
                this.scaleValue = Math.max(1.0, Math.min(4.0, this.startScale * event.scale));
              })
              .onActionEnd(() => {
                // 缩放小于 1.1 时回弹到 1.0
                if (this.scaleValue < 1.1) {
                  this.scaleValue = 1.0;
                }
              }),
            // 双击切换缩放（TapGesture count=2 实现双击）
            TapGesture({ count: 2, fingers: 1 })
              .onAction(() => {
                this.scaleValue = this.scaleValue > 1.0 ? 1.0 : 2.5;
              }),
            // 长按弹出保存菜单
            LongPressGesture({ repeat: false, duration: LONG_PRESS_DURATION_MS })
              .onAction(() => {
                // #121 触感反馈：长按保存图片属于强调交互，触发重震动
                VibratorUtil.heavy();
                this.onLongPress(this.url);
              })
          )
        )
    }
    .width('100%')
    .height('100%')
    // #97 P2 #2 ImageViewerItem 含 Image + GestureGroup + scale 动画的复杂子组件，
    // 启用 renderGroup 减少渲染批次，提升动画流畅度
    .renderGroup(true)
  }
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
  // 长按后显示保存按钮浮层（SaveButton 必须在用户可见区域，不能放对话框里）
  @Local showSaveButton: boolean = false;
  @Local pendingSaveUrl: string = '';
  // #90 下载中状态：长按后先下载到沙箱，下载完成后才显示 SaveButton
  @Local isDownloadingForSave: boolean = false;
  // 沙箱临时文件路径（下载完成后保存，applyChanges 后清理）
  private sandboxFilePath: string = '';
  // #97 P1 生命周期守护：异步任务（downloadImage / createImageAssetWithMediaChangeRequest）
  // 在 await 返回后可能写入已销毁组件的 @State，触发 "state lock on destroyed component" 告警，
  // 同时 getUIContext() 在销毁后调用会抛异常。对齐 ThreadPage isDestroyed 模式
  private isDestroyed: boolean = false;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  // #90 aboutToDisappear：清理沙箱临时文件，避免泄漏
  // #97 P1 同时置 isDestroyed=true，阻止后续 await 写入 @State
  aboutToDisappear(): void {
    this.isDestroyed = true;
    this.cleanupSandboxFile();
  }

  async aboutToAppear() {
    // #165 路由迁移：router.getParams() → NavPathStack.getParamByName()
    // SDK 返回 Array<unknown>，ArkTS 不支持 unknown，用 as Object[] 断言
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_IMAGE_VIEWER_PAGE) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as ImageViewerNavParams;
      if (params && params.urls && params.urls.length > 0) {
        this.imageUrls = params.urls;
        // #90 越界保护：Math.max(0, Math.min(rawIdx, len-1))，避免 index 超出 urls 长度导致 Swiper 空白
        const rawIdx: number = params.index;
        const maxIdx: number = this.imageUrls.length - 1;
        this.currentIndex = Math.max(0, Math.min(rawIdx, maxIdx));
      }
    }
  }

  // #90 长按回调：异步下载图片到沙箱临时文件，下载完成后显示 SaveButton 浮层
  // 新流程：先下载到沙箱（任意时长）→ 再显示 SaveButton → 用户点击后 applyChanges（5 秒授权窗口内）
  // 这避免了旧方案"先 createAsset 占授权窗口 → 再 downloadImage"的竞态（新 API 不支持创建空资产）
  async handleLongPress(url: string): Promise<void> {
    if (this.isDownloadingForSave) {
      return; // 已在下载中，忽略重复长按
    }
    if (this.showSaveButton) {
      return; // SaveButton 已显示，忽略重复长按
    }
    this.pendingSaveUrl = url;
    this.isDownloadingForSave = true;
    try {
      const imageData = await this.downloadImage(url);
      // #97 P1 #1 用户可能在 await 期间关闭页面，aboutToDisappear 已置 isDestroyed=true 并清理沙箱。
      // 此时直接 return，避免写入已销毁组件的 @State；imageData 内存由 GC 回收，无沙箱文件泄漏
      if (this.isDestroyed) {
        return;
      }
      if (!imageData || imageData.byteLength === 0) {
        this.showToast(getResourceString($r('app.string.save_failed')));
        this.isDownloadingForSave = false;
        return;
      }
      // 写入沙箱临时文件
      // #193 P2 同步文件 API 改异步：openSync 改为 await fs.open，避免主线程阻塞 UI
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
      this.showSaveButton = true; // 下载完成，显示 SaveButton
    } catch (err) {
      console.error(`[ImageViewer] download to sandbox failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.save_failed')));
      this.isDownloadingForSave = false;
    }
  }

  // #90 SaveButton 点击回调：授权成功后调用 MediaAssetChangeRequest.createImageAssetRequest + applyChanges
  // 沙箱文件已在 handleLongPress 中就绪，此处只需在 5 秒授权窗口内完成 applyChanges
  async onSaveButtonClick(result: SaveButtonOnClickResult): Promise<void> {
    if (result !== SaveButtonOnClickResult.SUCCESS) {
      // 用户未授权或授权失败
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
      // createImageAssetRequest + applyChanges（沙箱文件已就绪，5 秒授权窗口内完成）
      await this.createImageAssetWithMediaChangeRequest();
      // #97 P1 #2 用户可能在 await 期间关闭页面，aboutToDisappear 已置 isDestroyed=true。
      // 此时不再调用 showToast（getUIContext 在销毁后调用会异常），直接走 finally 清理沙箱
      if (this.isDestroyed) {
        return;
      }
      // #121 触感反馈：图片保存成功触发轻震动
      VibratorUtil.light();
      this.showToast(getResourceString($r('app.string.save_success')));
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[ImageViewer] save failed: code=${error.code}, message=${error.message}`);
      // catch 分支同样受 isDestroyed 守卫保护，避免销毁后调用 getUIContext
      if (!this.isDestroyed) {
        this.showToast(`${getResourceString($r('app.string.save_failed'))}: ${error.message}`);
      }
    } finally {
      // 无论成功失败都清理沙箱临时文件
      this.cleanupSandboxFile();
    }
  }

  // #90 新 API：createImageAssetRequest + applyChanges（迁移自旧 API helper.createAsset）
  // createImageAssetRequest 要求 fileUri 必须是应用沙箱下的 uri（file://bundleName/path）
  private async createImageAssetWithMediaChangeRequest(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const fileUriStr: string = fileUri.getUriFromPath(this.sandboxFilePath);
    const assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
      photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, fileUriStr);
    await helper.applyChanges(assetChangeRequest);
  }

  // #90 清理沙箱临时文件（applyChanges 后或失败时调用，aboutToDisappear 时也调用）
  // #193 P2 同步文件 API 改异步：accessSync/unlinkSync 改为 await fs.access/fs.unlink
  // 注意：aboutToDisappear 不能 await，调用方采用 fire-and-forget；方法开始立即清空 sandboxFilePath
  // 防止并发调用（aboutToDisappear 与 onSaveButtonClick finally 可能先后触发）重复删除同一文件
  private async cleanupSandboxFile(): Promise<void> {
    if (this.sandboxFilePath.length === 0) {
      return;
    }
    const filePath: string = this.sandboxFilePath;
    this.sandboxFilePath = '';
    this.pendingSaveUrl = '';
    try {
      // P2 #8：直接 unlink + catch，省去 fs.access 预检查
      // 文件不存在时 unlink 抛错进 catch，行为与原 fs.access + unlink 一致但少一次 IO
      await fs.unlink(filePath);
    } catch (err) {
      console.warn(`[ImageViewer] cleanup sandbox file failed: ${(err as Error).message}`);
    }
  }

  // 下载图片为 ArrayBuffer
  // 校验响应状态码和 result 类型，避免 404/500 时写入错误数据
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

  // 从 URL 推断图片扩展名（支持 jpg/jpeg/png/webp/gif），默认 jpg
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
    // #165 [A4-S5] HdsNavDestination 包装：替代 @Entry + router，纳入 HdsNavigation 路由栈
    // 图片查看器是全屏黑底 Swiper，用 hideTitleBar(true)，保留浮动关闭按钮
    HdsNavDestination() {
      Stack() {
        // Swiper 左右滑动切换多图
        Swiper() {
          ForEach(this.imageUrls, (url: string, index: number) => {
            ImageViewerItem({
              url: url,
              onLongPress: (clickedUrl: string) => this.handleLongPress(clickedUrl)
            })
          }, (url: string, index: number) => `${index}_${url}`)
        }
        .index(this.currentIndex)
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
            // A5 图片优化：本地 SVG 小图同步加载避免闪烁
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            .onClick(() => {
              RouterUtil.back();
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)

        // #90 长按后显示的浮层（底部居中）
        // - isDownloadingForSave=true：显示 loading"正在下载..."
        // - showSaveButton=true：显示 SaveButton + 取消按钮
        // SaveButton 是安全控件，点击后授予 5 秒临时写相册权限，无需声明 WRITE_IMAGEVIDEO
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
                  console.error(`[ImageViewer] onSaveButtonClick failed: ${err.message}`);
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
      // #85 P1 #7 沉浸式安全区域：Stack 延伸到状态栏和导航条区域
      // 黑底背景下系统会自动适配状态栏图标为白色（浅色主题下默认深色图标在黑底不可见）
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Black)
  }
}
