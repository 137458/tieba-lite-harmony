// 图片查看器页面（issue #15）
// 全屏查看 + 双指缩放 + 左右滑动切换 + 双击缩放 + 长按保存到相册
// 调用方：router.pushUrl({ url: 'pages/viewer/ImageViewerPage', params: { urls: string[], index: number } })
//
// 保存到相册使用安全控件 SaveButton（免权限申请）：
// - 用户点击 SaveButton 后获得 5 秒临时授权
// - 期间调用 photoAccessHelper.createAsset 创建相册资源并写入
// - 无需在 module.json5 声明 WRITE_IMAGEVIDEO，自签名证书也可安装

import { router, promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getResourceString } from '../../utils/ResourceUtil';

/** router 传入的参数结构 */
interface ImageViewerParams {
  urls: string[];
  index: number;
}

/** 单个可缩放图片项 */
@Component
struct ImageViewerItem {
  @Prop url: string = '';
  // 缩放状态（每个 item 独立）。字段名用 scaleValue 避免与 CustomComponent 内置 scale 属性冲突
  @State scaleValue: number = 1.0;
  private startScale: number = 1.0;
  // 长按保存回调
  onLongPress: (url: string) => void = () => {};

  build() {
    Stack() {
      Image(this.url)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .scale({ x: this.scaleValue, y: this.scaleValue })
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
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => {
                this.onLongPress(this.url);
              })
          )
        )
    }
    .width('100%')
    .height('100%')
  }
}

@Entry
@Component
struct ImageViewerPage {
  @State imageUrls: string[] = [];
  @State currentIndex: number = 0;
  // 长按后显示保存按钮浮层（SaveButton 必须在用户可见区域，不能放对话框里）
  @State showSaveButton: boolean = false;
  @State pendingSaveUrl: string = '';

  aboutToAppear() {
    // 解析 router 参数
    const params = router.getParams() as ImageViewerParams;
    if (params && params.urls) {
      this.imageUrls = params.urls;
      // 显式检查 undefined，避免 index=0 被 || 替换（对齐 searchExact 0 值处理规范）
      this.currentIndex = params.index !== undefined ? params.index : 0;
    }
  }

  // 长按回调：显示 SaveButton 浮层（不弹对话框，SaveButton 需在可见区域）
  handleLongPress(url: string): void {
    this.pendingSaveUrl = url;
    this.showSaveButton = true;
  }

  // SaveButton 点击回调：授权成功后下载图片并保存到相册
  // SaveButton 点击后获得 5 秒临时授权，期间 createAsset 可用
  async onSaveButtonClick(result: SaveButtonOnClickResult): Promise<void> {
    if (result !== SaveButtonOnClickResult.SUCCESS) {
      // 用户未授权或授权失败
      this.showSaveButton = false;
      return;
    }
    const url = this.pendingSaveUrl;
    this.showSaveButton = false;
    if (url.length === 0) {
      return;
    }
    try {
      promptAction.showToast({ message: getResourceString($r('app.string.saving_image')) });
      // Step 1: 下载图片为 ArrayBuffer
      const imageData = await this.downloadImage(url);
      if (!imageData || imageData.byteLength === 0) {
        promptAction.showToast({ message: getResourceString($r('app.string.save_failed')) });
        return;
      }
      // Step 2: createAsset 创建相册资源并写入（5 秒临时授权窗口内）
      await this.saveToGallery(imageData, url);
      promptAction.showToast({ message: getResourceString($r('app.string.save_success')) });
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[ImageViewer] save failed: ${error.message}`);
      promptAction.showToast({ message: getResourceString($r('app.string.save_failed')) });
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

  // 创建相册资源并写入图片数据（SaveButton 临时授权窗口内调用）
  private async saveToGallery(imageData: ArrayBuffer, url: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const helper = photoAccessHelper.getPhotoAccessHelper(context);

    // 从 URL 推断图片扩展名，默认 jpg（贴吧图片多为 jpg）
    const ext: string = this.inferExtension(url);
    const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext);

    // 打开文件并写入数据（fs 默认导出自 @ohos.file.fs，用异步 API 避免阻塞 UI）
    const file = await fs.open(uri, fs.OpenMode.READ_WRITE);
    try {
      await fs.write(file.fd, imageData);
    } finally {
      await fs.close(file);
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
      .duration(200)
      .width('100%')
      .height('100%')

      // 顶部关闭按钮（左上角，返回箭头）
      Row() {
        Image($r('app.media.ic_back'))
          .width(28)
          .height(28)
          .fillColor(Color.White)
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)

      // 长按后显示的保存按钮浮层（底部居中）
      // SaveButton 是安全控件，点击后授予 5 秒临时写相册权限，无需声明 WRITE_IMAGEVIDEO
      if (this.showSaveButton) {
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
  }
}
