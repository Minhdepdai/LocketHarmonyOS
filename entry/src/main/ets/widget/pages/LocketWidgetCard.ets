const locketWidgetStorage = new LocalStorage();

@Entry(locketWidgetStorage)
@Component
struct LocketWidgetCard {
  @LocalStorageProp('imgName') imgName: string = '';
  @LocalStorageProp('hasImage') hasImage: boolean = false;
  @LocalStorageProp('caption') caption: string = '';
  @LocalStorageProp('senderName') senderName: string = '';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('unseenCount') unseenCount: number = 0;

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.hasData && this.hasImage && this.imgName.length > 0) {
        Image(`memory://${this.imgName}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)

        // Subtle bottom gradient scrim for caption/sender legibility
        Column()
          .width('100%')
          .height('52%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [['#00000000', 0.0], ['#BF000000', 1.0]]
          })

        // Bottom-start caption & sender pills
        Column({ space: 4 }) {
          if (this.caption.length > 0) {
            Text(this.caption)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .backgroundColor('#99000000')
              .border({ width: 0.5, color: '#33FFFFFF' })
              .borderRadius(12)
          }
          if (this.senderName.length > 0) {
            Text(this.senderName)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFB800')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('#B3000000')
              .border({ width: 0.5, color: '#4DFFB800' })
              .borderRadius(10)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(10)

        // Top-right golden unseen count badge
        if (this.unseenCount > 0) {
          Row() {
            Row() {
              Text(this.unseenCount > 99 ? '99+' : `${this.unseenCount}`)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#000000')
            }
            .constraintSize({ minWidth: 24 })
            .height(22)
            .padding({ left: 7, right: 7 })
            .borderRadius(11)
            .backgroundColor('#FFB800')
            .shadow({ radius: 8, color: '#66000000', offsetX: 0, offsetY: 2 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .height('100%')
          .alignItems(VerticalAlign.Top)
          .justifyContent(FlexAlign.End)
          .padding({ top: 10, right: 10 })
        }
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
    .clip(true)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          source: 'widget',
          viewMode: 'feed'
        }
      });
    })
  }
}
