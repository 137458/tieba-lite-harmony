// 偏好持久化 key 注册表（M11：key/类型/默认值/主要写入方单一事实源）
// 禁止在 AppStorageManager 调用点散落 key 字面量；新增偏好先在此注册。
// 三个类型化注册表 + isRegistered 运行时校验（未注册 key 记 warn）。
// 调用点写法：AppStorageManager.getInstance().getNumber(NumberPrefs.HOME_LIST_MODE.key, -1)

/** 数字偏好 key */
export class NumberPreferenceKey {
  readonly key: string;
  readonly defaultValue: number;
  readonly writer: string;

  constructor(key: string, defaultValue: number, writer: string) {
    this.key = key;
    this.defaultValue = defaultValue;
    this.writer = writer;
  }
}

/** 字符串偏好 key */
export class StringPreferenceKey {
  readonly key: string;
  readonly defaultValue: string;
  readonly writer: string;

  constructor(key: string, defaultValue: string, writer: string) {
    this.key = key;
    this.defaultValue = defaultValue;
    this.writer = writer;
  }
}

/** 布尔偏好 key */
export class BooleanPreferenceKey {
  readonly key: string;
  readonly defaultValue: boolean;
  readonly writer: string;

  constructor(key: string, defaultValue: boolean, writer: string) {
    this.key = key;
    this.defaultValue = defaultValue;
    this.writer = writer;
  }
}

/** 数字偏好 key 注册表（默认值 = 首次安装/迁移后的缺省） */
export class NumberPrefs {
  static readonly COLOR_MODE: NumberPreferenceKey = new NumberPreferenceKey('colorMode', 0, 'SettingsPage');
  static readonly DEFAULT_HOME_PAGE: NumberPreferenceKey = new NumberPreferenceKey('default_home_page', 0, 'SettingsPage');
  static readonly FONT_SCALE: NumberPreferenceKey = new NumberPreferenceKey('fontScale', 0, 'SettingsPage');
  static readonly FORUM_FAB_FUNCTION: NumberPreferenceKey = new NumberPreferenceKey('forum_fab_function', 0, 'SettingsPage');
  static readonly FORUM_PAGE_VERSION: NumberPreferenceKey = new NumberPreferenceKey('forum_page_version', 0, 'SettingsPage');
  static readonly HOME_LIST_MODE: NumberPreferenceKey = new NumberPreferenceKey('homeListMode', 0, 'SettingsPage');
  static readonly IMAGE_LOAD_TYPE: NumberPreferenceKey = new NumberPreferenceKey('imageLoadType', 0, 'SettingsPage');
  static readonly MATERIAL_LEVEL: NumberPreferenceKey = new NumberPreferenceKey('materialLevel', 0, 'SettingsPage');
  static readonly TAB_VISIBILITY: NumberPreferenceKey = new NumberPreferenceKey('tabVisibility', 0b1111, 'SettingsPage');
  static readonly THEME_ID: NumberPreferenceKey = new NumberPreferenceKey('themeId', 0, 'ThemePage');
  static readonly USER_LIKE_LAST_REQUEST_UNIX: NumberPreferenceKey = new NumberPreferenceKey('userLikeLastRequestUnix', 0, 'TiebaAPI');

  static readonly ALL_NUMBER: NumberPreferenceKey[] = [NumberPrefs.COLOR_MODE, NumberPrefs.DEFAULT_HOME_PAGE, NumberPrefs.FONT_SCALE, NumberPrefs.FORUM_FAB_FUNCTION, NumberPrefs.FORUM_PAGE_VERSION, NumberPrefs.HOME_LIST_MODE, NumberPrefs.IMAGE_LOAD_TYPE, NumberPrefs.MATERIAL_LEVEL, NumberPrefs.TAB_VISIBILITY, NumberPrefs.THEME_ID, NumberPrefs.USER_LIKE_LAST_REQUEST_UNIX];
}

/** 字符串偏好 key 注册表（默认值 = 空串等读回缺省） */
export class StringPrefs {
  static readonly AES_CBC_SEC_KEY: StringPreferenceKey = new StringPreferenceKey('aes_cbc_sec_key', '', 'CryptoUtil');
  static readonly ANDROID_ID: StringPreferenceKey = new StringPreferenceKey('android_id', '', 'CryptoUtil');
  static readonly AVATAR: StringPreferenceKey = new StringPreferenceKey('avatar', '', 'LoginPage');
  static readonly BAIDUID: StringPreferenceKey = new StringPreferenceKey('baiduid', '', 'WebLoginPage');
  static readonly BDUSS: StringPreferenceKey = new StringPreferenceKey('bduss', '', 'AuthSessionManager');
  static readonly CLIENT_ID: StringPreferenceKey = new StringPreferenceKey('client_id', '', 'TiebaAPI');
  static readonly CUID: StringPreferenceKey = new StringPreferenceKey('cuid', '', 'LoginPage');
  static readonly DEVICE_ID: StringPreferenceKey = new StringPreferenceKey('device_id', '', 'CryptoUtil');
  static readonly LITTLE_TAIL: StringPreferenceKey = new StringPreferenceKey('littleTail', '', 'SettingsPage');
  static readonly NAME: StringPreferenceKey = new StringPreferenceKey('name', '', 'LoginPage');
  static readonly NICKNAME: StringPreferenceKey = new StringPreferenceKey('nickname', '', 'LoginPage');
  static readonly RECENT_FORUMS: StringPreferenceKey = new StringPreferenceKey('recentForums', '[]', 'RecentForumHistory');
  static readonly SAMPLE_ID: StringPreferenceKey = new StringPreferenceKey('sample_id', '', 'TiebaAPI');
  static readonly STOKEN: StringPreferenceKey = new StringPreferenceKey('stoken', '', 'AuthSessionManager');
  static readonly TBS: StringPreferenceKey = new StringPreferenceKey('tbs', '', 'LoginPage');
  static readonly THREAD_DRAFT: StringPreferenceKey = new StringPreferenceKey('thread_draft', '', 'DraftManager');
  static readonly TIEBA_UID: StringPreferenceKey = new StringPreferenceKey('tieba_uid', '', 'TiebaAPI');
  static readonly UID: StringPreferenceKey = new StringPreferenceKey('uid', '', 'LoginPage');
  static readonly UUID: StringPreferenceKey = new StringPreferenceKey('uuid', '', 'CryptoUtil');
  static readonly Z_ID: StringPreferenceKey = new StringPreferenceKey('z_id', '', 'TiebaAPI');

  static readonly ALL_STRING: StringPreferenceKey[] = [StringPrefs.AES_CBC_SEC_KEY, StringPrefs.ANDROID_ID, StringPrefs.AVATAR, StringPrefs.BAIDUID, StringPrefs.BDUSS, StringPrefs.CLIENT_ID, StringPrefs.CUID, StringPrefs.DEVICE_ID, StringPrefs.LITTLE_TAIL, StringPrefs.NAME, StringPrefs.NICKNAME, StringPrefs.RECENT_FORUMS, StringPrefs.SAMPLE_ID, StringPrefs.STOKEN, StringPrefs.TBS, StringPrefs.THREAD_DRAFT, StringPrefs.TIEBA_UID, StringPrefs.UID, StringPrefs.UUID, StringPrefs.Z_ID];
}

/** 布尔偏好 key 注册表 */
export class BooleanPrefs {
  static readonly APP_LOCK_ENABLED: BooleanPreferenceKey = new BooleanPreferenceKey('appLockEnabled', false, 'SettingsPage');
  static readonly CREDENTIAL_NON_PERSISTENT_MIGRATED: BooleanPreferenceKey = new BooleanPreferenceKey('credentialNonPersistentMigrated', false, 'AuthSessionManager');
  static readonly DYNAMIC_COLOR_ENABLED: BooleanPreferenceKey = new BooleanPreferenceKey('dynamicColorEnabled', false, 'ThemePage');
  static readonly FORUM_COMMENT_PREVIEW: BooleanPreferenceKey = new BooleanPreferenceKey('forumCommentPreview', false, 'SettingsPage');
  static readonly HOME_DUAL_COLUMN: BooleanPreferenceKey = new BooleanPreferenceKey('homeDualColumn', false, 'Index');
  static readonly NOTIFICATION_ENABLED: BooleanPreferenceKey = new BooleanPreferenceKey('notificationEnabled', false, 'SettingsPage');
  static readonly RECEIVE_PRERELEASE_UPDATES: BooleanPreferenceKey = new BooleanPreferenceKey('receivePrereleaseUpdates', false, 'SettingsPage');
  static readonly SHOW_RECENT_FORUMS: BooleanPreferenceKey = new BooleanPreferenceKey('showRecentForums', false, 'SettingsPage');
  static readonly THREAD_COMMENT_PREVIEW: BooleanPreferenceKey = new BooleanPreferenceKey('threadCommentPreview', true, 'SettingsPage');
  static readonly THREAD_FLOATING_BAR: BooleanPreferenceKey = new BooleanPreferenceKey('threadFloatingBar', false, 'SettingsPage');
  static readonly VIBRATOR_ENABLED: BooleanPreferenceKey = new BooleanPreferenceKey('vibratorEnabled', true, 'SettingsPage');

  static readonly ALL_BOOLEAN: BooleanPreferenceKey[] = [BooleanPrefs.APP_LOCK_ENABLED, BooleanPrefs.CREDENTIAL_NON_PERSISTENT_MIGRATED, BooleanPrefs.DYNAMIC_COLOR_ENABLED, BooleanPrefs.FORUM_COMMENT_PREVIEW, BooleanPrefs.HOME_DUAL_COLUMN, BooleanPrefs.NOTIFICATION_ENABLED, BooleanPrefs.RECEIVE_PRERELEASE_UPDATES, BooleanPrefs.SHOW_RECENT_FORUMS, BooleanPrefs.THREAD_COMMENT_PREVIEW, BooleanPrefs.THREAD_FLOATING_BAR, BooleanPrefs.VIBRATOR_ENABLED];
}

/** 注册表统一入口：key 存在性校验（AppStorageManager 各访问器调用，未注册记 warn） */
export class PreferenceKeys {
  private static readonly ALL_NUMBER: NumberPreferenceKey[] = NumberPrefs.ALL_NUMBER;
  private static readonly ALL_STRING: StringPreferenceKey[] = StringPrefs.ALL_STRING;
  private static readonly ALL_BOOLEAN: BooleanPreferenceKey[] = BooleanPrefs.ALL_BOOLEAN;

  static isRegistered(key: string): boolean {
    for (let i = 0; i < PreferenceKeys.ALL_NUMBER.length; i++) {
      if (PreferenceKeys.ALL_NUMBER[i].key === key) {
        return true;
      }
    }
    for (let i = 0; i < PreferenceKeys.ALL_STRING.length; i++) {
      if (PreferenceKeys.ALL_STRING[i].key === key) {
        return true;
      }
    }
    for (let i = 0; i < PreferenceKeys.ALL_BOOLEAN.length; i++) {
      if (PreferenceKeys.ALL_BOOLEAN[i].key === key) {
        return true;
      }
    }
    return false;
  }
}
