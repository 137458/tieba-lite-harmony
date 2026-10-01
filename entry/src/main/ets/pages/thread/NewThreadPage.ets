// 发帖页（Phase 4 内容生产）
// 对照 Android NewThreadActivity（标题 + 正文 + 选吧 + 图片 + 发布）
// 协议：TiebaAPI.addThread（/c/c/thread/add 表单）
// 图片：复用 ReplyBox 同款链路——photoAccessHelper.PhotoViewPicker 选图（免权限）
//       → ImageUploader 分块上传 → #(pic,picId,width,height) 标记追加到正文
// 草稿：DraftManager 自动保存（输入防抖 + 离开页面时保存），发布成功后清除

import { HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { TiebaAPI, IAddThreadParams } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { MaterialLevelState, connectMaterialLevel } from '../../model/AppStorageV2Models';
import { ImageUploader, UploadedPicInfo } from '../../utils/ImageUploader';
import { DraftManager, ThreadDraft } from '../../utils/DraftManager';
import { RouterUtil } from '../../utils/RouterUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { EmoticonManager, EmoticonInfo } from '../../utils/EmoticonManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { MATERIAL_TYPE_IMMERSIVE, resolveMaterialLevel } from '../../theme/MaterialUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';

/** 标题最大长度（对齐 Android NewThreadActivity EditText maxLength） */
const TITLE_MAX_LENGTH: number = 100;
/** 正文最大长度 */
const CONTENT_MAX_LENGTH: number = 20000;
/** 单帖最大图片数（对齐 ReplyBox MAX_IMAGE_COUNT） */
const MAX_IMAGE_COUNT: number = 9;
/** 草稿自动保存防抖间隔（毫秒） */
const DRAFT_SAVE_DEBOUNCE_MS: number = 800;

// #163 [A4-S3] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function NewThreadPageBuilder() {
  NewThreadPage()
}

@ComponentV2
export struct NewThreadPage {
  @Local themeState: ThemeState = connectTheme();
  // 沉浸光感材质档位（与全局设置共享，SettingsPage 修改后自动响应）
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  // 滚动器：绑定 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();

  // 表单状态
  @Local selectedForumName: string = '';
  @Local selectedForumId: number = 0;
  @Local title: string = '';
  @Local content: string = '';
  @Local selectedImages: string[] = [];

  // 吧选择半模态
  @Local isForumSheetShow: boolean = false;
  @Local forumList: SelfFollowForum[] = [];
  @Local isForumListLoading: boolean = false;

  // 表情选择半模态（对齐 ReplyBox EmojiPanel 的 #(表情名) 标记约定）
  @Local isEmojiSheetShow: boolean = false;
  @Local emoticons: EmoticonInfo[] = [];

  // 发布流程状态
  @Local isUploading: boolean = false;
  @Local isPublishing: boolean = false;

  private titleController: TextInputController = new TextInputController();
  private isDestroyed: boolean = false;
  private draftSaveTimerId: number = -1;
  /** 发布成功标志：离开页面时不回写草稿 */
  private published: boolean = false;

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  aboutToAppear(): void {
    this.restoreDraft();
    // 表情列表一次性加载缓存（对齐 ReplyBox aboutToAppear）
    this.emoticons = EmoticonManager.getAllEmoticons();
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    this.clearDraftTimer();
    // 发布成功后不回写草稿；有内容且未发布则保存草稿
    if (!this.published && (this.title.length > 0 || this.content.length > 0 || this.selectedForumId > 0)) {
      this.saveDraftNow();
    }
  }

  /** 恢复草稿（aboutToAppear 异步加载） */
  private async restoreDraft(): Promise<void> {
    try {
      const draft: ThreadDraft = await DraftManager.load();
      if (this.isDestroyed) {
        return;
      }
      if (draft.forumId > 0 || draft.title.length > 0 || draft.content.length > 0) {
        this.selectedForumId = draft.forumId;
        this.selectedForumName = draft.forumName;
        this.title = draft.title;
        this.content = draft.content;
        this.showToast(getResourceString($r('app.string.new_thread_draft_restored')));
      }
    } catch (err) {
      console.warn(`[NewThreadPage] restoreDraft failed: ${(err as Error).message}`);
    }
  }

  /** 输入变化：防抖保存草稿 */
  private scheduleDraftSave(): void {
    this.clearDraftTimer();
    this.draftSaveTimerId = setTimeout(() => {
      if (this.isDestroyed) {
        return;
      }
      this.draftSaveTimerId = -1;
      this.saveDraftNow();
    }, DRAFT_SAVE_DEBOUNCE_MS);
  }

  private clearDraftTimer(): void {
    if (this.draftSaveTimerId !== -1) {
      clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
  }

  private saveDraftNow(): void {
    const draft: ThreadDraft = new ThreadDraft();
    draft.forumId = this.selectedForumId;
    draft.forumName = this.selectedForumName;
    draft.title = this.title;
    draft.content = this.content;
    DraftManager.save(draft).catch((err: Error) => {
      console.warn(`[NewThreadPage] saveDraft failed: ${err.message}`);
    });
  }

  /**
   * 打开选吧半模态：拉取关注吧列表（page=1, rn=100，对齐 FollowForumsPage 取全量）
   */
  private async openForumSheet(): Promise<void> {
    this.isForumSheetShow = true;
    if (this.forumList.length > 0) {
      return;
    }
    this.isForumListLoading = true;
    try {
      const pageData = await TiebaAPI.getFollowForums(1, 100);
      if (this.isDestroyed) {
        return;
      }
      this.forumList = pageData.list;
    } catch (err) {
      if (this.isDestroyed) {
        return;
      }
      this.showToast((err as Error).message || getResourceString($r('app.string.new_thread_pick_forum_failed')));
    } finally {
      if (!this.isDestroyed) {
        this.isForumListLoading = false;
      }
    }
  }

  /** 选择吧 */
  private selectForum(forum: SelfFollowForum): void {
    this.selectedForumId = forum.fid;
    this.selectedForumName = forum.fname;
    this.isForumSheetShow = false;
    this.scheduleDraftSave();
  }

  /** 打开表情选择半模态（先收起键盘，避免键盘与半模态叠加） */
  private openEmojiSheet(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.isEmojiSheetShow = true;
  }

  /** 表情点击：#(表情名) 标记追加到正文末尾（对齐 ReplyBox.onEmoticonClick） */
  private insertEmoticon(emoticon: EmoticonInfo): void {
    this.content = this.content + EmoticonManager.buildEmoticonMark(emoticon.name);
    this.scheduleDraftSave();
  }

  /**
   * 选择图片（photoAccessHelper.PhotoViewPicker，免权限，对齐 ReplyBox）
   * 上限 = MAX_IMAGE_COUNT - 已选数量
   */
  async pickImages(): Promise<void> {
    const remainCount: number = MAX_IMAGE_COUNT - this.selectedImages.length;
    if (remainCount <= 0) {
      this.showToast(getResourceString($r('app.string.reply_image_max_reached', MAX_IMAGE_COUNT)));
      return;
    }
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = remainCount;
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris && result.photoUris.length > 0) {
        this.selectedImages = [...this.selectedImages, ...result.photoUris];
      }
    } catch (err) {
      console.warn(`[NewThreadPage] pickImages failed: ${(err as Error).message}`);
    }
  }

  /** 移除已选图片 */
  removeImage(index: number): void {
    if (index < 0 || index >= this.selectedImages.length) {
      return;
    }
    const newList: string[] = [];
    for (let i: number = 0; i < this.selectedImages.length; i++) {
      if (i !== index) {
        newList.push(this.selectedImages[i]);
      }
    }
    this.selectedImages = newList;
  }

  /**
   * 拼接图片引用文本（对齐 ReplyBox.buildImageContent 模板）：
   * #(pic,<picId>,<width>,<height>)，多图 \n 分隔
   */
  private buildImageContent(images: UploadedPicInfo[]): string {
    const lines: string[] = [];
    for (let i: number = 0; i < images.length; i++) {
      const img: UploadedPicInfo = images[i];
      lines.push(`#(pic,${img.picId},${img.width},${img.height})`);
    }
    return lines.join('\n');
  }

  /**
   * 发布：校验 → 上传图片（串行）→ 拼接图片标记 → addThread → 清草稿 → 返回
   */
  async publish(): Promise<void> {
    if (this.isUploading || this.isPublishing) {
      return;
    }
    if (this.selectedForumId <= 0) {
      this.showToast(getResourceString($r('app.string.new_thread_need_forum')));
      return;
    }
    const title: string = this.title.trim();
    const content: string = this.content.trim();
    if (title.length === 0 && content.length === 0 && this.selectedImages.length === 0) {
      this.showToast(getResourceString($r('app.string.new_thread_need_content')));
      return;
    }

    this.isPublishing = true;
    try {
      // 串行上传图片（对齐 ReplyBox：任一张失败整体抛异常，已选图片保留供重试）
      const uploaded: UploadedPicInfo[] = [];
      if (this.selectedImages.length > 0) {
        this.isUploading = true;
        for (let i: number = 0; i < this.selectedImages.length; i++) {
          const info: UploadedPicInfo = await ImageUploader.uploadSinglePicture(
            this.selectedImages[i], this.selectedForumName, false
          );
          uploaded.push(info);
        }
        this.isUploading = false;
      }

      let finalContent: string = content;
      if (uploaded.length > 0) {
        const imgText: string = this.buildImageContent(uploaded);
        finalContent = finalContent.length > 0 ? `${finalContent}\n${imgText}` : imgText;
      }

      // #121 触感反馈：发布属于强调交互，触发重震动（对齐 ReplyBox 发送回帖）
      VibratorUtil.heavy();
      const params: IAddThreadParams = {
        title: title,
        content: finalContent,
        forumId: this.selectedForumId,
        forumName: this.selectedForumName
      };
      await TiebaAPI.addThread(params);
      if (this.isDestroyed) {
        return;
      }
      this.published = true;
      this.title = '';
      this.content = '';
      this.selectedImages = [];
      this.selectedForumId = 0;
      this.selectedForumName = '';
      await DraftManager.clear();
      this.showToast(getResourceString($r('app.string.new_thread_success')));
      RouterUtil.back();
    } catch (err) {
      if (this.isDestroyed) {
        return;
      }
      this.showToast((err as Error).message || getResourceString($r('app.string.new_thread_publish_failed')));
    } finally {
      if (!this.isDestroyed) {
        this.isUploading = false;
        this.isPublishing = false;
      }
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.scroller) {
          Column() {
            // 选吧行
            Row() {
              Text($r('app.string.new_thread_select_forum'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              Text(this.selectedForumName.length > 0
                ? this.selectedForumName
                : $r('app.string.new_thread_select_forum_placeholder'))
                .fontSize(14)
                .fontColor(this.selectedForumName.length > 0
                  ? this.themeState.primary
                  : $r('app.color.text_caption'))
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([$r('app.color.text_caption')])
            }
            .width('100%')
            .padding({ top: 14, bottom: 14, left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .onClick(() => {
              this.openForumSheet().catch((err: Error) => {
                console.error(`[NewThreadPage] openForumSheet failed: ${err.message}`);
              });
            })

            // 标题输入（输入框风格对齐 LoginPage：input_background + text_caption 占位色）
            TextInput({
              text: this.title,
              placeholder: $r('app.string.new_thread_title_hint'),
              controller: this.titleController
            })
              .maxLength(TITLE_MAX_LENGTH)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_caption'))
              .placeholderFont({ size: 16 })
              .backgroundColor($r('app.color.input_background'))
              .borderRadius(10)
              .margin({ top: 12 })
              .onChange((value: string) => {
                this.title = value;
                this.scheduleDraftSave();
              })

            // 正文输入（字号对齐 ReplyBox TextArea 的 15fp）
            TextArea({
              text: this.content,
              placeholder: $r('app.string.new_thread_content_hint')
            })
              .maxLength(CONTENT_MAX_LENGTH)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_caption'))
              .placeholderFont({ size: 15 })
              .backgroundColor($r('app.color.input_background'))
              .borderRadius(10)
              .margin({ top: 12 })
              .height(220)
              .onChange((value: string) => {
                this.content = value;
                this.scheduleDraftSave();
              })

            // 已选图片条（对齐 ReplyBox.SelectedImagesPanel：72x72 缩略图 + 圆形删除角标）
            if (this.selectedImages.length > 0) {
              List({ space: 8 }) {
                ForEach(this.selectedImages, (uri: string, index: number) => {
                  ListItem() {
                    Stack() {
                      Image(uri)
                        .width(72)
                        .height(72)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(6)
                        .backgroundColor($r('app.color.input_background'))
                        .alt($r('app.media.startIcon'))
                        .syncLoad(true)
                        .interpolation(ImageInterpolation.Medium)
                        .autoResize(true)

                      // 右上角删除角标
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
                        .onClick(() => {
                          this.removeImage(index);
                        })
                    }
                    .width(72)
                    .height(72)
                  }
                }, (uri: string, index: number) => `${uri}_${index}`)
              }
              .listDirection(Axis.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(80)
              .padding({ top: 4, bottom: 4 })
              .margin({ top: 12 })
            }

            // 工具行：添加图片 / 表情（图标对齐 ReplyBox 工具栏：24vp SVG + 40vp 点击区，
            // 有已选图片/面板展开时高亮主题色）
            Row({ space: 8 }) {
              Row() {
                Image($r('app.media.ic_image'))
                  .width(24)
                  .height(24)
                  .fillColor(this.selectedImages.length > 0
                    ? this.themeState.primary
                    : $r('app.color.text_secondary'))
                  .syncLoad(true)
                  .interpolation(ImageInterpolation.Low)
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.pickImages().catch((err: Error) => {
                  console.error(`[NewThreadPage] pickImages failed: ${err.message}`);
                });
              })

              Row() {
                Image($r('app.media.ic_emoji'))
                  .width(24)
                  .height(24)
                  .fillColor(this.isEmojiSheetShow
                    ? this.themeState.primary
                    : $r('app.color.text_secondary'))
                  .syncLoad(true)
                  .interpolation(ImageInterpolation.Low)
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.openEmojiSheet();
              })

              Blank()
            }
            .width('100%')
            .margin({ top: 8 })

            // 发布按钮（对齐 LoginPage btn-primary：50vp 高 / 17fp / 600 字重 / 圆角 12）
            Button(this.isPublishing || this.isUploading
              ? $r('app.string.new_thread_publishing')
              : $r('app.string.new_thread_publish'))
              .width('100%')
              .height(50)
              .fontSize(17)
              .fontWeight(600)
              .fontColor(Color.White)
              .backgroundColor(this.themeState.primary)
              .borderRadius(12)
              .margin({ top: 20 })
              .enabled(!this.isPublishing && !this.isUploading)
              .onClick(() => {
                this.publish().catch((err: Error) => {
                  console.error(`[NewThreadPage] publish failed: ${err.message}`);
                });
              })
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor($r('app.color.page_background'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      // 表情选择半模态（绑在内层 Column，与 HdsNavDestination 上的选吧半模态分节点绑定）
      .bindSheet(this.isEmojiSheetShow, this.EmojiSheetBuilder(), {
        height: 320,
        dragBar: true,
        onDisappear: () => {
          this.isEmojiSheetShow = false;
        }
      })
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.new_thread_title')
        }
      },
      style: {
        // 与其他二级页面统一：GRADIENT_BLUR 渐变模糊 + IMMERSIVE 沉浸光感材质
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
        }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下需显式设置，
      // 让 titleBar 内容（标题/返回按钮）避让状态栏
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
    // 选吧半模态
    .bindSheet(this.isForumSheetShow, this.ForumSheetBuilder(), {
      height: 420,
      dragBar: true,
      onDisappear: () => {
        this.isForumSheetShow = false;
      }
    })
  }

  /** 选吧半模态 Builder（关注吧列表） */
  @Builder
  ForumSheetBuilder() {
    Column() {
      Text($r('app.string.new_thread_select_forum'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16, bottom: 8 })

      if (this.isForumListLoading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .margin({ top: 40 })
      } else if (this.forumList.length === 0) {
        Text($r('app.string.new_thread_no_forums'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 40 })
      } else {
        // 行样式对齐 FollowForumsPage：吧头像 + 吧名 + 选中态勾选，inset 分割线
        List() {
          ForEach(this.forumList, (forum: SelfFollowForum) => {
            ListItem() {
              Row() {
                Image(forum.avatar)
                  .width(36)
                  .height(36)
                  .borderRadius(18)
                  .backgroundColor($r('app.color.input_background'))
                  .alt($r('app.media.startIcon'))
                  .objectFit(ImageFit.Cover)
                  .syncLoad(true)
                  .interpolation(ImageInterpolation.Low)
                Text(forum.fname)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 12 })
                Blank()
                if (forum.fid === this.selectedForumId) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16)
                    .fontColor([this.themeState.primary])
                }
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.selectForum(forum);
              })
            }
          }, (forum: SelfFollowForum) => `${forum.fid}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        // inset 分割线从吧头像右侧开始（16 + 36 + 12 = 64）
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 64, endMargin: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_background'))
  }

  /**
   * 表情选择半模态 Builder（对齐 ReplyBox.EmojiPanel：8 列 Grid + Scroll 滚动）
   * 点击表情追加标记后不关闭面板，支持连续插入；下滑/点蒙层关闭
   */
  @Builder
  EmojiSheetBuilder() {
    Column() {
      Text($r('app.string.new_thread_emoji_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16, bottom: 8 })

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
                  .syncLoad(false)
                  .interpolation(ImageInterpolation.High)
              }
              .width('100%')
              .aspectRatio(1)
              .justifyContent(FlexAlign.Center)
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.insertEmoticon(emoticon);
              })
            }
          }, (emoticon: EmoticonInfo, idx: number) => `${emoticon.id}_${idx}`)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(4)
        .width('100%')
        .padding(12)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_background'))
  }
}
