// 我的页占位（issue #16）
// TabBar 我的 tab，后续迭代接入个人信息+设置+退出登录

import { PagePlaceholder } from '../../components/PagePlaceholder';

@Component
export struct ProfilePage {
  build() {
    Column() {
      PagePlaceholder({ pageTitle: $r('app.string.profile_page_title') })
    }
    .width('100%')
    .height('100%')
  }
}
