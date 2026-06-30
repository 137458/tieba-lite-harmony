// 消息页占位（issue #16）
// TabBar 消息 tab，后续迭代接入消息列表 API

import { PagePlaceholder } from '../../components/PagePlaceholder';

@Component
export struct MessagePage {
  build() {
    Column() {
      PagePlaceholder({ pageTitle: $r('app.string.message_page_title') })
    }
    .width('100%')
    .height('100%')
  }
}
