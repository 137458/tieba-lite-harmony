// 更新弹窗组件（通过 ComponentContent + openCustomDialog 在非组件上下文中显示）
// 两种模式：
// 1. STARTUP_NOTICE（更新公告）：应用更新后首次进入新版本时显示当前版本 Release 公告
//    - 标题"更新公告"，无版本对比行，按钮"我已知晓" + "前往查看"
// 2. CHECK_UPDATE（检测到新版本）：手动检查更新后发现新版本时显示
//    - 标题"发现新版本"，显示当前版本→最新版本对比，按钮"以后再说" + "下载更新"

import { getResourceString } from '../utils/ResourceUtil';
import { ReleaseInfo } from '../utils/UpdateChecker';
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';

// 弹窗模式
export enum UpdateDialogMode {
  // 启动公告：应用更新后首次进入新版本，显示当前版本的 Release 公告
  STARTUP_NOTICE = 0,
  // 检查更新：手动检查后发现新版本，显示新版本 Release 公告
  CHECK_UPDATE = 1
}

/**
 * 更新公告对话框参数（供 ComponentContent + openCustomDialog 使用）
 * UpdateNoticeManager 在非组件上下文中无法使用 CustomDialogController，
 * 改用 ComponentContent + promptAction.openCustomDialog 方式显示对话框
 */
export class UpdateContentParams {
  releaseInfo: ReleaseInfo = new ReleaseInfo();
  currentVersion: string = '';
  // 弹窗模式：STARTUP_NOTICE=更新公告（无版本对比，按钮"我已知晓"） CHECK_UPDATE=检测到新版本（有版本对比，按钮"以后再说"+"下载更新"）
  mode: UpdateDialogMode = UpdateDialogMode.STARTUP_NOTICE;
  // 关闭对话框回调（由 UpdateNoticeManager 设置，用于标记已读等清理操作）
  onClose: () => void = () => {};
  // 跳转 Release 页面回调（由 UpdateNoticeManager 设置，用于打开浏览器）
  onOpenRelease: () => void = () => {};
  markdownController: MarkdownController = new MarkdownController();

  configureMarkdownStyle(): void {
    this.markdownController
      .setTitleColor($r('app.color.text_primary'))
      .setTextColor($r('app.color.text_primary'))
      .setQuoteTextColor($r('app.color.text_secondary'))
      .setHyperlinkTextColor($r('app.color.primary'));
  }
}

/**
 * 更新公告 @Builder 函数（供 ComponentContent + wrapBuilder 使用）
 * 直接构建 UI，不依赖 @CustomDialog，可在非组件上下文中通过 ComponentContent 显示
 */
@Builder
export function UpdateContentBuilder(params: UpdateContentParams) {
  Column() {
    // 标题：更新公告（STARTUP_NOTICE）或 发现新版本（CHECK_UPDATE）
    Text(getResourceString(params.mode === UpdateDialogMode.CHECK_UPDATE
      ? $r('app.string.update_new_version_available')
      : $r('app.string.update_notice_title')))
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .margin({ bottom: 8 })

    // 版本号行：仅 CHECK_UPDATE 模式显示
    if (params.mode === UpdateDialogMode.CHECK_UPDATE) {
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
    }

    // 更新公告正文（Markdown 渲染，Scroll 包裹防止内容过长）
    Scroll() {
      Markdown({
        controller: params.markdownController,
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
      // STARTUP_NOTICE: "我已知晓"  CHECK_UPDATE: "以后再说"
      Button(getResourceString(params.mode === UpdateDialogMode.CHECK_UPDATE
        ? $r('app.string.update_later')
        : $r('app.string.update_acknowledged')))
        .layoutWeight(1)
        .height(40)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.input_background'))
        .onClick(() => {
          params.onClose();
        })

      // STARTUP_NOTICE: "前往查看"  CHECK_UPDATE: "下载更新"
      Button(getResourceString(params.mode === UpdateDialogMode.CHECK_UPDATE
        ? $r('app.string.update_download')
        : $r('app.string.update_view_release')))
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
