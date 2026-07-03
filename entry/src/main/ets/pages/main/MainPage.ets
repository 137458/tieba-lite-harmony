import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { MessagePage } from './MessagePage';
import { ProfilePage } from './ProfilePage';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;

  @Builder
  tabBuilder(text: ResourceStr, index: number, iconRes: Resource) {
    Column() {
      Image(iconRes)
        .width(22)
        .height(22)
        .fillColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
      Text(text)
        .fontSize(10)
        .fontColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .margin({ top: 1 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.currentIndex = index;
    })
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_home'), 0, $r('app.media.ic_home')))

        TabContent() {
          FavoritePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_favorite'), 1, $r('app.media.ic_favorite')))

        TabContent() {
          MessagePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_message'), 2, $r('app.media.ic_message')))

        TabContent() {
          ProfilePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_profile'), 3, $r('app.media.ic_profile')))
      }
      .barHeight(49)
      .barMode(BarMode.Fixed)
      .vertical(false)
      .scrollable(false)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
