import { promptAction, window } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getResourceString } from '../utils/ResourceUtil';
import { UpdateChecker, ReleaseInfo, VersionCompareResult } from '../utils/UpdateChecker';

export class UpdateNoticeManager {
  private static isDialogShowing: boolean = false;

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
          false
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
      return await UpdateNoticeManager.showUpdateDialog(context, release, currentVersion, markAsRead);
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
        await UpdateNoticeManager.showUpdateDialog(context, result.releaseInfo, result.currentVersion, false);
      } else {
        await UpdateNoticeManager.showToast(context, getResourceString($r('app.string.update_already_latest')));
      }
    } catch (err) {
      console.error(`[UpdateNoticeManager] checkManually failed: ${(err as Error).message}`);
      await UpdateNoticeManager.showToast(context, getResourceString($r('app.string.update_check_failed')));
    }
  }

  private static async showUpdateDialog(
    context: common.UIAbilityContext,
    releaseInfo: ReleaseInfo,
    currentVersion: string,
    markAsRead: boolean
  ): Promise<boolean> {
    if (UpdateNoticeManager.isDialogShowing) {
      return false;
    }
    try {
      const mainWindow: window.Window = await window.getLastWindow(context);
      UpdateNoticeManager.isDialogShowing = true;
      mainWindow.getUIContext().getPromptAction().showDialog({
        title: getResourceString($r('app.string.update_notice_title')),
        message: releaseInfo.body.length > 0 ? releaseInfo.body : getResourceString($r('app.string.update_notice_empty')),
        buttons: [
          { text: getResourceString($r('app.string.update_later')), color: $r('app.color.text_secondary') },
          { text: getResourceString($r('app.string.update_view_release')), color: $r('app.color.primary') }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        if (result.index === 1) {
          UpdateNoticeManager.openReleasePage(context, releaseInfo.html_url);
        }
        if (markAsRead) {
          UpdateChecker.markCurrentVersionRead().catch((err: Error) => {
            console.error(`[UpdateNoticeManager] markCurrentVersionRead failed: ${err.message}`);
          });
        }
        UpdateNoticeManager.isDialogShowing = false;
      }).catch((err: Error) => {
        UpdateNoticeManager.isDialogShowing = false;
        console.error(`[UpdateNoticeManager] showUpdateDialog failed: ${err.message}`);
      });
      return true;
    } catch (err) {
      UpdateNoticeManager.isDialogShowing = false;
      console.error(`[UpdateNoticeManager] createUpdateDialog failed: ${(err as Error).message}`);
      return false;
    }
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
