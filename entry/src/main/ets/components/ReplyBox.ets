import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { TiebaAPI } from '../api/TiebaAPI';
import { getResourceString } from '../utils/ResourceUtil';
import { EmoticonManager, EmoticonInfo } from '../utils/EmoticonManager';
import { AppStorageManager } from '../data/AppStorage';
import { UploadedPicInfo } from '../utils/ImageUploader';
import { connectTheme, ThemeState } from '../theme/ThemeManager';
import { VibratorUtil } from '../utils/VibratorUtil';
import { SoundPoolUtil } from '../utils/SoundPoolUtil';

/**
 * 内嵌回复框组件（替代原 ReplyPage 跳转方案）
 *
 * 通过 bindSheet 半模态弹出，由父组件（ThreadPage / SubPostsPage）触发显示。
 * 接收回复目标参数（tid/fid/forumName + 可选楼中楼参数），
 * 内部管理 content/selectedImages/showEmojiPanel 等本地状态。
 *
 * 实现：
 *   - 文本回复 + 表情面板（#(表情名) 插入）
 *   - 图片上传（选择图片 → 上传至 /c/s/uploadPicture → #(pic,picId,w,h) 嵌入 content）
 *   - 楼中楼回复时 content 自动加前缀 "回复 #(reply, portrait, userName) :"（对齐 ReplyPage.kt:658）
 *   - 调用 TiebaAPI.addPost 发送，成功后通过 onSentSuccess 回调通知父组件
 *   - 表情面板与键盘互斥：点表情按钮主动 clearFocus 收键盘
 *
 * 使用方式（父组件）：
 *   @Local showReplySheet: boolean = false;
 *   @Local replyTarget: ReplyTarget = new ReplyTarget();
 *   @Builder ReplySheetBuilder() {
 *     ReplyBox({
 *       tid: this.replyTarget.tid,
 *       fid: this.replyTarget.fid,
 *       forumName: this.replyTarget.forumName,
 *       postId: this.replyTarget.postId,
 *       subPostId: this.replyTarget.subPostId,
 *       replyUid: this.replyTarget.replyUid,
 *       replyUserName: this.replyTarget.replyUserName,
 *       replyUserPortrait: this.replyTarget.replyUserPortrait,
 *       floor: this.replyTarget.floor,
 *       onSentSuccess: () => { this.showReplySheet = false; },
 *       onClose: () => { this.showReplySheet = false; }
 *     })
 *   }
 *   // 触发：this.replyTarget = ...; this.showReplySheet = true;
 *   // bindSheet($$this.showReplySheet, this.ReplySheetBuilder(), { ... })
 */

/** 回帖内容最大长度（对齐 Android ReplyPage EditText maxLength） */
const MAX_CONTENT_LENGTH: number = 2000;
/** 单次回帖最多图片数（对齐 Android ReplyPage 限制） */
const MAX_IMAGE_COUNT: number = 9;

/**
 * 回复目标参数（父组件统一持有，每次打开 sheet 时新建实例触发 @Local 刷新）
 * 字段含义对齐 ReplyPage 路由参数
 */
export class ReplyTarget {
  tid: number = 0;
  fid: number = 0;
  forumName: string = '';
  postId: number = 0;
  subPostId: number = 0;
  replyUid: number = 0;
  replyUserName: string = '';
  replyUserPortrait: string = '';
  floor: number = 0;
}

@ComponentV2
export struct ReplyBox {
  /** 主题帖 id */
  @Param tid: number = 0;
  /** 贴吧 id */
  @Param fid: number = 0;
  /** 贴吧名 */
  @Param forumName: string = '';
  /** 楼中楼回复参数（postId > 0 即楼中楼场景） */
  @Param postId: number = 0;
  @Param subPostId: number = 0;
  @Param replyUid: number = 0;
  @Param replyUserName: string = '';
  @Param replyUserPortrait: string = '';
  /** 楼层号（仅用于标题显示，目前不在 ReplyBox 内使用） */
  @Param floor: number = 0;

  /** 发送成功回调（父组件用于关闭 sheet 并刷新列表） */
  @Event onSentSuccess?: () => void;
  /** 关闭回调（用户点击关闭/蒙层关闭时触发） */
  @Event onClose?: () => void;

  /** 输入框内容（不含楼中楼前缀，发送时拼前缀） */
  @Local content: string = '';
  /** 是否正在发送 */
  @Local isSending: boolean = false;
  /** 是否显示表情面板 */
  @Local showEmojiPanel: boolean = false;
  /** 当前用户显示名（从 AppStorageManager 读取，用作 name_show） */
  @Local nameShow: string = '';
  /** 表情列表（一次性加载缓存） */
  @Local emoticons: EmoticonInfo[] = [];
  /** 已选图片 uri 数组（photoAccessHelper 返回的 uri） */
  @Local selectedImages: string[] = [];
  /** 图片上传中（含压缩+分块上传全流程） */
  @Local isUploading: boolean = false;
  /** 原图模式开关（true=10MB 阈值不压缩，false=5MB 阈值压缩） */
  @Local isOriginImage: boolean = false;
  @Local themeState: ThemeState = connectTheme();

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear(): Promise<void> {
    this.emoticons = EmoticonManager.getAllEmoticons();
    // 读取当前用户显示名（对齐 TiebaLite AccountUtil.nameShow，HarmonyOS 用 AppStorage 存储）
    try {
      const nickname: string = await AppStorageManager.getInstance().getString('nickname');
      this.nameShow = nickname;
    } catch (err) {
      console.warn(`[ReplyBox] read nickname failed: ${(err as Error).message}`);
    }
    if (this.nameShow.length === 0) {
      this.nameShow = getResourceString($r('app.string.profile_default_name'));
      console.warn('[ReplyBox] nameShow is empty, fallback to default');
    }
  }

  /** 是否为楼中楼回复（postId > 0 即为楼中楼场景） */
  isSubPostReply(): boolean {
    return this.postId > 0;
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
   * 互斥逻辑（#88 键盘避让）：
   *   - 打开表情面板：主动 clearFocus 收起键盘
   *   - 关闭表情面板：主动 requestFocus('replyTextArea') 让 TextArea 获焦，触发键盘自动弹出
   *     之前关闭表情后依赖用户点击 TextArea 才弹键盘，体验不连贯
   */
  toggleEmojiPanel(): void {
    if (!this.showEmojiPanel) {
      // 打开表情前先收起键盘（避免键盘+表情同时显示导致布局异常）
      this.getUIContext().getFocusController().clearFocus();
      this.showEmojiPanel = true;
    } else {
      // 关闭表情面板：主动让 TextArea 获焦，键盘自动弹出
      this.showEmojiPanel = false;
      try {
        this.getUIContext().getFocusController().requestFocus('replyTextArea');
      } catch (err) {
        // 防御：sheet 销毁竞态下 requestFocus 可能抛错
        console.warn(`[ReplyBox] toggleEmojiPanel requestFocus failed: ${(err as Error).message}`);
      }
    }
  }

  /**
   * 选择图片（photoAccessHelper.PhotoViewPicker，免权限）
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
        // 追加到已选列表（spread + 字面量触发 @Local 刷新）
        this.selectedImages = [...this.selectedImages, ...result.photoUris];
      }
    } catch (err) {
      console.warn(`[ReplyBox] pickImages failed: ${(err as Error).message}`);
    }
  }

  /** 移除已选图片 */
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

  /** 切换原图模式 */
  toggleOriginImage(): void {
    this.isOriginImage = !this.isOriginImage;
  }

  /**
   * 拼接图片引用文本
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
   * 校验内容非空 → 上传图片（如有）→ 调 TiebaAPI.addPost → 成功后调 onSentSuccess
   * 失败时弹 Toast 提示，不关闭 sheet（用户可修改后重试，已选图片不清空对齐 Android）
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

    // 有图片时先上传，再拼接 #(pic,picId,w,h) 文本
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
    try {
      const littleTail: string = await AppStorageManager.getInstance().getString('littleTail', '');
      if (littleTail.length > 0 && finalContent.length > 0) {
        finalContent = `${finalContent}\n${littleTail}`;
      }
    } catch (err) {
      console.warn(`[ReplyBox] load littleTail failed: ${(err as Error).message}`);
    }

    // #121 触感反馈：发送回帖属于强调交互，触发重震动
    VibratorUtil.heavy();
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
        // #123 消息提示音：发送成功播放提示音
        SoundPoolUtil.playMessage();
        this.showToast(getResourceString($r('app.string.reply_success')));
        if (this.onSentSuccess) {
          this.onSentSuccess();
        }
      } else {
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
                // A5 图片优化：网络表情图异步加载 + 高质量插值缓解锯齿 + 错误兜底
                .syncLoad(false)
                .interpolation(ImageInterpolation.High)
                .onError(() => {
                  // 表情图加载失败静默处理：alt 占位图会自动显示
                })
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

  /** 已选图片预览面板（横向滚动，每项 72x72 + 删除按钮） */
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
              // A5 图片优化：本地已选图片缩略图同步加载避免闪烁 + 自动降采样减少内存
              .syncLoad(true)
              .interpolation(ImageInterpolation.Medium)
              .autoResize(true)
              .onError((err: ImageError) => {
                console.error(`[ReplyBox] image load failed: uri=${uri}, msg=${err.message}`);
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
      // 已选图片预览（有图时显示在 TextArea 上方）
      if (this.selectedImages.length > 0) {
        this.SelectedImagesPanel()
      }

      // 输入区：TextArea 多行输入
      // 点击 TextArea 时收起表情面板，键盘自动弹出（互斥逻辑）
      // .key('replyTextArea')：bindSheet onAppear 时通过 FocusController.requestFocus('replyTextArea')
      // 主动获焦，触发输入法弹出；onWillDismiss 时 clearFocus 避免焦点残留导致退出后跳回回复框
      TextArea({ text: $$this.content, placeholder: this.buildPlaceholder() })
        .key('replyTextArea')
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
        // 图片选择按钮
        Row() {
          Image($r('app.media.ic_image'))
            .width(24)
            .height(24)
            .fillColor(this.selectedImages.length > 0
              ? this.themeState.primary
              : $r('app.color.text_secondary'))
            // A5 图片优化：本地 SVG 小图同步加载避免闪烁
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
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
              ? this.themeState.primary
              : $r('app.color.text_secondary'))
            // A5 图片优化：本地 SVG 小图同步加载避免闪烁
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
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
        // 原图开关（仅有图时显示）
        if (this.selectedImages.length > 0) {
          Text(getResourceString($r('app.string.reply_origin_image')))
            .fontSize(12)
            .fontColor(this.isOriginImage
              ? this.themeState.primary
              : $r('app.color.text_caption'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(4)
            .border({ width: 0.5, color: this.isOriginImage
              ? this.themeState.primary
              : $r('app.color.divider') })
            .margin({ right: 8 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => this.toggleOriginImage())
        }
        // 发送按钮
        Text(this.isUploading
          ? getResourceString($r('app.string.reply_uploading_image'))
          : (this.isSending
            ? getResourceString($r('app.string.reply_sending'))
            : getResourceString($r('app.string.reply_send'))))
          .fontSize(15)
          .fontWeight(600)
          .fontColor(this.isUploading || this.isSending
            ? $r('app.color.text_caption')
            : this.themeState.primary)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.onSend())
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: { top: 0.5 }, color: $r('app.color.divider') })

      // 表情面板（showEmojiPanel=true 时显示，与键盘互斥）
      if (this.showEmojiPanel) {
        this.EmojiPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
