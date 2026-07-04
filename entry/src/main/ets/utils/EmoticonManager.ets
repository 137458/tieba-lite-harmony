// 表情资源管理（issue #74）
// 对齐 Android TiebaLite EmoticonManager.kt:61-121
// 表情在 content 中以 #(表情名) 格式插入，服务端解析为图片显示
// 表情图 URL: https://static.tieba.baidu.com/tb/editor/images/client/{id}.png

/** 表情信息 */
export class EmoticonInfo {
  /** 表情 id（如 image_emoticon25） */
  id: string = '';
  /** 表情名（如 滑稽） */
  name: string = '';
}

/**
 * 表情管理器
 * 提供 name ↔ id 映射 + URL 构造 + #(表情名) 标记构造
 * 映射表来源：TiebaLite-4.0-dev EmoticonManager.kt:61-121 DEFAULT_EMOTICON_MAPPING
 */
export class EmoticonManager {
  /** 表情图 CDN 基础路径（对齐 TiebaLite EmoticonManager.kt:303） */
  private static readonly CDN_BASE: string = 'https://static.tieba.baidu.com/tb/editor/images/client/';

  /** 表情名列表（与 IDS 一一对应，对齐 EmoticonManager.kt:61-121 顺序） */
  private static readonly NAMES: string[] = [
    '呵呵', '哈哈', '吐舌', '啊', '酷', '怒', '开心', '汗', '泪', '黑线',
    '鄙视', '不高兴', '真棒', '钱', '疑问', '阴险', '吐', '咦', '委屈', '花心',
    '呼~', '笑眼', '冷', '太开心', '滑稽', '勉强', '狂汗', '乖', '睡觉', '惊哭',
    '生气', '惊讶', '喷', '爱心', '心碎', '玫瑰', '礼物', '彩虹', '星星月亮', '太阳',
    '钱币', '灯泡', '茶杯', '蛋糕', '音乐', 'haha', '胜利', '大拇指', '弱', 'OK',
    '沙发', '手纸', '香蕉', '便便', '药丸', '红领巾', '蜡烛', '三道杠'
  ];

  /** 表情 id 列表（与 NAMES 一一对应） */
  private static readonly IDS: string[] = [
    'image_emoticon1', 'image_emoticon2', 'image_emoticon3', 'image_emoticon4', 'image_emoticon5',
    'image_emoticon6', 'image_emoticon7', 'image_emoticon8', 'image_emoticon9', 'image_emoticon10',
    'image_emoticon11', 'image_emoticon12', 'image_emoticon13', 'image_emoticon14', 'image_emoticon15',
    'image_emoticon16', 'image_emoticon17', 'image_emoticon18', 'image_emoticon19', 'image_emoticon20',
    'image_emoticon21', 'image_emoticon22', 'image_emoticon23', 'image_emoticon24', 'image_emoticon25',
    'image_emoticon26', 'image_emoticon27', 'image_emoticon28', 'image_emoticon29', 'image_emoticon30',
    'image_emoticon31', 'image_emoticon32', 'image_emoticon33', 'image_emoticon34', 'image_emoticon35',
    'image_emoticon36', 'image_emoticon37', 'image_emoticon38', 'image_emoticon39', 'image_emoticon40',
    'image_emoticon41', 'image_emoticon42', 'image_emoticon43', 'image_emoticon44', 'image_emoticon45',
    'image_emoticon46', 'image_emoticon47', 'image_emoticon48', 'image_emoticon49', 'image_emoticon50',
    'image_emoticon77', 'image_emoticon78', 'image_emoticon79', 'image_emoticon80',
    'image_emoticon81', 'image_emoticon82', 'image_emoticon83', 'image_emoticon84'
  ];

  /** 缓存的所有表情列表 */
  private static emoticonList: EmoticonInfo[] | null = null;

  /**
   * 构造表情图 URL
   * @param id 表情 id（如 image_emoticon25）
   * @returns 完整 CDN URL
   */
  static getEmoticonUrl(id: string): string {
    return EmoticonManager.CDN_BASE + id + '.png';
  }

  /**
   * 构造 #(表情名) 标记（用于插入回帖 content）
   * @param name 表情名（如 滑稽）
   * @returns #(滑稽) 格式标记
   */
  static buildEmoticonMark(name: string): string {
    return `#(${name})`;
  }

  /**
   * 根据 name 查询表情信息
   * @param name 表情名
   * @returns EmoticonInfo 或 undefined（未找到）
   */
  static getEmoticonByName(name: string): EmoticonInfo | undefined {
    // 并行数组查表：NAMES.indexOf 定位索引，IDS[index] 取对应 id
    const index: number = EmoticonManager.NAMES.indexOf(name);
    if (index < 0) {
      return undefined;
    }
    const info: EmoticonInfo = new EmoticonInfo();
    info.id = EmoticonManager.IDS[index];
    info.name = name;
    return info;
  }

  /**
   * 获取所有表情列表（按映射表顺序）
   * 首次调用时构建并缓存，后续直接返回缓存
   */
  static getAllEmoticons(): EmoticonInfo[] {
    if (EmoticonManager.emoticonList !== null) {
      return EmoticonManager.emoticonList;
    }
    const list: EmoticonInfo[] = [];
    // 并行数组同步遍历（NAMES 与 IDS 一一对应，长度相同）
    for (let i = 0; i < EmoticonManager.NAMES.length; i++) {
      const info: EmoticonInfo = new EmoticonInfo();
      info.id = EmoticonManager.IDS[i];
      info.name = EmoticonManager.NAMES[i];
      list.push(info);
    }
    EmoticonManager.emoticonList = list;
    return list;
  }
}
