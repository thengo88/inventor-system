# 🚀 HƯỚNG DẪN TRIỂN KHAI LÊN RENDER & TURSO

Tài liệu này hướng dẫn bạn đưa hệ thống Inventor từ máy cá nhân lên Cloud (Internet) để có thể truy cập từ bất cứ đâu.

---

## 🏗️ KIẾN TRÚC MỚI
- **Backend:** Node.js (Render.com)
- **Database:** Managed libSQL (Turso.tech) - Thay thế cho file `database.db` cục bộ để đảm bảo dữ liệu không bị mất khi Server khởi động lại.
- **Frontend:** Flutter Web (được phục vụ bởi chính Node.js server).

---

## 🛠️ CÁC BƯỚC CHUẨN BỊ

### 1. Thiết lập Database (Turso)
1. Truy cập [Turso.tech](https://turso.tech/) và đăng ký tài khoản.
2. Cài đặt Turso CLI hoặc sử dụng Web Dashboard.
3. Tạo database mới:
   ```bash
   turso db create inventor-db
   ```
4. Lấy URL và Token:
   - **URL:** `libsql://inventor-db-yourname.turso.io`
   - **Token:** Chạy lệnh `turso db tokens create inventor-db`

### 2. Đưa code lên GitHub
1. Tạo một repository mới trên GitHub (ví dụ: `inventor-system`).
2. Push toàn bộ code của bạn lên đó (bao gồm cả folder `server` và folder `lib`).
   *Lưu ý: Không nên push file `database.db` và `node_modules`.*

---

## 🚀 TRIỂN KHAI LÊN RENDER

1. Truy cập [Render.com](https://render.com/) và kết nối với GitHub.
2. Chọn **New +** -> **Blueprint**.
3. Render sẽ tự động nhận diện file `render.yaml` tôi đã tạo cho bạn.
4. **Cấu hình Environment Variables:**
   Trong quá trình tạo, Render sẽ yêu cầu bạn nhập các giá trị sau:
   - `TURSO_DATABASE_URL`: (URL lấy từ bước 1)
   - `TURSO_AUTH_TOKEN`: (Token lấy từ bước 1)

5. Nhấn **Apply**.
6. Đợi khoảng 2-5 phút để Render build và deploy.
7. Bạn sẽ nhận được một URL có dạng: `https://inventor-server.onrender.com`

---

## 📱 CẬP NHẬT TRÊN MOBILE APP

Bây giờ server đã ở trên Internet, bạn không cần dùng IP LAN nữa:

1. Mở App trên điện thoại.
2. Ở màn hình Login, nhấn vào **Cài đặt Server** (icon bánh răng hoặc nút đổi IP).
3. Nhập URL Render của bạn vào:
   - Ví dụ: `https://inventor-server.onrender.com`
4. Hệ thống sẽ tự động nhận diện đây là URL Cloud và kết nối qua HTTPS (An toàn).

---

## 🌐 TRUY CẬP WEB INTERFACE

Truy cập trực tiếp URL Render của bạn từ trình duyệt:
`https://inventor-server.onrender.com`

---

## ⚠️ LƯU Ý QUAN TRỌNG

1. **Dữ liệu cũ:** File `database.db` hiện tại trên máy bạn sẽ KHÔNG tự động chuyển lên Turso. Bạn nên sử dụng tính năng **Import Excel** trên giao diện web mới để đưa dữ liệu vào hệ thống Cloud.
2. **Puppeteer (ERP Scraping):** Trên gói Free của Render, tính năng Scraping có thể bị chậm hoặc không hoạt động do giới hạn tài nguyên. Khuyến khích sử dụng **Import Excel** làm phương thức chính.
3. **SSL/HTTPS:** Render tự động cấp chứng chỉ SSL, bạn không cần quan tâm đến file `key.pem` và `cert.pem` nữa.

---

**🎉 CHÚC MỪNG! HỆ THỐNG CỦA BẠN ĐÃ SẴN SÀNG TRÊN TOÀN CẦU! 🎉**
