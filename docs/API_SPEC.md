# Locket HarmonyOS — Verified Original API Spec

Tài liệu các endpoint gốc của Locket đã được kiểm thử thực tế (`200 OK`) và tích hợp trong `LocketApiClient.ets`, kết nối trực tiếp không qua web proxy trung gian.

## 1. Common iOS Headers

```http
Content-Type: application/json
Accept: application/json
Accept-Language: en-US
X-Ios-Bundle-Identifier: com.locket.Locket
User-Agent: FirebaseAuth.iOS/10.23.1 com.locket.Locket/2.8.0 iPhone/18.0 hw/iPhone12_1
X-Client-Version: iOS/FirebaseSDK/10.23.1/FirebaseCore-iOS
X-Firebase-GMPID: 1:641029076083:ios:cc8eb46290d69b234fa606
```

Các request cần đăng nhập thêm header:
```http
Authorization: Bearer <idToken>
```

---

## 2. Authentication (Firebase IdentityToolkit & SecureToken)

### Login
- **POST** `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=<FIREBASE_API_KEY>`
- **Body:**
```json
{
  "email": "user@example.com",
  "password": "your_password",
  "returnSecureToken": true
}
```
- **Response `200`:**
  - `localId` (UID), `email`, `displayName`, `idToken`, `refreshToken`, `expiresIn`, `profilePicture`

### Refresh Token
- **POST** `https://securetoken.googleapis.com/v1/token?key=<FIREBASE_API_KEY>`
- **Content-Type:** `application/x-www-form-urlencoded`
- **Body:** `grant_type=refresh_token&refresh_token=<refreshToken>`
- **Response `200`:** `id_token`, `refresh_token`, `user_id`, `expires_in`

---

## 3. User Profile (`fetchUserV2`)

- **POST** `https://api.locketcamera.com/fetchUserV2`
- **Body:**
```json
{
  "data": {
    "user_uid": "<uid>"
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "data": {
      "uid": "...",
      "first_name": "...",
      "last_name": "...",
      "username": "...",
      "profile_picture_url": "https://firebasestorage.googleapis.com/...",
      "badge": null
    }
  }
}
```

---

## 4. Friends List & Management

### List Friends (Firestore REST)
- **GET** `https://firestore.googleapis.com/v1/projects/locket-4252a/databases/(default)/documents/users/{uid}/friends?pageSize=100`
- **Response `200`:**
```json
{
  "documents": [
    {
      "fields": {
        "user": { "stringValue": "<friend_uid>" }
      }
    }
  ],
  "nextPageToken": "..."
}
```
> Sau khi lấy danh sách `friend_uid`, gọi `fetchUserV2` cho từng UID để lấy tên, username và avatar.

### Lookup User by Invite Token (`fetchUserForInviteToken`)
- **POST** `https://api.locketcamera.com/fetchUserForInviteToken`
- **Body:**
```json
{
  "data": {
    "invite_token": "<invite_token_or_username>"
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "data": {
      "uid": "<target_uid>",
      "first_name": "...",
      "last_name": "...",
      "username": "...",
      "profile_picture_url": "https://firebasestorage.googleapis.com/..."
    }
  }
}
```

### Send Friend Request (`sendFriendRequest`)
- **POST** `https://api.locketcamera.com/sendFriendRequest`
- **Body:**
```json
{
  "data": {
    "user_uid": "<target_uid>",
    "source": "invite_link"
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "status": 200
  }
}
```

### Remove Friend (`removeFriend`)
- **POST** `https://api.locketcamera.com/removeFriend`
- **Body:**
```json
{
  "data": {
    "user_uid": "<friend_uid>"
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "status": 200
  }
}
```

---

## 5. Moments Feed (`getLatestMomentV2`)

- **POST** `https://api.locketcamera.com/getLatestMomentV2`
- **Body:**
```json
{
  "data": {
    "excluded_users": [],
    "last_fetch": 1,
    "should_count_missed_moments": true
  }
}
```
*(Có thể truyền thêm `"sync_token": "<canonical_uid>"` để phân trang hoặc `"user_uid"` nếu lọc theo bạn bè)*
- **Response `200`:**
```json
{
  "result": {
    "status": 200,
    "missed_moments_count": 0,
    "sync_token": "...",
    "data": [
      {
        "canonical_uid": "...",
        "user": "<sender_uid>",
        "thumbnail_url": "https://firebasestorage.googleapis.com/...",
        "video_url": null,
        "caption": "...",
        "date": { "_seconds": 1795344405, "_nanoseconds": 563000000 },
        "overlays": [],
        "md5": "..."
      }
    ]
  }
}
```

---

## 6. Moment Interactions

### React to Moment (`reactToMoment`)
- **POST** `https://api.locketcamera.com/reactToMoment`
- **Body:**
```json
{
  "data": {
    "moment_uid": "<canonical_uid>",
    "reaction": "❤️",
    "intensity": 0
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "status": 200
  }
}
```

### Mark Moment as Viewed (`markMomentAsViewed`)
- **POST** `https://api.locketcamera.com/markMomentAsViewed`
- **Body:**
```json
{
  "data": {
    "moment_uid": "<canonical_uid>"
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "status": 200
  }
}
```

### Delete Moment (`deleteMomentV2`)
- **POST** `https://api.locketcamera.com/deleteMomentV2`
- **Body:**
```json
{
  "data": {
    "moment_uid": "<canonical_uid>",
    "owner_uid": "<current_user_uid>"
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "status": 200
  }
}
```

---

## 7. Chat & Quick Reply (`sendChatMessageV2`)

- **POST** `https://api.locketcamera.com/sendChatMessageV2`
- **Body:**
```json
{
  "data": {
    "receiver_uid": "<friend_uid>",
    "msg": "Ảnh đẹp quá!",
    "moment_uid": "<optional_canonical_uid>",
    "client_token": "<uuid>"
  }
}
```
> Khi trả lời trực tiếp trên một khoảnh khắc (Quick Reply), truyền kèm `moment_uid`. Khi nhắn tin 1-1 thông thường trong `ChatPage`, `moment_uid` có thể bỏ qua hoặc để `null`.
- **Response `200`:**
```json
{
  "result": {
    "status": 200,
    "data": {
      "uid": "<message_uid>"
    }
  }
}
```

---

## 8. Upload Photo & Post Moment (`Firebase Storage` + `postMomentV2`)

Quy trình đăng khoảnh khắc mới gồm 3 bước:

### Bước 1: Khởi tạo phiên upload ảnh lên Firebase Storage
- **POST** `https://firebasestorage.googleapis.com/v0/b/locket-img/o/users%2F{uid}%2Fmoments%2Fthumbnails%2F{filename}.webp?uploadType=resumable&name=users%2F{uid}%2Fmoments%2Fthumbnails%2F{filename}.webp`
- **Headers:**
```http
Authorization: Firebase <idToken>
Content-Type: application/json; charset=UTF-8
X-Upload-Content-Type: image/webp
X-Upload-Content-Length: <byte_length>
```
- **Body:**
```json
{
  "name": "users/{uid}/moments/thumbnails/{filename}.webp",
  "contentType": "image/webp",
  "bucket": "",
  "metadata": {
    "creator": "<uid>",
    "visibility": "private"
  }
}
```
- **Response `200`:** Trả về header `X-Goog-Upload-URL` (đường dẫn upload dữ liệu nhị phân).

### Bước 2: Tải dữ liệu ảnh (PUT) & Lấy Download URL
- **PUT** `<X-Goog-Upload-URL>` với raw binary bytes của ảnh (`image/webp` hoặc `image/jpeg`).
- **Response `200`:** Trả về JSON chứa `downloadTokens` (hoặc gọi `GET` metadata đối tượng để lấy token).
- Tạo URL tải ảnh:
  `https://firebasestorage.googleapis.com/v0/b/locket-img/o/users%2F{uid}%2Fmoments%2Fthumbnails%2F{filename}.webp?alt=media&token=<downloadToken>`

### Bước 3: Gửi Moment (`postMomentV2`)
- **POST** `https://api.locketcamera.com/postMomentV2`
- **Body:**
```json
{
  "data": {
    "thumbnail_url": "<firebase_download_url>",
    "caption": "Hello from HarmonyOS!",
    "sent_to_all": true,
    "recipients": [],
    "overlays": [],
    "show_personally": false,
    "analytics": {
      "platform": "ios"
    }
  }
}
```
- **Response `200`:**
```json
{
  "result": {
    "status": 200,
    "data": {
      "canonical_uid": "<new_moment_uid>"
    }
  }
}
```
