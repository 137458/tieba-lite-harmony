// 收藏页占位（issue #16）
// TabBar 收藏 tab，后续迭代接入收藏 API

import { PagePlaceholder } from '../../components/PagePlaceholder';

@Component
export struct FavoritePage {
  build() {
    Column() {
      PagePlaceholder({ pageTitle: $r('app.string.favorite_page_title') })
    }
    .width('100%')
    .height('100%')
  }
}
