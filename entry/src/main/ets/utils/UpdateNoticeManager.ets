import { promptAction, window, ComponentContent } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getResourceString } from '../utils/ResourceUtil';
import { UpdateChecker, ReleaseInfo, VersionCompareResult } from '../utils/UpdateChecker';
import { UpdateContentBuilder, UpdateContentParams, UpdateDialogMode } from '../components/UpdateDialog';

export class UpdateNoticeManager {
  private static isDialogShowing: boolean = false;
  // 当前对话框的 ComponentContent，关闭时需 dispose 释放资源
  private static currentContent: ComponentContent<UpdateContentParams> | null = null;

  static async checkOnStartup(context: common.UIAbilityContext): Promise<boolean> {
    if (UpdateNoticeManager.isDialogShowing) {
      return false;
    }
    try {
      const result: VersionCompareResult = await UpdateChecker.checkUpdate();
      if (result.hasUpdate && result.releaseInfo !== null) {
        return await UpdateNoticeManager.showUpdateDialog(
          context,
          result.releaseInfo,
          result.currentVersion,
          false,
          UpdateDialogMode.CHECK_UPDATE
        );
      }
    } catch (err) {
      console.error(`[UpdateNoticeManager] checkOnStartup failed: ${(err as Error).message}`);
    }
    return false;
  }

  static async showStartupNoticeIfNeed(context: common.UIAbilityContext): Promise<boolean> {
    if (UpdateNoticeManager.isDialogShowing) {
      return false;
    }
    try {
      const needShow: boolean = await UpdateChecker.shouldShowUpdateNotice();
      if (!needShow) {
        return false;
      }
      return await UpdateNoticeManager.showCurrentVersionNotice(context, true);
    } catch (err) {
      console.error(`[UpdateNoticeManager] showStartupNoticeIfNeed failed: ${(err as Error).message}`);
      return false;
    }
  }

  static async showCurrentVersionNotice(context: common.UIAbilityContext, markAsRead: boolean): Promise<boolean> {
    if (UpdateNoticeManager.isDialogShowing) {
      return false;
    }
    const currentVersion: string = UpdateChecker.getCurrentVersion();
    if (currentVersion.length === 0) {
      if (!markAsRead) {
        await UpdateNoticeManager.showToast(context, getResourceString($r('app.string.update_check_failed')));
      }
      return false;
    }
    try {
      const release: ReleaseInfo = await UpdateChecker.fetchReleaseByVersion(currentVersion);
      return await UpdateNoticeManager.showUpdateDialog(context, release, currentVersion, markAsRead, UpdateDialogMode.STARTUP_NOTICE);
    } catch (err) {
      console.error(`[UpdateNoticeManager] showCurrentVersionNotice failed: ${(err as Error).message}`);
      if (!markAsRead) {
        await UpdateNoticeManager.showToast(context, getResourceString($r('app.string.update_notice_load_failed')));
      }
      return false;
    }
  }

  static async checkManually(context: common.UIAbilityContext): Promise<void> {
    if (UpdateNoticeManager.isDialogShowing) {
      return;
    }
    await UpdateNoticeManager.showToast(context, getResourceString($r('app.string.update_checking')));
    try {
      const result: VersionCompareResult = await UpdateChecker.checkUpdate();
      if (result.hasUpdate && result.releaseInfo !== null) {
        await UpdateNoticeManager.showUpdateDialog(context, result.releaseInfo, result.currentVersion, false, UpdateDialogMode.CHECK_UPDATE);
      } else {
        await UpdateNoticeManager.showToast(context, getResourceString($r('app.string.update_already_latest')));
      }
    } catch (err) {
      console.error(`[UpdateNoticeManager] checkManually failed: ${(err as Error).message}`);
      await UpdateNoticeManager.showToast(context, getResourceString($r('app.string.update_check_failed')));
    }
  }

  /**
   * 显示更新公告对话框（使用 ComponentContent + openCustomDialog 实现 Markdown 渲染）
   * 替代原 showDialog 纯文本显示方式，支持 GitHub Release 的 Markdown 格式 body
   */
  private static async showUpdateDialog(
    context: common.UIAbilityContext,
    releaseInfo: ReleaseInfo,
    currentVersion: string,
    markAsRead: boolean,
    mode: UpdateDialogMode
  ): Promise<boolean> {
    if (UpdateNoticeManager.isDialogShowing) {
      return false;
    }
    try {
      const mainWindow: window.Window = await window.getLastWindow(context);
      const uiContext = mainWindow.getUIContext();
      UpdateNoticeManager.isDialogShowing = true;

      // 构建对话框参数
      const params: UpdateContentParams = new UpdateContentParams();
      params.configureMarkdownStyle();
      params.releaseInfo = releaseInfo;
      params.currentVersion = currentVersion;
      params.mode = mode;
      params.onClose = () => {
        UpdateNoticeManager.closeDialog(uiContext);
        if (markAsRead) {
          UpdateChecker.markCurrentVersionRead().catch((err: Error) => {
            console.error(`[UpdateNoticeManager] markCurrentVersionRead failed: ${err.message}`);
          });
        }
      };
      params.onOpenRelease = () => {
        UpdateNoticeManager.closeDialog(uiContext);
        UpdateNoticeManager.openReleasePage(context, releaseInfo.html_url);
        if (markAsRead) {
          UpdateChecker.markCurrentVersionRead().catch((err: Error) => {
            console.error(`[UpdateNoticeManager] markCurrentVersionRead failed: ${err.message}`);
          });
        }
      };

      // 创建 ComponentContent 并显示自定义对话框
      // 对话框样式（width/height/cornerRadius/backgroundColor）在 UpdateContentBuilder 根容器设置
      UpdateNoticeManager.currentContent = new ComponentContent<UpdateContentParams>(
        uiContext,
        wrapBuilder(UpdateContentBuilder),
        params
      );

      await uiContext.getPromptAction().openCustomDialog(UpdateNoticeManager.currentContent, {
        alignment: DialogAlignment.Center,
        autoCancel: false
      });

      return true;
    } catch (err) {
      UpdateNoticeManager.isDialogShowing = false;
      UpdateNoticeManager.currentContent = null;
      console.error(`[UpdateNoticeManager] showUpdateDialog failed: ${(err as Error).message}`);
      return false;
    }
  }

  /**
   * 关闭当前对话框并释放 ComponentContent 资源
   */
  private static closeDialog(uiContext: UIContext): void {
    if (UpdateNoticeManager.currentContent !== null) {
      uiContext.getPromptAction().closeCustomDialog(UpdateNoticeManager.currentContent);
      UpdateNoticeManager.currentContent.dispose();
      UpdateNoticeManager.currentContent = null;
    }
    UpdateNoticeManager.isDialogShowing = false;
  }

  private static openReleasePage(context: common.UIAbilityContext, url: string): void {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    context.startAbility(want).catch((err: BusinessError) => {
      console.error(`[UpdateNoticeManager] openReleasePage failed: ${err.code} ${err.message}`);
      UpdateNoticeManager.showToast(context, getResourceString($r('app.string.about_open_failed'))).catch((toastErr: Error) => {
        console.error(`[UpdateNoticeManager] showOpenFailedToast failed: ${toastErr.message}`);
      });
    });
  }

  private static async showToast(context: common.UIAbilityContext, message: string): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(context);
      mainWindow.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      console.error(`[UpdateNoticeManager] showToast failed: ${(err as Error).message}`);
    }
  }
}
