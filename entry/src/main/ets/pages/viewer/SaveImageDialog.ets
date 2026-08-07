// 保存图片确认对话框
// 使用 SaveButton 安全组件获取临时授权，无需 WRITE_IMAGEVIDEO 权限
// 对齐 HomePage 删除确认弹窗的交互风格

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getResourceString } from '../../utils/ResourceUtil';

@CustomDialog
export struct SaveImageDialog {
  /** 沙箱临时文件路径 */
  sandboxFilePath: string = '';
  /** 保存结果回调：success=true 表示保存成功，false 表示失败或取消 */
  onSaveResult: (success: boolean) => void = () => {};
  controller: CustomDialogController;

  build() {
    Column() {
      // 标题
      Text(getResourceString($r('app.string.save_image_title')))
        .fontSize(18)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      // 提示消息
      Text(getResourceString($r('app.string.save_image_confirm')))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 24 })

      // 按钮行：取消 + SaveButton
      Row({ space: 12 }) {
        Button(getResourceString($r('app.string.cancel_button')))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.input_background'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
            this.onSaveResult(false);
          })

        SaveButton({
          icon: SaveIconStyle.FULL_FILLED,
          text: SaveDescription.SAVE_IMAGE,
          buttonType: ButtonType.Normal
        })
          .height(40)
          .borderRadius(20)
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            if (result === SaveButtonOnClickResult.SUCCESS) {
              this.doSave();
            }
          })
      }
      .width('100%')
    }
    .padding({ top: 20, bottom: 20, left: 24, right: 24 })
  }

  private async doSave(): Promise<void> {
    if (this.sandboxFilePath.length === 0) {
      return;
    }
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const fileUriStr: string = fileUri.getUriFromPath(this.sandboxFilePath);
      const assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
        photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, fileUriStr);
      await helper.applyChanges(assetChangeRequest);
      this.controller.close();
      this.onSaveResult(true);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error(`[SaveImageDialog] save failed: code=${error.code}, message=${error.message}`);
      this.controller.close();
      this.onSaveResult(false);
    }
  }
}