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

  /** name → id 映射表（对齐 EmoticonManager.kt:61-121） */
  private static readonly MAPPING: Record<string, string> = {
    '呵呵': 'image_emoticon1',
    '哈哈': 'image_emoticon2',
    '吐舌': 'image_emoticon3',
    '啊': 'image_emoticon4',
    '酷': 'image_emoticon5',
    '怒': 'image_emoticon6',
    '开心': 'image_emoticon7',
    '汗': 'image_emoticon8',
    '泪': 'image_emoticon9',
    '黑线': 'image_emoticon10',
    '鄙视': 'image_emoticon11',
    '不高兴': 'image_emoticon12',
    '真棒': 'image_emoticon13',
    '钱': 'image_emoticon14',
    '疑问': 'image_emoticon15',
    '阴险': 'image_emoticon16',
    '吐': 'image_emoticon17',
    '咦': 'image_emoticon18',
    '委屈': 'image_emoticon19',
    '花心': 'image_emoticon20',
    '呼~': 'image_emoticon21',
    '笑眼': 'image_emoticon22',
    '冷': 'image_emoticon23',
    '太开心': 'image_emoticon24',
    '滑稽': 'image_emoticon25',
    '勉强': 'image_emoticon26',
    '狂汗': 'image_emoticon27',
    '乖': 'image_emoticon28',
    '睡觉': 'image_emoticon29',
    '惊哭': 'image_emoticon30',
    '生气': 'image_emoticon31',
    '惊讶': 'image_emoticon32',
    '喷': 'image_emoticon33',
    '爱心': 'image_emoticon34',
    '心碎': 'image_emoticon35',
    '玫瑰': 'image_emoticon36',
    '礼物': 'image_emoticon37',
    '彩虹': 'image_emoticon38',
    '星星月亮': 'image_emoticon39',
    '太阳': 'image_emoticon40',
    '钱币': 'image_emoticon41',
    '灯泡': 'image_emoticon42',
    '茶杯': 'image_emoticon43',
    '蛋糕': 'image_emoticon44',
    '音乐': 'image_emoticon45',
    'haha': 'image_emoticon46',
    '胜利': 'image_emoticon47',
    '大拇指': 'image_emoticon48',
    '弱': 'image_emoticon49',
    'OK': 'image_emoticon50',
    '沙发': 'image_emoticon77',
    '手纸': 'image_emoticon78',
    '香蕉': 'image_emoticon79',
    '便便': 'image_emoticon80',
    '药丸': 'image_emoticon81',
    '红领巾': 'image_emoticon82',
    '蜡烛': 'image_emoticon83',
    '三道杠': 'image_emoticon84'
  };

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
    const id: string | undefined = EmoticonManager.MAPPING[name];
    if (id === undefined) {
      return undefined;
    }
    const info: EmoticonInfo = new EmoticonInfo();
    info.id = id;
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
    const keys = Object.keys(EmoticonManager.MAPPING);
    for (let i = 0; i < keys.length; i++) {
      const name: string = keys[i];
      const id: string = EmoticonManager.MAPPING[name];
      const info: EmoticonInfo = new EmoticonInfo();
      info.id = id;
      info.name = name;
      list.push(info);
    }
    EmoticonManager.emoticonList = list;
    return list;
  }
}
