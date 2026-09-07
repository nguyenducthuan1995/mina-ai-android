# MINA AI - TÀI LIỆU KIẾN TRÚC & LỘ TRÌNH PHÁT TRIỂN HỆ THỐNG
## (Dành riêng cho Màn hình Ô tô & Cộng đồng Kiều bào tại Đức / Châu Âu)

> **Mục tiêu:** Xây dựng Mina AI thành trợ lý giọng nói trên ô tô số 1 cho người Việt tại Đức và Châu Âu, vượt trội hoàn toàn so với các giải pháp hiện có (Lily AI, Kiki...) nhờ tính năng bản địa hóa độc quyền, tích hợp Google Maps thực tế, và bản tin săn khuyến mãi siêu thị Đức tự động.

---

## I. NHỮNG LỢI THẾ ĐỘC QUYỀN (VƯỢT TRỘI SO VỚI LILY AI)

| Hạng mục | Lily AI (SensorNotes) | Mina AI (Hệ thống của chúng ta) |
| :--- | :--- | :--- |
| **Thị trường cốt lõi** | Nội địa Việt Nam | 🇩🇪 **Bản địa hóa đặc quyền cho người Việt tại Đức & EU** |
| **Bản đồ & Chỉ đường** | Vietmap / Navitel (chỉ dùng ở VN) | 🗺️ **Google Maps chính hãng:** Báo tắc đường (Stau) chuẩn xác trên Autobahn, hiển thị làn đường Đức |
| **Tiện ích xe hơi tại Đức** | Chỉ tra cứu phạt nguội công an VN | ⛽ **Giá xăng Đức thời gian thực (Tankerkönig API):** Tìm cây xăng rẻ nhất quanh xe từng phút<br>🅿️ Tra cứu giờ đỗ xe (Parkscheibe), khu vực khí thải (Umweltplakette) |
| **Tính năng chủ động (Proactive AI)** | Bị động (phải bấm mic mới nói) | 🎙️ **Bản tin chào buổi sáng khi nổ máy:** Báo thời tiết, giao thông lộ trình và deal giảm giá siêu thị Đức hôm nay |
| **Kiến trúc mở rộng (MCP)** | Đóng kín, tính phí theo tài khoản VIP | 🚀 **Model Context Protocol (MCP) mở:** Tự do tích hợp bất kỳ API dịch vụ nào tại Đức |
| **Quyền làm chủ** | Thuê bot của bên thứ 3 | 💎 **Làm chủ mã nguồn 100%:** Tự chủ server, dữ liệu và thương hiệu |

---

## II. BẢN THIẾT KẾ ĐA TRỢ LÝ (MULTI-PERSONA GRID)

Màn hình *"Chọn Trợ Lý"* được thiết kế dạng lưới 2 cột tỷ lệ màn hình ô tô với các nhân vật chuyên biệt:

1. 🇩🇪 **Thầy Peter - Giáo viên tiếng Đức bản xứ**
   - **Nhiệm vụ:** Đồng hành học tiếng Đức trên xe.
   - **Kỹ năng:** Sửa lỗi ngữ pháp (chia giống der/die/das, Dativ/Akkusativ), giải thích từ vựng bằng tiếng Việt, luyện phản xạ hỏi đáp chuẩn Hochdeutsch.
2. 🚗 **Mina Xe Hơi - Bạn đường nước Đức**
   - **Nhiệm vụ:** Dẫn đường qua Google Maps, đọc biển báo, cảnh báo tốc độ, hướng dẫn xử lý sự cố xe hơi ở Đức (ADAC, TÜV, bảo hiểm).
3. 🛒 **Mina Săn Deal - Chuyên gia Siêu thị Đức**
   - **Nhiệm vụ:** Quét tờ rơi khuyến mãi (*Prospekte*) tuần này của Kaufland, Lidl, Aldi, Rewe, Netto... Báo ngay khi có tuần lễ châu Á (*Asia Woche*), giảm giá mì tôm, gạo, sườn, thịt bò.
4. 💖 **Mina Tâm Sự - Bạn đồng hành vui vẻ**
   - **Nhiệm vụ:** Trò chuyện đời sống, giải tỏa buồn ngủ, kể chuyện cười, đọc tin tức thời sự tiếng Việt.

---

## III. KIẾN TRÚC KỸ THUẬT: SĂN DEAL SIÊU THỊ ĐỨC & SỨC CHỊU TẢI LỚN

### 1. Tại sao KHÔNG để từng chiếc xe tự cào web khi nổ máy?
* **Rủi ro:** Nếu 1.000 xe cùng nổ máy lúc 7h sáng và đồng loạt gửi yêu cầu cào trang web Kaufland/Lidl:
  - Tường lửa Cloudflare của siêu thị sẽ chặn IP ngay lập tức.
  - Xe phải chờ 5 - 10 giây mới có câu trả lời (gây đơ app).
  - Tốn tài nguyên mạng và CPU của màn hình xe hơi.

### 2. Kiến trúc chuẩn mực cao cấp: "Data Collector Bot + Smart Cache"
* **Đặc tính dữ liệu siêu thị Đức:** Các siêu thị chỉ đổi tờ rơi khuyến mại (*Prospekt*) **1 lần / tuần** (vào thứ Hai hoặc thứ Năm).
* **Quy trình hoạt động:**
  - Bot ngầm quét dữ liệu 1 lần mỗi tuần / mỗi sáng sớm.
  - Lọc ra 20-30 mặt hàng hot (Mì tôm, gạo, sườn, ba chỉ, cá hồi...) và lưu vào file Cache siêu nhẹ (JSON / Redis).
  - Khi xe nổ máy, Mina AI đọc từ Cache trong **0.05 giây (50 phần nghìn giây)** mà không cần chờ đợi.
* **Kết quả:**
  - Tốc độ phản hồi cực nhanh: **Dưới 0.1 giây**.
  - Không bao giờ bị lỗi hay nghẽn mạng.
  - Phục vụ được từ **1 chiếc xe đến 100.000 chiếc xe cùng lúc** mà không lo quá tải.

---

## IV. GIẢI PHÁP CHỈ ĐƯỜNG GOOGLE MAPS & BONG BÓNG NỔI (FLOATING WIDGET)

1. **Tích hợp Google Maps Turn-by-Turn:**
   - Sử dụng Android Intent điều hướng gốc: `google.navigation:q={lat},{lon}` hoặc `google.navigation:q={dia_diem}`.
   - Khai thác trọn vẹn dữ liệu giao thông thực của Google: Cảnh báo tắc đường (Stau), chỉ dẫn làn đường chuẩn xác.
2. **Bong bóng nổi (Floating Bubble System Alert):**
   - Khi Google Maps mở toàn màn hình, Mina AI thu nhỏ thành quả cầu tròn nổi trên góc phải.
   - Tài xế chạm 1 cái hoặc ra lệnh bằng giọng nói, thanh phụ đề và âm thanh của Mina AI sẽ phản hồi ngay lập tức mà không làm gián đoạn bản đồ.

---

## V. LỘ TRÌNH THỰC HIỆN THEO CÁC GIAI ĐOẠN

### 📍 Giai đoạn 1: Hệ thống Đa Trợ Lý & Trợ lý Tiếng Đức (Đang triển khai)
- [ ] Thiết kế màn hình `AssistantSelectionScreen` chuẩn ô tô (Grid 2 cột).
- [ ] Tích hợp 4 nhân vật mẫu: Thầy Peter Tiếng Đức, Mina Xe Hơi, Mina Săn Deal, Mina Tâm Sự.
- [ ] Cơ chế chuyển đổi Persona và System Prompt mượt mà không cần thoát app.

### 📍 Giai đoạn 2: Tích hợp Google Maps & Bong bóng nổi
- [ ] Bổ sung lệnh giọng nói tìm đường và mở Google Maps tự động.
- [ ] Xây dựng dịch vụ Overlay Floating Bubble trên Android.

### 📍 Giai đoạn 3: Dịch vụ Săn Deal Siêu Thị & Bản Tin Buổi Sáng
- [ ] Xây dựng script bot thu thập khuyến mại (Kaufland, Lidl, Aldi) theo mã bưu chính Đức (PLZ).
- [ ] Hook bản tin tự động chào hỏi khi nổ máy xe.

---
*Tài liệu được lưu trữ vĩnh viễn trong mã nguồn dự án để làm kim chỉ nam phát triển.*
