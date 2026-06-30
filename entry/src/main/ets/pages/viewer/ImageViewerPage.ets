// 图片查看器页面（issue #15）
// 全屏查看 + 双指缩放 + 左右滑动切换 + 双击缩放 + 长按保存到相册
// 调用方：router.pushUrl({ url: 'pages/viewer/ImageViewerPage', params: { urls: string[], index: number } })

import { router, promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.PhotoAccessHelper';
import { fileIo } from '@kit.CoreFileIo';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
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
  // 缩放状态（每个 item 独立）
  @State scale: number = 1.0;
  private startScale: number = 1.0;
  // 长按保存回调
  onLongPress: (url: string) => void = () => {};

  build() {
    Stack() {
      Image(this.url)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .scale({ x: this.scale, y: this.scale })
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            // 双指捏合缩放
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.startScale = this.scale;
              })
              .onAction((event: GestureEvent) => {
                // event.scale 是当前捏合比例（相对于开始），限制 1.0~4.0
                this.scale = Math.max(1.0, Math.min(4.0, this.startScale * event.scale));
              })
              .onActionEnd(() => {
                // 缩放小于 1.1 时回弹到 1.0
                if (this.scale < 1.1) {
                  this.scale = 1.0;
                }
              }),
            // 双击切换缩放
            DoubleTapGesture({ count: 1, fingers: 1, interval: 300 })
              .onAction(() => {
                this.scale = this.scale > 1.0 ? 1.0 : 2.5;
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

  aboutToAppear() {
    // 解析 router 参数
    const params = router.getParams() as ImageViewerParams;
    if (params && params.urls) {
      this.imageUrls = params.urls;
      // 显式检查 undefined，避免 index=0 被 || 替换（对齐 searchExact 0 值处理规范）
      this.currentIndex = params.index !== undefined ? params.index : 0;
    }
  }

  // 长按保存回调：弹出确认对话框
  handleLongPress(url: string): void {
    promptAction.showDialog({
      title: getResourceString($r('app.string.save_image_title')),
      message: getResourceString($r('app.string.save_image_confirm')),
      buttons: [
        { text: getResourceString($r('app.string.save_button')), color: '#4A90D9' },
        { text: getResourceString($r('app.string.cancel_button')), color: '#999999' }
      ]
    }).then((result) => {
      if (result.index === 0) {
        this.saveImageToGallery(url);
      }
    }).catch((err: BusinessError) => {
      // showDialog reject（如系统异常）兜底，避免 unhandled rejection
      console.error(`[ImageViewer] showDialog failed: ${err.message}`);
    });
  }

  // 保存图片到相册
  // 流程：申请权限 → 下载图片 → 创建相册资源 → 写入数据
  async saveImageToGallery(url: string): Promise<void> {
    try {
      // Step 1: 申请 WRITE_IMAGEMEDIA 权限
      const granted = await this.requestSavePermission();
      if (!granted) {
        promptAction.showToast({ message: getResourceString($r('app.string.permission_denied')) });
        return;
      }

      // Step 2: 下载图片为 ArrayBuffer
      promptAction.showToast({ message: getResourceString($r('app.string.saving_image')) });
      const imageData = await this.downloadImage(url);
      if (!imageData || imageData.byteLength === 0) {
        promptAction.showToast({ message: getResourceString($r('app.string.save_failed')) });
        return;
      }

      // Step 3: 保存到相册（传入 url 用于推断扩展名）
      await this.saveToGallery(imageData, url);
      promptAction.showToast({ message: getResourceString($r('app.string.save_success')) });
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[ImageViewer] save failed: ${error.message}`);
      promptAction.showToast({ message: getResourceString($r('app.string.save_failed')) });
    }
  }

  // 申请相册写入权限
  private async requestSavePermission(): Promise<boolean> {
    const context = getContext(this) as common.UIAbilityContext;
    const atm = abilityAccessCtrl.createAtManager();
    const tokenId = context.applicationInfo.accessTokenId;
    const permission: Permissions = 'ohos.permission.WRITE_IMAGEMEDIA';
    const status = await atm.checkAccessToken(tokenId, permission);
    if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true;
    }
    const result = await atm.requestPermissionsFromUser(context, [permission]);
    return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
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

  // 创建相册资源并写入图片数据
  private async saveToGallery(imageData: ArrayBuffer, url: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const helper = photoAccessHelper.getPhotoAccessHelper(context);

    // 从 URL 推断图片扩展名，默认 jpg（贴吧图片多为 jpg）
    const ext: string = this.inferExtension(url);
    const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext);

    // 打开文件并写入数据
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE);
    try {
      fileIo.writeSync(file.fd, imageData);
    } finally {
      fileIo.closeSync(file);
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
