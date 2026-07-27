// 更新公告管理器
// 封装更新检查 + 弹窗显示逻辑，供 EntryAbility（启动检查）和 SettingsPage（手动检查）调用
//
// 两种触发场景：
// 1. 启动检查（EntryAbility）：应用启动后静默调用 UpdateChecker.checkUpdate，
//    - 有新版本：弹 UpdateDialog 显示新版本公告
//    - 无新版本：静默不弹窗
//    - 检查失败：静默不弹窗（用户不感知）
// 2. 手动检查（SettingsPage）：用户点"检查更新"按钮后调用，
//    - 检查中：Toast 提示"正在检查更新..."
//    - 有新版本：弹 UpdateDialog 显示新版本公告
//    - 无新版本：Toast 提示"已是最新版本"
//    - 检查失败：Toast 提示"检查更新失败，请检查网络后重试"

import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getResourceString } from '../utils/ResourceUtil';
import { UpdateChecker, ReleaseInfo, VersionCompareResult } from '../utils/UpdateChecker';
import { UpdateDialog, UpdateDialogMode } from '../components/UpdateDialog';

export class UpdateNoticeManager {
  /**
   * 启动时自动检查更新（后台静默）
   * EntryAbility 启动完成后调用，有新版本时弹窗，失败时静默
   * @param context UIAbilityContext，用于创建 CustomDialogController
   */
  static async checkOnStartup(context: common.UIAbilityContext): Promise<void> {
    try {
      const result: VersionCompareResult = await UpdateChecker.checkUpdate();
      if (result.hasUpdate && result.releaseInfo !== null) {
        // 有新版本：弹窗显示更新公告
        UpdateNoticeManager.showUpdateDialog(
          context,
          UpdateDialogMode.CHECK_UPDATE,
          result.releaseInfo,
          result.currentVersion
        );
      }
      // 无新版本：静默不弹窗
    } catch (err) {
      // 启动检查失败：静默，不提示用户
      console.error(`[UpdateNoticeManager] checkOnStartup failed: ${(err as Error).message}`);
    }
  }

  /**
   * 启动时检查是否需要显示更新公告（应用更新后首次进入）
   * EntryAbility 启动完成后调用，与 checkOnStartup 独立
   * 通过比较当前版本与已读版本判断是否需要弹窗
   * @param context UIAbilityContext
   */
  static async showStartupNoticeIfNeed(context: common.UIAbilityContext): Promise<void> {
    try {
      const needShow: boolean = await UpdateChecker.shouldShowUpdateNotice();
      if (!needShow) {
        return;
      }
      // 需要显示：拉取当前版本的 Release 公告
      const currentVersion: string = UpdateChecker.getCurrentVersion();
      if (currentVersion.length === 0) {
        return;
      }
      // 拉取最新 Release，如果 tag_name 与当前版本匹配，显示其 body 作为公告
      const release: ReleaseInfo = await UpdateChecker.fetchLatestRelease();
      // 用当前版本号构造 ReleaseInfo（即使服务端最新版本与当前不一致，也显示当前版本的公告）
      // 服务端可能没有当前版本的 Release，此时 body 为空，弹窗显示"已是最新版本"
      const currentRelease: ReleaseInfo = new ReleaseInfo();
      if (UpdateChecker.compareVersions(currentVersion, release.tag_name) === 0) {
        // 当前版本就是最新 Release，直接用其 body
        currentRelease.tag_name = release.tag_name;
        currentRelease.body = release.body;
        currentRelease.html_url = release.html_url;
        currentRelease.name = release.name;
        currentRelease.published_at = release.published_at;
      } else {
        // 当前版本不是最新 Release（可能是中间版本），body 为空
        currentRelease.tag_name = currentVersion;
        currentRelease.body = '';
        currentRelease.html_url = release.html_url;
      }
      UpdateNoticeManager.showUpdateDialog(
        context,
        UpdateDialogMode.STARTUP_NOTICE,
        currentRelease,
        currentVersion
      );
    } catch (err) {
      // 启动公告检查失败：静默，不阻塞用户使用
      console.error(`[UpdateNoticeManager] showStartupNoticeIfNeed failed: ${(err as Error).message}`);
    }
  }

  /**
   * 手动检查更新（设置页"检查更新"按钮）
   * 检查中 Toast 提示，完成后弹窗或 Toast 提示结果
   * @param context UIAbilityContext
   */
  static async checkManually(context: common.UIAbilityContext): Promise<void> {
    promptAction.showToast({ message: getResourceString($r('app.string.update_checking')) });
    try {
      const result: VersionCompareResult = await UpdateChecker.checkUpdate();
      if (result.hasUpdate && result.releaseInfo !== null) {
        // 有新版本：弹窗
        UpdateNoticeManager.showUpdateDialog(
          context,
          UpdateDialogMode.CHECK_UPDATE,
          result.releaseInfo,
          result.currentVersion
        );
      } else {
        // 已是最新版本
        promptAction.showToast({
          message: getResourceString($r('app.string.update_already_latest'))
        });
      }
    } catch (err) {
      console.error(`[UpdateNoticeManager] checkManually failed: ${(err as Error).message}`);
      promptAction.showToast({
        message: getResourceString($r('app.string.update_check_failed'))
      });
    }
  }

  /**
   * 显示更新公告弹窗
   * @param context UIAbilityContext
   * @param mode 弹窗模式
   * @param releaseInfo Release 信息
   * @param currentVersion 当前版本号
   */
  private static showUpdateDialog(
    context: common.UIAbilityContext,
    mode: UpdateDialogMode,
    releaseInfo: ReleaseInfo,
    currentVersion: string
  ): void {
    const controller: CustomDialogController = new CustomDialogController({
      builder: UpdateDialog({
        mode: mode,
        releaseInfo: releaseInfo,
        currentVersion: currentVersion,
        onClose: (): void => {
          // 启动公告场景：标记当前版本已读
          if (mode === UpdateDialogMode.STARTUP_NOTICE) {
            UpdateChecker.markCurrentVersionRead().catch((err: Error) => {
              console.error(`[UpdateNoticeManager] markCurrentVersionRead failed: ${err.message}`);
            });
          }
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: false
    });
    controller.open();
  }
}
