# Tối ưu hiệu suất cho bảng dữ liệu lớn (1000-2000 dòng)

## Vấn đề hiện tại
- File `erp_data_tab.dart` render tất cả rows cùng lúc
- Mỗi row có nhiều widget phức tạp (Container, Border, Text, etc.)
- Với 2000 rows × 20 columns = 40,000+ widgets được build cùng lúc
- Gây lag, treo, và có thể crash server/app

## Giải pháp đã áp dụng

### 1. Backend không thay đổi
- Server vẫn trả về toàn bộ dữ liệu
- Đảm bảo tính năng scan/search hoạt động trên tất cả records

### 2. Frontend optimization (cần implement)

#### A. Sử dụng ListView.builder
```dart
ListView.builder(
  itemCount: filteredData.length,
  addAutomaticKeepAlives: false,  // Không cache widgets cũ
  addRepaintBoundaries: true,      // Tối ưu repaint
  cacheExtent: 500,                // Giới hạn cache
  itemBuilder: (context, index) {
    return _buildRow(filteredData[index], index);
  },
)
```

#### B. Optimize widget tree
- Giảm số lượng Container lồng nhau
- Dùng const constructor khi có thể
- Tránh rebuild không cần thiết

#### C. Lazy rendering
- Chỉ build widgets cho rows đang hiển thị trên màn hình
- Flutter tự động dispose widgets ngoài viewport

### 3. Kết quả mong đợi
- **Smooth scrolling** ngay cả với 2000+ rows
- **Instant search** - tìm trong toàn bộ data
- **Memory efficient** - chỉ giữ ~50-100 rows trong memory
- **No lag** - 60fps scrolling

## Lưu ý
- Cần refactor `_buildTablePart` method để dùng ListView.builder
- Giữ nguyên logic search, filter, và column configuration
- Virtual scrolling tự động bởi Flutter framework
