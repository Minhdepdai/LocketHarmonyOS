# LocketHarmonyOS

Ứng dụng **Locket** viết bằng **ArkTS (Stage Model)** cho **HarmonyOS NEXT (API 12+)**, kết nối trực tiếp tới hệ thống API gốc của Locket (Firebase Auth, Firestore REST, Firebase Storage, `api.locketcamera.com`) mà không cần máy chủ trung gian.

## Tính năng chính

- **Đăng nhập 3 bước & Quản lý phiên (`LoginPage`):** Luồng đăng nhập 3 bước (màn hình chào mừng, nhập email, nhập mật khẩu) qua Firebase Auth, lưu phiên bền vững bằng `@kit.ArkData` (`preferences`) và tự động làm mới `idToken` khi gần hết hạn.
- **Màn hình chính 3 chế độ (`HomePage`):** Chuyển đổi mượt mà giữa 3 chế độ: **Camera** (chụp/chọn ảnh nhanh), **Vertical Feed** (vuốt dọc xem khoảnh khắc `1:1`, thả cảm xúc nhanh `reactToMoment`, trả lời nhanh `sendChatMessageV2`, tự động đánh dấu đã xem `markMomentAsViewed`, xóa khoảnh khắc `deleteMomentV2`), và **3-Column History Grid** (lưới lịch sử 3 cột).
- **Camera & Đăng ảnh (`CameraPage`):** Chụp ảnh hoặc chọn ảnh từ thư viện, nhập caption, tải lên Firebase Storage và đăng khoảnh khắc trực tiếp tới bạn bè (`postMomentV2`).
- **Nhắn tin 1-1 (`ChatPage`):** Trò chuyện trực tiếp với từng người bạn qua `sendChatMessageV2` và đồng bộ hội thoại.
- **Quản lý bạn bè (`FriendsPage`):** Hiển thị danh sách bạn bè (Firestore + `fetchUserV2`), lọc feed theo từng người bạn, tìm và gửi lời mời kết bạn bằng invite token (`fetchUserForInviteToken`, `sendFriendRequest`), cũng như hủy kết bạn (`removeFriend`).
- **Hồ sơ cá nhân & Cài đặt (`ProfilePage`):** Xem thông tin tài khoản, ảnh đại diện, quản lý liên kết/tùy chọn cá nhân và đăng xuất an toàn.
- **Widget màn hình chính (`FormKit`):** Thẻ dịch vụ `LocketWidget` (`2×2` và `2×4`) thông qua `LocketFormAbility` và `LocketWidgetCard` hiển thị khoảnh khắc mới nhất ngay trên màn hình chính HarmonyOS.

## Cấu trúc thư mục

```text
LocketHarmonyOS/
├── AppScope/
│   ├── app.json5
│   └── resources/base/
│       ├── element/string.json
│       └── media/app_icon.png
├── docs/
│   └── API_SPEC.md
├── entry/
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   ├── oh-package.json5
│   └── src/main/
│       ├── module.json5
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets
│       │   ├── models/LocketModels.ets
│       │   ├── services/
│       │   │   ├── LocketApiClient.ets
│       │   │   └── SessionManager.ets
│       │   ├── pages/
│       │   │   ├── Index.ets
│       │   │   ├── LoginPage.ets
│       │   │   ├── HomePage.ets
│       │   │   ├── FriendsPage.ets
│       │   │   ├── CameraPage.ets
│       │   │   ├── ChatPage.ets
│       │   │   └── ProfilePage.ets
│       │   └── widget/
│       │       ├── LocketFormAbility.ets
│       │       └── pages/LocketWidgetCard.ets
│       └── resources/base/
│           ├── element/
│           │   ├── color.json
│           │   └── string.json
│           ├── media/
│           │   ├── background.png
│           │   ├── foreground.png
│           │   ├── layered_image.json
│           │   └── startIcon.png
│           └── profile/
│               ├── form_config.json
│               └── main_pages.json
├── hvigor/
│   └── hvigor-config.json5
├── scripts/
│   └── verify_project.py
├── build-profile.json5
├── hvigorfile.ts
├── oh-package.json5
└── README.md
```

## Cài đặt & Chạy trên DevEco Studio

1. Cài đặt **DevEco Studio** phiên bản hỗ trợ **HarmonyOS NEXT (API 12+ / Model 5.0.0)**.
2. Mở trực tiếp thư mục gốc `LocketHarmonyOS`. Toàn bộ cấu hình `hvigor`, `module.json5`, `form_config.json` và bộ icon PNG (`app_icon.png`, `startIcon.png`, `layered_image.json`) đã được tạo sẵn.
3. Chọn **Sync Now** (Hvigor Sync) nếu DevEco Studio yêu cầu.
4. Cấu hình chữ ký tự động (**File → Project Structure → Signing Configs → Automatically generate signature**) nếu chạy trên thiết bị thật hoặc Emulator.
5. Chọn thiết bị / Emulator và bấm **Run (`Shift+F10`)**.
6. Để thêm Widget màn hình chính: nhấn giữ biểu tượng ứng dụng Locket trên màn hình chính → chọn **Service widgets** → thêm thẻ `2×2` hoặc `2×4`.

## Kiểm tra tự động cấu hình dự án

Chạy script kiểm tra tính toàn vẹn cấu hình, tài nguyên, trang ArkTS, tệp PNG và bảo mật trước khi build:

```bash
python3 scripts/verify_project.py
```