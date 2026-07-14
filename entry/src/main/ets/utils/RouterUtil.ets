// #162 [A4-S1] Navigation 路由迁移基础设施
// 全局 NavPathStack 管理 + 路由常量 + 跳转封装方法
//
// 替代 router.pushUrl/replaceUrl/back，提供 Navigation 组件级路由能力
// 使用方式：
//   1. Index.ets 创建 NavPathStack 后调用 RouterUtil.setStack(stack) 注册全局栈
//   2. 跳转：RouterUtil.push(RouterUtil.ROUTE_SETTINGS_PAGE)
//   3. 带参跳转：RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid))
//   4. 返回：RouterUtil.back() / RouterUtil.backTo(name) / RouterUtil.backToRoot()
//
// 注意：页面已在 router_map.json 注册，各页面通过 RouterUtil.xxx 操作导航栈

import { UIContext } from '@kit.ArkUI';

/**
 * ThreadPage 路由参数（#163 提取为公共 class，供所有调用方实例化）
 * ArkTS 严格类型不允许无类型对象字面量传参，必须用显式 class 实例
 * #175 tid 统一为 number 类型，与 SubPostsNavParams.tid 保持一致
 */
export class ThreadNavParams {
  tid: number;
  seeLz: boolean;

  constructor(tid: number, seeLz: boolean = false) {
    this.tid = tid;
    this.seeLz = seeLz;
  }
}

/**
 * SubPostsPage 路由参数（#163 提取为公共 class）
 */
export class SubPostsNavParams {
  tid: number;
  pid: number;
  floor: number;

  constructor(tid: number, pid: number, floor: number) {
    this.tid = tid;
    this.pid = pid;
    this.floor = floor;
  }
}

/**
 * ForumPage 路由参数（#164 提取为公共 class）
 */
export class ForumNavParams {
  forumName: string;

  constructor(forumName: string) {
    this.forumName = forumName;
  }
}

/**
 * FollowsPage 路由参数（#165 提取为公共 class）
 * userId 必需，userName 可选（标题显示），initialTab 可选（0=关注默认 / 1=粉丝）
 */
export class FollowsNavParams {
  userId: number;
  userName: string;
  initialTab: number;

  constructor(userId: number, userName: string = '', initialTab: number = 0) {
    this.userId = userId;
    this.userName = userName;
    this.initialTab = initialTab;
  }
}

/**
 * SearchPage 路由参数（#165 提取为公共 class）
 * fname 可选（吧内搜索非空，全吧搜索为空），keyword 可选
 */
export class SearchNavParams {
  fname: string;
  keyword: string;

  constructor(fname: string = '', keyword: string = '') {
    this.fname = fname;
    this.keyword = keyword;
  }
}

/**
 * UserProfilePage 路由参数（#165 提取为公共 class）
 * portrait 必需（panel API 主查询参数），userName 可选 fallback，uid 可选回填
 */
export class UserProfileNavParams {
  portrait: string;
  userName: string;
  uid: number;

  constructor(portrait: string, userName: string = '', uid: number = 0) {
    this.portrait = portrait;
    this.userName = userName;
    this.uid = uid;
  }
}

/**
 * ImageViewerPage 路由参数（#165 提取为公共 class）
 * urls 图片 URL 数组，index 初始展示索引
 * #132 shareId 共享元素转场 ID（源端 Image 与目标端 Image 绑定同 id 实现转场动画）
 */
export class ImageViewerNavParams {
  urls: string[];
  index: number;
  shareId: string;

  constructor(urls: string[], index: number = 0, shareId: string = '') {
    this.urls = urls;
    this.index = index;
    this.shareId = shareId;
  }
}

/**
 * TopicDetailPage 路由参数（#165 提取为公共 class）
 * topicId 必需，topicName 可选（标题显示）
 */
export class TopicDetailNavParams {
  topicId: string;
  topicName: string;

  constructor(topicId: string, topicName: string = '') {
    this.topicId = topicId;
    this.topicName = topicName;
  }
}

/**
 * 路由常量
 * 对应 main_pages.json 中注册的 17 个页面（除 Index 外，Index 是 Navigation 容器入口）
 * 在 router_map.json 中用这些 name 注册
 */
export class RouterUtil {
  // ========== 路由常量 ==========
  /** 登录页（BDUSS 登录） */
  static readonly ROUTE_LOGIN_PAGE: string = 'LoginPage';
  /** 网页登录页（百度账号登录） */
  static readonly ROUTE_WEB_LOGIN_PAGE: string = 'WebLoginPage';
  /** 主页面（Tab 容器，首页/消息/收藏/我的） */
  static readonly ROUTE_MAIN_PAGE: string = 'MainPage';
  /** 吧详情页 */
  static readonly ROUTE_FORUM_PAGE: string = 'ForumPage';
  /** 关注吧列表页 */
  static readonly ROUTE_FOLLOW_FORUMS_PAGE: string = 'FollowForumsPage';
  /** 帖子详情页 */
  static readonly ROUTE_THREAD_PAGE: string = 'ThreadPage';
  /** 收藏帖列表页 */
  static readonly ROUTE_THREAD_STORE_PAGE: string = 'ThreadStorePage';
  /** 楼中楼子帖页 */
  static readonly ROUTE_SUB_POSTS_PAGE: string = 'SubPostsPage';
  /** 关注/粉丝列表页 */
  static readonly ROUTE_FOLLOWS_PAGE: string = 'FollowsPage';
  /** 搜索页 */
  static readonly ROUTE_SEARCH_PAGE: string = 'SearchPage';
  /** 用户主页 */
  static readonly ROUTE_USER_PROFILE_PAGE: string = 'UserProfilePage';
  /** 设置页 */
  static readonly ROUTE_SETTINGS_PAGE: string = 'SettingsPage';
  /** 主题选择页 */
  static readonly ROUTE_THEME_PAGE: string = 'ThemePage';
  /** 关于页 */
  static readonly ROUTE_ABOUT_PAGE: string = 'AboutPage';
  /** 图片查看器页 */
  static readonly ROUTE_IMAGE_VIEWER_PAGE: string = 'ImageViewerPage';
  /** 话题详情页 */
  static readonly ROUTE_TOPIC_DETAIL_PAGE: string = 'TopicDetailPage';

  // ========== 全局 NavPathStack 管理 ==========
  /**
   * 全局 NavPathStack 实例
   * Index.ets 创建 Navigation 容器时通过 setStack 注册，全局共享
   * 未注册前为空 NavPathStack（调用跳转方法不会产生效果）
   */
  private static pathStack: NavPathStack = new NavPathStack();

  /**
   * 获取全局 NavPathStack
   * 用于在 NavDestination 页面中通过 context.pathStack 获取栈实例
   * @returns 全局 NavPathStack
   */
  static getStack(): NavPathStack {
    return RouterUtil.pathStack;
  }

  /**
   * 设置全局 NavPathStack
   * Index.ets 创建 Navigation 容器时调用，将组件内的 NavPathStack 注册到全局
   * @param stack Index.ets 的 NavPathStack 实例
   */
  static setStack(stack: NavPathStack): void {
    RouterUtil.pathStack = stack;
  }

  // ========== 跳转封装方法（替代 router.pushUrl/replaceUrl/back） ==========

  /**
   * push 跳转（对应 router.pushUrl）
   * 将目标页面推入导航栈，保留当前页面在栈底
   * @param name 路由常量（如 RouterUtil.ROUTE_SETTINGS_PAGE）
   * @param params 跳转参数，目标页面通过 NavDestinationContext.pathInfo.param 接收
   *               无参数时传空字符串（pushPathByName 的 param 为必填）
   */
  static push(name: string, params: Object = ''): void {
    try {
      RouterUtil.pathStack.pushPathByName(name, params);
    } catch (err) {
      console.error(`[RouterUtil] push ${name} failed: ${(err as Error).message || err}`);
    }
  }

  /**
   * #132 push 跳转 + 共享元素转场动画
   * 用 animateTo 包裹 pushPathByName(name, params, false)：
   * - false 禁用系统默认转场动画，由 geometryTransition 接管
   * - animateTo 提供动画驱动，源端/目标端 geometryTransition 匹配后自动播放转场
   *
   * 调用方需在源端 Image 绑定 .geometryTransition(shareId, { follow: true }) + .transition()
   * 目标页需在目标端 Image 绑定 .geometryTransition(shareId) + .clip(true) + .transition()
   * 目标页需在 onBackPressed 中调用 RouterUtil.backWithTransition() 返回
   *
   * 参考：华为开发者论坛 NavDestination geometryTransition 官方方案
   * https://developer.huawei.com/consumer/cn/forum/topic/0202205776568320297
   *
   * @param name 路由常量
   * @param params 跳转参数（需包含 shareId 字段供目标页读取）
   * @param uiContext 调用方 UIContext（组件销毁后可能为 undefined）
   */
  static pushWithTransition(name: string, params: Object,
    uiContext: UIContext | undefined): void {
    if (uiContext === undefined) {
      // 组件已销毁，降级为普通 push（无转场动画）
      RouterUtil.push(name, params);
      return;
    }
    try {
      uiContext.animateTo({
        duration: 350,
        curve: Curve.Friction
      }, () => {
        // false 禁用系统默认转场，由 geometryTransition 接管
        RouterUtil.pathStack.pushPathByName(name, params, false);
      });
    } catch (err) {
      console.error(`[RouterUtil] pushWithTransition ${name} failed: ${(err as Error).message || err}`);
    }
  }

  /**
   * #132 返回 + 共享元素转场动画
   * 用 animateTo 包裹 pop(false)：
   * - false 禁用系统默认返回动画，由 geometryTransition 接管逆向转场
   * 目标页 onBackPressed 中调用此方法返回
   *
   * @param uiContext 调用方 UIContext（组件销毁后可能为 undefined）
   */
  static backWithTransition(uiContext: UIContext | undefined): void {
    if (uiContext === undefined) {
      RouterUtil.back();
      return;
    }
    try {
      uiContext.animateTo({
        duration: 350,
        curve: Curve.Friction
      }, () => {
        RouterUtil.pathStack.pop(false);
      });
    } catch (err) {
      console.error(`[RouterUtil] backWithTransition failed: ${(err as Error).message || err}`);
    }
  }

  /**
   * replace 跳转（对应 router.replaceUrl）
   * 用目标页面替换当前栈顶页面，不保留当前页面
   * #173 空栈时 replacePathByName 行为未定义（无栈顶可替换），
   * 改用 pushPathByName 将目标页面推入栈底，保证首次跳转生效
   * @param name 路由常量
   * @param params 跳转参数（无参数时可省略，默认空字符串）
   */
  static replace(name: string, params: Object = ''): void {
    try {
      if (RouterUtil.pathStack.size() === 0) {
        RouterUtil.pathStack.pushPathByName(name, params);
      } else {
        RouterUtil.pathStack.replacePathByName(name, params);
      }
    } catch (err) {
      console.error(`[RouterUtil] replace ${name} failed: ${(err as Error).message || err}`);
    }
  }

  /**
   * 返回上一页（对应 router.back）
   * @param count 返回层数，默认 1（仅退一层）
   */
  static back(count: number = 1): void {
    try {
      RouterUtil.pathStack.pop(count);
    } catch (err) {
      console.error(`[RouterUtil] back failed: ${(err as Error).message || err}`);
    }
  }

  /**
   * 返回到指定页面
   * 从栈顶依次 pop，直到名为 name 的页面成为栈顶
   * @param name 目标页面路由常量
   */
  static backTo(name: string): void {
    try {
      RouterUtil.pathStack.popToName(name);
    } catch (err) {
      console.error(`[RouterUtil] backTo ${name} failed: ${(err as Error).message || err}`);
    }
  }

  /**
   * 返回到栈底（首页）
   * 清空导航栈除栈底外的所有页面
   */
  static backToRoot(): void {
    try {
      RouterUtil.pathStack.clear();
    } catch (err) {
      console.error(`[RouterUtil] backToRoot failed: ${(err as Error).message || err}`);
    }
  }

  /**
   * 获取当前导航栈大小
   * @returns 栈中页面数量
   */
  static size(): number {
    return RouterUtil.pathStack.size();
  }

  /**
   * 获取栈顶页面的路由名
   * @returns 栈顶页面路由名，栈空时返回空字符串
   */
  static topName(): string {
    const pathStack: NavPathStack = RouterUtil.pathStack;
    if (pathStack.size() === 0) {
      return '';
    }
    // NavPathStack 没有直接的 topName API，通过 getAllPathName 取最后一项
    const names: string[] = pathStack.getAllPathName();
    if (names.length === 0) {
      return '';
    }
    return names[names.length - 1];
  }
}
