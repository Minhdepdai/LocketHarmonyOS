const locketWidgetStorage = new LocalStorage();

@Entry(locketWidgetStorage)
@Component
struct LocketWidgetCard {
  @LocalStorageProp('thumbnailUrl') thumbnailUrl: string = '';
  @LocalStorageProp('caption') caption: string = '';
  @LocalStorageProp('senderName') senderName: string = '';
  @LocalStorageProp('hasData') hasData: boolean = false;

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.hasData && this.thumbnailUrl.length > 0) {
        Image(this.thumbnailUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)

        Column({ space: 4 }) {
          if (this.caption.length > 0) {
            Text(this.caption)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('#B3000000')
              .borderRadius(10)
          }
          if (this.senderName.length > 0) {
            Text(this.senderName)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFB800')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor('#99000000')
              .borderRadius(8)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(10)
      } else {
        Column({ space: 6 }) {
          Text('Locket')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFB800')
          Text('Chạm để xem khoảnh khắc mới nhất')
            .fontSize(11)
            .fontColor('#8E8E93')
            .textAlign(TextAlign.Center)
            .padding({ left: 10, right: 10 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#1C1C1E')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0D0D0F')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {}
      });
    })
  }
}
