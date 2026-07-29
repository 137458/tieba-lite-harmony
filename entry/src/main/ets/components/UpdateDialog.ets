// 更新公告弹窗组件
// 两种使用场景：
// 1. 启动时更新公告：应用更新后首次进入新版本时弹窗显示当前版本的 Release 公告
//    （数据源：GitHub Releases API，通过 tag_name 匹配当前版本获取 body）
// 2. 手动检查更新结果：设置页点"检查更新"后，有新版本时显示新版本公告
//
// 弹窗内容：标题（版本号）+ 更新公告正文（Markdown 渲染）+ 操作按钮
// 操作按钮：
//   - 启动公告场景：[以后再说]（关闭并标记已读） + [前往查看]（跳转浏览器 Release 页面）
//   - 检查更新场景：[以后再说] + [下载更新]（跳转浏览器 Release 页面）

import { promptAction } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getResourceString } from '../utils/ResourceUtil';
import { UpdateChecker, ReleaseInfo } from '../utils/UpdateChecker';
import { connectTheme, ThemeState } from '../theme/ThemeManager';
import { Markdown } from '@luvi/lv-markdown-in';

// 弹窗最大高度占比（占屏幕高度）
const DIALOG_MAX_HEIGHT_RATIO: string = '70%';

// 弹窗模式
export enum UpdateDialogMode {
  // 启动公告：应用更新后首次进入新版本，显示当前版本的 Release 公告
  STARTUP_NOTICE = 0,
  // 检查更新：手动检查后发现新版本，显示新版本 Release 公告
  CHECK_UPDATE = 1
}

@CustomDialog
struct UpdateDialog {
  controller: CustomDialogController;
  // 弹窗模式
  mode: UpdateDialogMode = UpdateDialogMode.STARTUP_NOTICE;
  // Release 信息（含 tag_name/body/html_url）
  releaseInfo: ReleaseInfo = new ReleaseInfo();
  // 当前应用版本号
  currentVersion: string = '';
  // 主题色
  themeState: ThemeState = connectTheme();
  // 关闭回调（标记已读等清理操作）
  onClose: () => void = () => {};

  /**
   * 用系统浏览器打开 Release 页面
   */
  private openReleasePage(): void {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: this.releaseInfo.html_url
      };
      context.startAbility(want).catch((err: BusinessError) => {
        console.error(`[UpdateDialog] startAbility failed: ${err.code} ${err.message}`);
        promptAction.showToast({ message: getResourceString($r('app.string.about_no_browser')) });
      });
    } catch (err) {
      console.error(`[UpdateDialog] openReleasePage failed: ${(err as Error).message}`);
      promptAction.showToast({ message: getResourceString($r('app.string.about_open_failed')) });
    }
  }

  build() {
    Column() {
      // 标题：更新公告
      Text(getResourceString($r('app.string.update_notice_title')))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      // 版本号行
      Row({ space: 8 }) {
        Text(getResourceString($r('app.string.update_current_version_label')) + ': ' + this.currentVersion)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        Text('→')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        Text(getResourceString($r('app.string.update_latest_version_label')) + ': ' + this.releaseInfo.tag_name)
          .fontSize(13)
          .fontColor(this.themeState.primary)
          .fontWeight(FontWeight.Medium)
      }
      .margin({ bottom: 12 })

      // 更新公告正文（Markdown 渲染，Scroll 包裹防止内容过长）
      // 使用 @luvi/lv-markdown-in 库渲染 GitHub Release 的 Markdown 格式 body
      // body 为空时显示"已是最新版本"提示
      Scroll() {
        Markdown({
          text: this.releaseInfo.body.length > 0 ? this.releaseInfo.body : getResourceString($r('app.string.update_already_latest')),
          mode: 'text',
          callback: {
            complete: () => {
              console.log('[UpdateDialog] Markdown render complete');
            },
            fail: (code: number, message: string) => {
              console.error(`[UpdateDialog] Markdown render failed: ${code} ${message}`);
            }
          }
        })
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Start)
      .scrollBar(BarState.Off)
      .margin({ bottom: 16 })

      // 操作按钮
      Row({ space: 12 }) {
        Button(getResourceString($r('app.string.update_later')))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.input_background'))
          .onClick(() => {
            this.onClose();
            this.controller.close();
          })

        Button(getResourceString($r('app.string.update_view_release')))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.card_background'))
          .backgroundColor(this.themeState.primary)
          .onClick(() => {
            this.openReleasePage();
            this.onClose();
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .width('85%')
    .height(DIALOG_MAX_HEIGHT_RATIO)
  }
}

export { UpdateDialog };

/**
 * 更新公告对话框参数（供 ComponentContent + openCustomDialog 使用）
 * UpdateNoticeManager 在非组件上下文中无法使用 CustomDialogController，
 * 改用 ComponentContent + promptAction.openCustomDialog 方式显示对话框
 */
export class UpdateContentParams {
  releaseInfo: ReleaseInfo = new ReleaseInfo();
  currentVersion: string = '';
  // 关闭对话框回调（由 UpdateNoticeManager 设置，用于标记已读等清理操作）
  onClose: () => void = () => {};
  // 跳转 Release 页面回调（由 UpdateNoticeManager 设置，用于打开浏览器）
  onOpenRelease: () => void = () => {};
}

/**
 * 更新公告 @Builder 函数（供 ComponentContent + wrapBuilder 使用）
 * 直接构建 UI，不依赖 @CustomDialog，可在非组件上下文中通过 ComponentContent 显示
 */
@Builder
export function UpdateContentBuilder(params: UpdateContentParams) {
  Column() {
    // 标题：更新公告
    Text(getResourceString($r('app.string.update_notice_title')))
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .margin({ bottom: 8 })

    // 版本号行
    Row({ space: 8 }) {
      Text(getResourceString($r('app.string.update_current_version_label')) + ': ' + params.currentVersion)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))

      Text('→')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))

      Text(getResourceString($r('app.string.update_latest_version_label')) + ': ' + params.releaseInfo.tag_name)
        .fontSize(13)
        .fontColor($r('app.color.primary'))
        .fontWeight(FontWeight.Medium)
    }
    .margin({ bottom: 12 })

    // 更新公告正文（Markdown 渲染，Scroll 包裹防止内容过长）
    Scroll() {
      Markdown({
        text: params.releaseInfo.body.length > 0 ? params.releaseInfo.body : getResourceString($r('app.string.update_already_latest')),
        mode: 'text',
        callback: {
          complete: () => {
            console.log('[UpdateDialog] Markdown render complete');
          },
          fail: (code: number, message: string) => {
            console.error(`[UpdateDialog] Markdown render failed: ${code} ${message}`);
          }
        }
      })
        .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Start)
    .scrollBar(BarState.Off)
    .margin({ bottom: 16 })

    // 操作按钮
    Row({ space: 12 }) {
      Button(getResourceString($r('app.string.update_later')))
        .layoutWeight(1)
        .height(40)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.input_background'))
        .onClick(() => {
          params.onClose();
        })

      Button(getResourceString($r('app.string.update_view_release')))
        .layoutWeight(1)
        .height(40)
        .fontSize(14)
        .fontColor($r('app.color.card_background'))
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          params.onOpenRelease();
        })
    }
    .width('100%')
  }
  .padding(20)
  .backgroundColor($r('app.color.card_background'))
  .borderRadius(16)
  .width('85%')
  .height('70%')
}
