// M03 AppStartup 任务：用户偏好装配（依赖 AppStorageInit，主线程）
// 自 Index.aboutToAppear 迁入：preferences 读回 → 写 AppStorageV2（含 4 组哨兵迁移），
// 组合根（Index 路由容器）不再承担偏好装配职责。
// waitOnMainThread=true：装配须在子页面（HomePage/FavoritePage 等订阅方）读取前完成，
// 与原 Index 首帧前 await 的时序等价；#290 并行读优化原样保留。

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageManager } from '../data/AppStorage';
import { BooleanPrefs, NumberPrefs } from '../data/PreferenceKeys';
import {
  HomeListModeState, connectHomeListMode, TabVisibilityState, connectTabVisibility,
  MaterialLevelState, connectMaterialLevel, HomeDualColumnState, connectHomeDualColumn,
  ForumPageVersionState, connectForumPageVersion, ForumFabFunctionState, connectForumFabFunction,
  DefaultHomePageState, connectDefaultHomePage, ForumCommentPreviewState, connectForumCommentPreview,
  ThreadCommentPreviewState, connectThreadCommentPreview, RecentForumsState, connectRecentForums
} from '../model/AppStorageV2Models';
import { VibratorUtil } from '../utils/VibratorUtil';

@Sendable
export default class StartupTask_Prefs extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'StartupTask_Prefs', '%{public}s', 'StartupTask_Prefs init start');
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      // #290 冷启动优化：并行发起所有独立偏好读取，preferences I/O 重叠执行
      const pTabVisibility: Promise<number> = storage.getNumber(NumberPrefs.TAB_VISIBILITY.key, 0b1111);
      const pMaterialLevel: Promise<number> = storage.getNumber(NumberPrefs.MATERIAL_LEVEL.key, 0);
      const pHomeListMode: Promise<number> = storage.getNumber(NumberPrefs.HOME_LIST_MODE.key, -1);
      const pForumPageVersion: Promise<number> = storage.getNumber(NumberPrefs.FORUM_PAGE_VERSION.key, -1);
      const pForumFabFunction: Promise<number> = storage.getNumber(NumberPrefs.FORUM_FAB_FUNCTION.key, -1);
      const pDefaultHomePage: Promise<number> = storage.getNumber(NumberPrefs.DEFAULT_HOME_PAGE.key, -1);
      const pForumCommentPreview: Promise<boolean> = storage.getBoolean(BooleanPrefs.FORUM_COMMENT_PREVIEW.key, false);
      const pThreadCommentPreview: Promise<boolean> = storage.getBoolean(BooleanPrefs.THREAD_COMMENT_PREVIEW.key, true);
      const pShowRecentForums: Promise<boolean> = storage.getBoolean(BooleanPrefs.SHOW_RECENT_FORUMS.key, false);
      const pOldHomeDualColumn: Promise<boolean> = storage.getBoolean(BooleanPrefs.HOME_DUAL_COLUMN.key, false);

      // #234 持久化机制：AppStorageV2 默认内存态；启动读回 preferences 写入 AppStorageV2，
      // 确保重启后用户偏好不丢失
      const tabVisibilityValue: number = await pTabVisibility;
      const tabVisibilityState: TabVisibilityState = connectTabVisibility();
      // 至少保留首页 bit0=1（防止 preferences 数据异常导致全部隐藏）
      tabVisibilityState.value = tabVisibilityValue | 0b0001;
      const materialLevelValue: number = await pMaterialLevel;
      const materialLevelState: MaterialLevelState = connectMaterialLevel();
      materialLevelState.value = materialLevelValue;
      // #234 首页列表模式（3档枚举）：
      // 1) 先读新 key 'homeListMode'，0=SINGLE/1=DOUBLE_FULL/2=DOUBLE_COMPACT
      // 2) 旧用户迁移：若 'homeListMode' 未设置（默认0）但旧 key 'homeDualColumn'=true，
      //    迁移为 DOUBLE_FULL=1，并立即写入新 key（避免下次启动重复迁移）
      // 3) 旧 key 'homeDualColumn' 的 AppStorageV2 同步仍保留（HomePage 历史代码暂未完全切换，
      //    slice D 将把 HomePage 改为读 HomeListModeState，届时旧 dualColumnState 不再被订阅）
      let homeListModeValue: number = await pHomeListMode;
      if (homeListModeValue < 0) {
        // 新 key 未设置：检查旧 key 是否为 true，是则迁移为 DOUBLE_FULL
        const oldHomeDualColumn: boolean = await pOldHomeDualColumn;
        homeListModeValue = oldHomeDualColumn ? 1 : 0;
        await storage.setNumber(NumberPrefs.HOME_LIST_MODE.key, homeListModeValue);
      }
      const homeListModeState: HomeListModeState = connectHomeListMode();
      homeListModeState.value = homeListModeValue;
      // 旧 dualColumnState 同步（向后兼容，slice D 完成后可移除）
      const dualColumnState: HomeDualColumnState = connectHomeDualColumn();
      dualColumnState.value = homeListModeValue !== 0;
      // 完整版吧内页面开关 + 吧内 FAB 功能模式：新 key 启用迁移，
      // 先读新 key（-1 哨兵=未落盘），不存在则写入默认值 0 并立即 setNumber 持久化
      let forumPageVersionValue: number = await pForumPageVersion;
      if (forumPageVersionValue < 0) {
        forumPageVersionValue = 0;
        await storage.setNumber(NumberPrefs.FORUM_PAGE_VERSION.key, forumPageVersionValue);
      }
      const forumPageVersionState: ForumPageVersionState = connectForumPageVersion();
      forumPageVersionState.value = forumPageVersionValue;
      let forumFabFunctionValue: number = await pForumFabFunction;
      if (forumFabFunctionValue < 0) {
        forumFabFunctionValue = 0;
        await storage.setNumber(NumberPrefs.FORUM_FAB_FUNCTION.key, forumFabFunctionValue);
      }
      const forumFabFunctionState: ForumFabFunctionState = connectForumFabFunction();
      forumFabFunctionState.value = forumFabFunctionValue;
      // 默认启动页（0=首页/1=收藏/2=消息/3=我的），同上哨兵迁移
      let defaultHomePageValue: number = await pDefaultHomePage;
      if (defaultHomePageValue < 0) {
        defaultHomePageValue = 0;
        await storage.setNumber(NumberPrefs.DEFAULT_HOME_PAGE.key, defaultHomePageValue);
      }
      const defaultHomePageState: DefaultHomePageState = connectDefaultHomePage();
      defaultHomePageState.value = defaultHomePageValue;
      const forumCommentPreviewState: ForumCommentPreviewState = connectForumCommentPreview();
      forumCommentPreviewState.value = await pForumCommentPreview;
      const threadCommentPreviewState: ThreadCommentPreviewState = connectThreadCommentPreview();
      threadCommentPreviewState.value = await pThreadCommentPreview;
      const recentForumsState: RecentForumsState = connectRecentForums();
      recentForumsState.value = await pShowRecentForums;
      // 触感反馈偏好同步到 VibratorUtil 内存（冷启动时需 init 才能全局生效）
      await VibratorUtil.init();
      hilog.info(0x0000, 'StartupTask_Prefs', '%{public}s', 'StartupTask_Prefs init success');
    } catch (err) {
      // 读取失败不阻塞启动：各状态保持 connect 默认值（对齐原 Index catch 行为）
      hilog.error(0x0000, 'StartupTask_Prefs',
        'StartupTask_Prefs init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_Prefs';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    hilog.info(0x0000, 'StartupTask_Prefs',
      'StartupTask_Prefs onDependencyCompleted, dependence=%{public}s', dependence);
  }
}
