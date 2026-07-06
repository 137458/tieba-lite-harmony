import { router } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { EmoticonManager, EmoticonInfo } from '../../utils/EmoticonManager';
import { AppStorageManager } from '../../data/AppStorage';
import { UploadedPicInfo } from '../../utils/ImageUploader';

/**
 * #74 回帖页面
 *
 * 路由参数（router.pushUrl params）：
 *   - tid:                number  必需，主题帖 id
 *   - fid:                number  必需，贴吧 id
 *   - forumName:          string  必需，贴吧名（kw）
 *   - postId?:            number  可选，楼中楼回复时传被回复楼层 pid（普通回帖不传）
 *   - subPostId?:         number  可选，楼中楼的楼中楼时传 spid
 *   - replyUid?:          number  可选，楼中楼时传被回复者 uid
 *   - replyUserName?:     string  可选，楼中楼时传被回复者名称（用于 content 前缀）
 *   - replyUserPortrait?: string  可选，楼中楼时传被回复者 portrait（用于 content 前缀）
 *   - floor?:             number  可选，楼中楼楼层号（用于标题显示）
 *
 * 实现：
 *   - 文本回帖 + 表情面板（#(表情名) 插入）
 *   - 图片上传（#74）：选择图片 → 上传至 /c/s/uploadPicture → #(pic,picId,w,h) 嵌入 content
 *   - 楼中楼回复时 content 自动加前缀 "回复 #(reply, portrait, userName) :"（对齐 ReplyPage.kt:658）
 *   - 调用 TiebaAPI.addPost 发送，成功后 router.back()
 */

/** 回帖内容最大长度（对齐 Android ReplyPage EditText maxLength） */
const MAX_CONTENT_LENGTH: number = 2000;
/** #74 单次回帖最多图片数（对齐 Android ReplyPage 限制） */
const MAX_IMAGE_COUNT: number = 9;

/** ReplyPage 路由参数（tid/fid/forumName 必需，其余可选用于楼中楼回复） */
interface ReplyPageParams {
  tid?: number;
  fid?: number;
  forumName?: string;
  postId?: number;
  subPostId?: number;
  replyUid?: number;
  replyUserName?: string;
  replyUserPortrait?: string;
  floor?: number;
}

@Entry
@Component
struct ReplyPage {
  /** 主题帖 id */
  @State tid: number = 0;
  /** 贴吧 id */
  @State fid: number = 0;
  /** 贴吧名 */
  @State forumName: string = '';
  /** 楼中楼回复参数 */
  @State postId: number = 0;
  @State subPostId: number = 0;
  @State replyUid: number = 0;
  @State replyUserName: string = '';
  @State replyUserPortrait: string = '';
  /** 楼层号（仅用于标题显示） */
  @State floor: number = 0;

  /** 输入框内容（不含楼中楼前缀，发送时拼前缀） */
  @State content: string = '';
  /** 是否正在发送 */
  @State isSending: boolean = false;
  /** 是否显示表情面板 */
  @State showEmojiPanel: boolean = false;
  /** 状态栏高度 */
  @State statusBarHeight: number = 36;
  /** 当前用户显示名（从 AppStorageManager 读取，用作 name_show） */
  @State nameShow: string = '';
  /** 表情列表（一次性加载缓存） */
  @State emoticons: EmoticonInfo[] = [];
  /** #74 已选图片 uri 数组（photoAccessHelper 返回的 uri） */
  @State selectedImages: string[] = [];
  /** #74 图片上传中（含压缩+分块上传全流程） */
  @State isUploading: boolean = false;
  /** #74 原图模式开关（true=10MB 阈值不压缩，false=5MB 阈值压缩） */
  @State isOriginImage: boolean = false;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear(): Promise<void> {
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.warn(`[ReplyPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    this.emoticons = EmoticonManager.getAllEmoticons();

    // 读取路由参数
    const params = router.getParams() as ReplyPageParams;
    if (params !== null && params !== undefined) {
      const tidVal = params.tid;
      if (typeof tidVal === 'number') {
        this.tid = tidVal;
      }
      const fidVal = params.fid;
      if (typeof fidVal === 'number') {
        this.fid = fidVal;
      }
      const forumNameVal = params.forumName;
      if (typeof forumNameVal === 'string') {
        this.forumName = forumNameVal;
      }
      const postIdVal = params.postId;
      if (typeof postIdVal === 'number') {
        this.postId = postIdVal;
      }
      const subPostIdVal = params.subPostId;
      if (typeof subPostIdVal === 'number') {
        this.subPostId = subPostIdVal;
      }
      const replyUidVal = params.replyUid;
      if (typeof replyUidVal === 'number') {
        this.replyUid = replyUidVal;
      }
      const replyUserNameVal = params.replyUserName;
      if (typeof replyUserNameVal === 'string') {
        this.replyUserName = replyUserNameVal;
      }
      const replyUserPortraitVal = params.replyUserPortrait;
      if (typeof replyUserPortraitVal === 'string') {
        this.replyUserPortrait = replyUserPortraitVal;
      }
      const floorVal = params.floor;
      if (typeof floorVal === 'number') {
        this.floor = floorVal;
      }
    }

    // 读取当前用户显示名（对齐 TiebaLite AccountUtil.nameShow，HarmonyOS 用 AppStorage 存储）
    try {
      const nickname: string = await AppStorageManager.getInstance().getString('nickname');
      this.nameShow = nickname;
    } catch (err) {
      console.warn(`[ReplyPage] read nickname failed: ${(err as Error).message}`);
    }
    // nameShow 为空时 fallback 到默认昵称（对齐 TiebaLite AccountUtil.nameShow 默认值）
    // 贴吧 name_show 字段通常要求非空，空值可能导致服务端拒绝或显示异常
    if (this.nameShow.length === 0) {
      this.nameShow = getResourceString($r('app.string.profile_default_name'));
      console.warn('[ReplyPage] nameShow is empty, fallback to default');
    }
  }

  /** 是否为楼中楼回复（postId > 0 即为楼中楼场景） */
  isSubPostReply(): boolean {
    return this.postId > 0;
  }

  /** 顶部标题 */
  buildTitle(): string {
    if (this.isSubPostReply()) {
      return getResourceString($r('app.string.reply_subpost_title'));
    }
    return getResourceString($r('app.string.reply_thread_title'));
  }

  /** placeholder 提示文案 */
  buildPlaceholder(): string {
    if (this.isSubPostReply()) {
      return getResourceString($r('app.string.reply_subpost_placeholder', this.replyUserName));
    }
    return getResourceString($r('app.string.reply_thread_placeholder'));
  }

  /**
   * 构造发送给后端的最终 content
   * 楼中楼回复时自动加前缀 "回复 #(reply, portrait, userName) :"（对齐 ReplyPage.kt:658）
   */
  buildFinalContent(): string {
    if (this.isSubPostReply() && this.replyUserName.length > 0) {
      return `回复 #(reply, ${this.replyUserPortrait}, ${this.replyUserName}) :${this.content}`;
    }
    return this.content;
  }

  /** 表情点击：将 #(表情名) 追加到 content 末尾 */
  onEmoticonClick(emoticon: EmoticonInfo): void {
    const mark: string = EmoticonManager.buildEmoticonMark(emoticon.name);
    this.content = this.content + mark;
  }

  /**
   * 切换表情面板显隐
   * 互斥逻辑：打开表情面板时主动 clearFocus 收起键盘；关闭时由 TextArea 获焦自动弹键盘
   */
  toggleEmojiPanel(): void {
    if (!this.showEmojiPanel) {
      // 打开表情前先收起键盘（避免键盘+表情同时显示导致底部工具栏被遮挡）
      this.getUIContext().getFocusController().clearFocus();
    }
    this.showEmojiPanel = !this.showEmojiPanel;
  }

  /** 取消按钮 */
  onCancel(): void {
    router.back();
  }

  /**
   * #74 选择图片（photoAccessHelper.PhotoViewPicker，免权限）
   * 上限 = MAX_IMAGE_COUNT - 已选数量
   * 选择后追加到 selectedImages（不去重，对齐 Android 行为）
   */
  async pickImages(): Promise<void> {
    const remainCount: number = MAX_IMAGE_COUNT - this.selectedImages.length;
    if (remainCount <= 0) {
      this.showToast(getResourceString($r('app.string.reply_image_max_reached', MAX_IMAGE_COUNT)));
      return;
    }
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = remainCount;
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris && result.photoUris.length > 0) {
        // 追加到已选列表（spread + 字面量触发 @State 刷新）
        this.selectedImages = [...this.selectedImages, ...result.photoUris];
      }
    } catch (err) {
      // 用户取消选择不报错（photoAccessHelper 取消会抛 BusinessError，code 通常为 13900042）
      console.warn(`[ReplyPage] pickImages failed: ${(err as Error).message}`);
    }
  }

  /** #74 移除已选图片 */
  removeImage(index: number): void {
    if (index < 0 || index >= this.selectedImages.length) {
      return;
    }
    const newList: string[] = [];
    for (let i = 0; i < this.selectedImages.length; i++) {
      if (i !== index) {
        newList.push(this.selectedImages[i]);
      }
    }
    this.selectedImages = newList;
  }

  /** #74 切换原图模式 */
  toggleOriginImage(): void {
    this.isOriginImage = !this.isOriginImage;
  }

  /**
   * #74 拼接图片引用文本
   * 模板（对齐 Android ReplyPage.kt:323-344）：
   *   #(pic,<picId>,<width>,<height>)
   * 多图用 \n 分隔
   */
  buildImageContent(images: UploadedPicInfo[]): string {
    const lines: string[] = [];
    for (let i = 0; i < images.length; i++) {
      const img: UploadedPicInfo = images[i];
      lines.push(`#(pic,${img.picId},${img.width},${img.height})`);
    }
    return lines.join('\n');
  }

  /**
   * 发送回帖
   * 校验内容非空 → 上传图片（如有）→ 调 TiebaAPI.addPost → 成功后 router.back()
   * 失败时弹 Toast 提示，不关闭页面（用户可修改后重试，已选图片不清空对齐 Android）
   */
  async onSend(): Promise<void> {
    if (this.isSending || this.isUploading) {
      return;
    }
    const trimmed: string = this.content.trim();
    const hasImages: boolean = this.selectedImages.length > 0;
    if (trimmed.length === 0 && !hasImages) {
      this.showToast(getResourceString($r('app.string.reply_empty_content')));
      return;
    }
    if (this.tid <= 0) {
      this.showToast(getResourceString($r('app.string.reply_invalid_params')));
      return;
    }
    // 普通回帖要求 fid + forumName（楼中楼回复时 fid/forumName 可为空，由 postId 标识）
    if (!this.isSubPostReply() && (this.fid <= 0 || this.forumName.length === 0)) {
      this.showToast(getResourceString($r('app.string.reply_invalid_params')));
      return;
    }

    this.isSending = true;

    // #74 有图片时先上传，再拼接 #(pic,picId,w,h) 文本
    let imageContent: string = '';
    if (hasImages) {
      this.isUploading = true;
      try {
        const uploadedImages: UploadedPicInfo[] = await TiebaAPI.uploadImages(
          this.selectedImages,
          this.forumName,
          this.isOriginImage
        );
        imageContent = this.buildImageContent(uploadedImages);
      } catch (err) {
        const msg: string = (err as Error).message || getResourceString($r('app.string.reply_upload_failed'));
        this.showToast(msg);
        // P1 修复：isUploading 由 finally 统一重置，此处只需重置 isSending 并返回
        this.isSending = false;
        return;
      } finally {
        this.isUploading = false;
      }
    }

    // 拼接最终 content：楼中楼前缀 + 用户输入 + 图片引用（图片引用用 \n 分隔追加到末尾）
    let finalContent: string = this.buildFinalContent();
    if (imageContent.length > 0) {
      finalContent = finalContent.length > 0
        ? `${finalContent}\n${imageContent}`
        : imageContent;
    }

    // 追加"我的小尾巴"（用户在设置页配置，对齐 Android TiebaLite little_tail）
    // 仅当 finalContent 非空且小尾巴非空时追加，避免空回复
    try {
      const littleTail: string = await AppStorageManager.getInstance().getString('littleTail', '');
      if (littleTail.length > 0 && finalContent.length > 0) {
        finalContent = `${finalContent}\n${littleTail}`;
      }
    } catch (err) {
      console.warn(`[ReplyPage] load littleTail failed: ${(err as Error).message}`);
    }

    try {
      const result = await TiebaAPI.addPost({
        content: finalContent,
        tid: this.tid,
        fid: this.fid,
        forumName: this.forumName,
        nameShow: this.nameShow,
        postId: this.postId > 0 ? this.postId : undefined,
        subPostId: this.subPostId > 0 ? this.subPostId : undefined,
        replyUid: this.replyUid > 0 ? this.replyUid : undefined
      });
      if (result.needVcode) {
        this.showToast(getResourceString($r('app.string.reply_need_vcode')));
      } else if (result.pid > 0) {
        this.showToast(getResourceString($r('app.string.reply_success')));
        router.back();
      } else {
        // pid=0 但无 error 抛出，说明响应异常
        this.showToast(getResourceString($r('app.string.reply_unknown_error')));
      }
    } catch (err) {
      const msg: string = (err as Error).message || getResourceString($r('app.string.reply_failed'));
      this.showToast(msg);
    } finally {
      this.isSending = false;
    }
  }

  @Builder
  EmojiPanel() {
    // 表情面板：Scroll 包裹 Grid，支持滚动（58 个表情 8 列约 8 行，超出 280vp 视口）
    Scroll() {
      Grid() {
        ForEach(this.emoticons, (emoticon: EmoticonInfo, idx: number) => {
          GridItem() {
            Column() {
              Image(EmoticonManager.getEmoticonUrl(emoticon.id))
                .width(32)
                .height(32)
                .objectFit(ImageFit.Contain)
                .alt($r('app.media.startIcon'))
                .backgroundColor($r('app.color.input_background'))
                .borderRadius(6)
            }
            .width('100%')
            .aspectRatio(1)
            .justifyContent(FlexAlign.Center)
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.onEmoticonClick(emoticon);
            })
          }
        }, (emoticon: EmoticonInfo, idx: number) => `${emoticon.id}_${idx}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(8)
      .columnsGap(4)
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.card_background'))
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .width('100%')
    .height(280)
    .backgroundColor($r('app.color.card_background'))
  }

  /** #74 已选图片预览面板（横向滚动，每项 72x72 + 删除按钮） */
  @Builder
  SelectedImagesPanel() {
    List({ space: 8 }) {
      ForEach(this.selectedImages, (uri: string, idx: number) => {
        ListItem() {
          Stack() {
            Image(uri)
              .width(72)
              .height(72)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
              .backgroundColor($r('app.color.input_background'))
              .alt($r('app.media.startIcon'))
              // P2 修复：加载失败时记录日志，便于排查 URI 失效（如 PhotoViewPicker 临时权限过期）等问题
              .onError((err: ImageError) => {
                console.error(`[ReplyPage] SelectedImagesPanel image load failed: uri=${uri}, msg=${err.message}`);
              })

            // 右上角删除按钮
            Text('×')
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(700)
              .width(20)
              .height(20)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor($r('app.color.divider'))
              .position({ x: 56, y: -4 })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => this.removeImage(idx))
          }
          .width(72)
          .height(72)
        }
      }, (uri: string, idx: number) => `${uri}_${idx}`)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(80)
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.page_background'))
  }

  build() {
    Column() {
      // 顶部导航栏：取消 / 标题 / 发送
      Row() {
        Text(getResourceString($r('app.string.cancel')))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.onCancel())

        Text(this.buildTitle())
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })

        // 发送按钮：上传中/发送中显示 loading 文案，禁用点击
        Text(this.isUploading
          ? getResourceString($r('app.string.reply_uploading_image'))
          : (this.isSending
            ? getResourceString($r('app.string.reply_sending'))
            : getResourceString($r('app.string.reply_send'))))
          .fontSize(15)
          .fontWeight(600)
          .fontColor(this.isUploading || this.isSending
            ? $r('app.color.text_caption')
            : $r('app.color.primary'))
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.onSend())
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      // #74 已选图片预览（有图时显示在 TextArea 上方）
      if (this.selectedImages.length > 0) {
        this.SelectedImagesPanel()
      }

      // 输入区：TextArea 多行输入
      // 点击 TextArea 时收起表情面板，键盘自动弹出（互斥逻辑）
      TextArea({ text: $$this.content, placeholder: this.buildPlaceholder() })
        .width('100%')
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_caption'))
        .placeholderFont({ size: 15 })
        .backgroundColor($r('app.color.page_background'))
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .maxLength(MAX_CONTENT_LENGTH)
        .showCounter(false)
        .onFocus(() => {
          // TextArea 获焦时收起表情面板，避免键盘+表情同时显示
          if (this.showEmojiPanel) {
            this.showEmojiPanel = false;
          }
        })

      // 底部工具栏：图片按钮 + 表情按钮 + 字数提示 + 原图开关
      Row() {
        // #74 图片选择按钮
        Row() {
          Image($r('app.media.ic_image'))
            .width(24)
            .height(24)
            .fillColor(this.selectedImages.length > 0
              ? $r('app.color.primary')
              : $r('app.color.text_secondary'))
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          // 上传中/发送中禁用选择
          if (!this.isUploading && !this.isSending) {
            this.pickImages();
          }
        })

        // 表情切换按钮
        Row() {
          Image($r('app.media.ic_emoji'))
            .width(24)
            .height(24)
            .fillColor(this.showEmojiPanel
              ? $r('app.color.primary')
              : $r('app.color.text_secondary'))
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => this.toggleEmojiPanel())

        // 字数提示
        Text(`${this.content.length}/${MAX_CONTENT_LENGTH}`)
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ left: 8 })
        Blank()
        // 楼中楼提示标签
        if (this.isSubPostReply() && this.replyUserName.length > 0) {
          Text(getResourceString($r('app.string.reply_to_user_label', this.replyUserName)))
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ right: 8 })
        }
        // #74 原图开关（仅有图时显示）
        if (this.selectedImages.length > 0) {
          Text(getResourceString($r('app.string.reply_origin_image')))
            .fontSize(12)
            .fontColor(this.isOriginImage
              ? $r('app.color.primary')
              : $r('app.color.text_caption'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(4)
            .border({ width: 0.5, color: this.isOriginImage
              ? $r('app.color.primary')
              : $r('app.color.divider') })
            .margin({ right: 8 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => this.toggleOriginImage())
        }
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: { top: 0.5 }, color: $r('app.color.divider') })

      // 表情面板（showEmojiPanel=true 时显示）
      if (this.showEmojiPanel) {
        this.EmojiPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
