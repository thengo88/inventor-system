const API_BASE = window.location.origin + '/api';
let currentUser = null;
let socket = null;
let wakeLock = null;
let qrScanActive = false;

document.addEventListener('DOMContentLoaded', () => {
    // Check if already logged in
    const savedUser = localStorage.getItem('inventor_user');
    if (savedUser) {
        currentUser = JSON.parse(savedUser);
        showApp();
    } else {
        showLogin();
    }

    // Setup event listeners
    setupEventListeners();

    // Request wake lock
    requestWakeLock();

    // Re-request wake lock when page becomes visible again
    document.addEventListener('visibilitychange', async () => {
        if (wakeLock !== null && document.visibilityState === 'visible') {
            await requestWakeLock();
        }
    });

    // Hide loading screen
    setTimeout(() => {
        document.getElementById('loading-screen').classList.add('hidden');
    }, 500);
});

async function requestWakeLock() {
    if ('wakeLock' in navigator) {
        try {
            wakeLock = await navigator.wakeLock.request('screen');
            console.log('✅ Đã kích hoạt chế độ chống tắt màn hình');

            wakeLock.addEventListener('release', () => {
                console.log('⚠️ Chế độ chống tắt màn hình đã bị hủy');
            });
        } catch (err) {
            console.error('❌ Lỗi kích hoạt Wake Lock:', err);
        }
    } else {
        console.warn('⚠️ Trình duyệt không hỗ trợ Wake Lock API');
    }
}

function setupEventListeners() {
    // Login form
    document.getElementById('login-form').addEventListener('submit', handleLogin);

    // Calculator inputs
    const calcInputs = ['pcs-per-bag', 'ngang', 'doc', 'chan', 'le', 'pcs-le'];
    calcInputs.forEach(id => {
        document.getElementById(id).addEventListener('input', calculateTotal);
    });

    // SKU input
    document.getElementById('sku-input').addEventListener('change', handleSkuChange);
}

// Authentication
async function handleLogin(e) {
    e.preventDefault();

    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value.trim();
    const loginBtn = document.getElementById('login-btn');
    const errorDiv = document.getElementById('login-error');

    loginBtn.disabled = true;
    loginBtn.textContent = 'Đang đăng nhập...';
    errorDiv.classList.add('hidden');

    try {
        // Attempt 1: Standard POST Login
        let response = await fetch(`${API_BASE}/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });

        if (!response.ok && username === 'admin') {
            // Attempt 2: Emergency GET Login (Bypass body parsing issues)
            console.warn('POST failed, trying fallback GET login...');
            response = await fetch(`${API_BASE}/login-emergency?username=${encodeURIComponent(username)}&password=${encodeURIComponent(password)}`);
        }

        if (response.ok) {
            const data = await response.json();
            currentUser = data;
            localStorage.setItem('inventor_user', JSON.stringify(data));
            showApp();
            requestWakeLock();
        } else {
            const errData = await response.json().catch(() => ({}));
            showError(errData.error || 'Tên đăng nhập hoặc mật khẩu không đúng');
        }
    } catch (error) {
        console.error(error);
        showError('Lỗi kết nối server: ' + error.message);
    } finally {
        loginBtn.disabled = false;
        loginBtn.textContent = 'Đăng nhập';
    }
}

function showError(message) {
    const errorDiv = document.getElementById('login-error');
    const errorText = document.getElementById('login-error-text');
    errorText.textContent = message;
    errorDiv.classList.remove('hidden');
}

function logout() {
    if (confirm('Bạn có chắc muốn đăng xuất?')) {
        localStorage.removeItem('inventor_user');
        currentUser = null;
        if (socket) socket.disconnect();
        location.reload();
    }
}

function showLogin() {
    document.getElementById('login-screen').classList.remove('hidden');
    document.getElementById('app').classList.remove('active');
}

function showApp() {
    document.getElementById('login-screen').classList.add('hidden');
    document.getElementById('app').classList.add('active');

    // Set user info
    const avatar = document.getElementById('user-avatar');
    avatar.textContent = currentUser.username.charAt(0).toUpperCase();

    // Initialize app features
    initializeSocket();
    loadHistory();
    loadNotifications();
    const now = new Date().toISOString();
    loadSuggestions();
}

// Socket.IO
function initializeSocket() {
    socket = io(window.location.origin);

    socket.on('connect', () => {
        console.log('Socket connected');
    });

    socket.on('notification', (data) => {
        loadNotifications();
        showAlert('Bạn có thông báo mới!', 'warning');
    });

    socket.on('stock_audit_updated', (data) => {
        loadHistory();
    });

    // Cập nhật ERP tức thì
    socket.on('erp_update_all', () => {
        console.log('🔄 ERP Data Updated');
        // Đối với Flutter Web, hàm này sẽ được gọi qua reload
        location.reload();
    });

    // Cập nhật thông báo tức thì (Dành cho web mobile.html)
    socket.on('notification_update', (data) => {
        loadNotifications();
    });
}

// Tab Navigation
function switchTab(tabName) {
    // Update nav items
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.remove('active');
    });
    event.currentTarget.classList.add('active');

    // Update content
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
    });
    document.getElementById(`tab-${tabName}`).classList.add('active');

    // Update header title
    const titles = {
        'scanner': 'Kiểm kê kho',
        'history': 'Lịch sử',
        'notifications': 'Thông báo'
    };
    document.getElementById('header-title').textContent = titles[tabName];

    // Load data if needed
    if (tabName === 'history') loadHistory();
    if (tabName === 'notifications') loadNotifications();
}

// Calculator
function calculateTotal() {
    const pcsPerBag = parseFloat(document.getElementById('pcs-per-bag').value) || 0;
    const ngang = parseFloat(document.getElementById('ngang').value) || 0;
    const doc = parseFloat(document.getElementById('doc').value) || 0;
    const chan = parseFloat(document.getElementById('chan').value) || 0;
    const le = parseFloat(document.getElementById('le').value) || 0;
    const pcsLe = parseFloat(document.getElementById('pcs-le').value) || 0;

    const total = ((ngang * doc * chan) + le) * pcsPerBag + pcsLe;
    document.getElementById('total-qty').value = Math.round(total);
}

// SKU Handler
async function handleSkuChange() {
    const sku = document.getElementById('sku-input').value.trim();
    if (!sku) return;

    try {
        // Try to get product info
        const response = await fetch(`${API_BASE}/products/${sku}`);
        if (response.ok) {
            const product = await response.json();

            // Auto-fill packaging standard
            const pkgMatch = product.packagingStandard.match(/(\d+)/);
            if (pkgMatch) {
                document.getElementById('pcs-per-bag').value = pkgMatch[0];
                calculateTotal();
            }
        }
    } catch (error) {
        console.error('Error fetching product:', error);
    }
}

// Scanner
let stream = null;

async function openScanner() {
    // Check if browser supports camera
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        let errorMsg = 'Trình duyệt của bạn không hỗ trợ camera.';
        // Secure context check
        if (window.location.protocol !== 'https:' && window.location.hostname !== 'localhost') {
            errorMsg = 'LỖI BẢO MẬT: Camera chỉ hoạt động trên giao thức HTTPS. Vui lòng sử dụng địa chỉ HTTPS.';
        }
        showAlert(errorMsg, 'error');
        return;
    }

    const modal = document.getElementById('camera-modal');
    const video = document.getElementById('camera-preview');
    const canvasElement = document.createElement('canvas');
    const canvas = canvasElement.getContext('2d', { willReadFrequently: true });

    try {
        stream = await navigator.mediaDevices.getUserMedia({
            video: { facingMode: 'environment' }
        });

        video.srcObject = stream;
        video.setAttribute('playsinline', 'true');
        video.setAttribute('muted', 'true');
        video.muted = true; // Required for autoplay on some browsers

        await video.play();

        modal.classList.add('active');
        qrScanActive = true;

        // Vibration feedback (if supported)
        if ('vibrate' in navigator) navigator.vibrate(50);

        showAlert('📷 Camera đang bật. Hãy hướng về mã QR.', 'success');

        requestAnimationFrame(tick);

        function tick() {
            if (!qrScanActive) return;

            if (video.readyState === video.HAVE_ENOUGH_DATA) {
                canvasElement.height = video.videoHeight;
                canvasElement.width = video.videoWidth;
                canvas.drawImage(video, 0, 0, canvasElement.width, canvasElement.height);

                const imageData = canvas.getImageData(0, 0, canvasElement.width, canvasElement.height);

                if (typeof jsQR === 'undefined') {
                    console.error('jsQR library missing');
                    return;
                }

                const code = jsQR(imageData.data, imageData.width, imageData.height, {
                    inversionAttempts: 'dontInvert',
                });

                if (code && code.data) {
                    playBeep();
                    if ('vibrate' in navigator) navigator.vibrate([100, 50, 100]);

                    const skuInput = document.getElementById('sku-input');
                    skuInput.value = code.data;
                    skuInput.blur(); // Hide keyboard

                    handleSkuChange();
                    showAlert('✅ Đã quét: ' + code.data, 'success');
                    closeScanner();
                    return;
                }
            }
            requestAnimationFrame(tick);
        }

    } catch (error) {
        console.error('Scanner error:', error);
        let msg = 'Không thể truy cập camera. ';
        if (error.name === 'NotAllowedError') msg += 'Bạn chưa cấp quyền truy cập camera.';
        else if (error.name === 'NotFoundError') msg += 'Không tìm thấy camera.';
        else msg += 'Vui lòng nhập mã thủ công.';
        showAlert(msg, 'error');
    }
}

function closeScanner() {
    const modal = document.getElementById('camera-modal');
    const video = document.getElementById('camera-preview');

    qrScanActive = false;
    if (stream) {
        stream.getTracks().forEach(track => track.stop());
        stream = null;
    }

    video.srcObject = null;
    modal.classList.remove('active');
}

// Submit Audit
async function submitAudit() {
    const sku = document.getElementById('sku-input').value.trim();
    const warehouse = document.getElementById('warehouse-input').value.trim();
    const totalQty = document.getElementById('total-qty').value;

    // Blur all inputs to hide keyboard on mobile
    document.querySelectorAll('input').forEach(i => i.blur());

    if (!sku || !totalQty || totalQty === '0') {
        showAlert('Vui lòng nhập đầy đủ thông tin!', 'error');
        return;
    }

    const submitBtn = document.getElementById('submit-btn');
    submitBtn.disabled = true;
    submitBtn.textContent = 'Đang lưu...';

    try {
        const response = await fetch(`${API_BASE}/stock-audit/safe-update`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                sku: sku,
                warehouse: warehouse || 'Default',
                updates: {
                    packagingStandard: parseInt(document.getElementById('pcs-per-bag').value) || 0,
                    horRows: parseInt(document.getElementById('ngang').value) || 0,
                    verRows: parseInt(document.getElementById('doc').value) || 0,
                    evenRows: parseInt(document.getElementById('chan').value) || 0,
                    oddRows: parseInt(document.getElementById('le').value) || 0,
                    individualBags: parseInt(document.getElementById('pcs-le').value) || 0,
                    totalResult: parseFloat(totalQty)
                },
                version: 0, // Will be tracked properly in production
                auditor: currentUser.username
            })
        });

        if (response.ok) {
            showAlert('✅ Lưu dữ liệu thành công!', 'success');
            resetCalculator();
            loadHistory();

            // Play beep sound
            playBeep();
        } else if (response.status === 409) {
            const data = await response.json();
            showAlert('⚠️ ' + data.message, 'warning');
        } else {
            showAlert('❌ Lỗi khi lưu dữ liệu', 'error');
        }
    } catch (error) {
        showAlert('❌ Không thể kết nối đến server', 'error');
    } finally {
        submitBtn.disabled = false;
        submitBtn.textContent = 'Lưu dữ liệu';
    }
}

function resetCalculator() {
    document.getElementById('sku-input').value = '';
    document.getElementById('ngang').value = '0';
    document.getElementById('doc').value = '0';
    document.getElementById('chan').value = '0';
    document.getElementById('le').value = '0';
    document.getElementById('pcs-le').value = '0';
    document.getElementById('total-qty').value = '0';
    document.getElementById('sku-input').focus();
}

function playBeep() {
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    oscillator.frequency.value = 800;
    oscillator.type = 'sine';

    gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.1);

    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + 0.1);
}

// Suggestions (Autocomplete)
async function loadSuggestions() {
    try {
        // Load Warehouses
        const whRes = await fetch(`${API_BASE}/erp/warehouses`);
        if (whRes.ok) {
            const warehouses = await whRes.json();
            const whList = document.getElementById('warehouse-list');
            whList.innerHTML = warehouses.map(wh => `<option value="${wh}">`).join('');
        }

        // Load SKUs (from ERP stock)
        const stRes = await fetch(`${API_BASE}/erp/stock`);
        if (stRes.ok) {
            const stock = await stRes.json();
            const skuList = document.getElementById('sku-list');
            const uniqueSkus = [...new Set(stock.map(item => item.sku))];
            skuList.innerHTML = uniqueSkus.map(sku => `<option value="${sku}">`).join('');
        }
    } catch (error) {
        console.error('Error loading suggestions:', error);
    }
}

// History
async function loadHistory() {
    const listEl = document.getElementById('history-list');
    listEl.innerHTML = '<li style="text-align: center; padding: 40px;">Đang tải...</li>';

    try {
        const response = await fetch(`${API_BASE}/audit/history`);
        if (response.ok) {
            const data = await response.json();

            if (data.length === 0) {
                listEl.innerHTML = '<li style="text-align: center; padding: 40px; color: var(--text-secondary);">Chưa có lịch sử</li>';
                return;
            }

            listEl.innerHTML = data.slice(0, 50).map(item => `
                <li class="history-item">
                    <div class="history-header">
                        <div class="history-sku">${item.sku || 'N/A'}</div>
                        <div class="history-qty">${item.totalResult || 0}</div>
                    </div>
                    <div class="history-meta">
                        <span>👤 ${item.auditor || 'Unknown'}</span>
                        <span>📦 ${item.warehouse || 'Default'}</span>
                        <span>🕐 ${formatTime(item.timestamp)}</span>
                    </div>
                </li>
            `).join('');
        }
    } catch (error) {
        listEl.innerHTML = '<li style="text-align: center; padding: 40px; color: var(--danger);">Lỗi khi tải dữ liệu</li>';
    }
}

// Notifications
async function loadNotifications() {
    const listEl = document.getElementById('notifications-list');
    const badge = document.getElementById('notif-badge');

    try {
        const response = await fetch(`${API_BASE}/notifications?user=${currentUser.username}`);
        if (response.ok) {
            const data = await response.json();

            // Update badge
            const unreadCount = data.filter(n => !n.readBy || !n.readBy.includes(currentUser.username)).length;
            if (unreadCount > 0) {
                badge.textContent = unreadCount;
                badge.classList.remove('hidden');
            } else {
                badge.classList.add('hidden');
            }

            if (data.length === 0) {
                listEl.innerHTML = '<li style="text-align: center; padding: 40px; color: var(--text-secondary);">Chưa có thông báo</li>';
                return;
            }

            listEl.innerHTML = data.map(item => `
                <li class="history-item">
                    <div class="history-header">
                        <div class="history-sku">${item.type || 'INFO'}</div>
                        <div style="font-size: 12px; color: var(--text-secondary);">
                            ${formatTime(item.timestamp)}
                        </div>
                    </div>
                    <div style="margin-top: 8px; color: var(--text);">
                        ${item.message || ''}
                    </div>
                </li>
            `).join('');
        }
    } catch (error) {
        console.error('Error loading notifications:', error);
    }
}

// Utilities
function showAlert(message, type = 'success') {
    const container = document.getElementById('alert-container');
    const alert = document.createElement('div');
    alert.className = `alert alert-${type}`;
    alert.innerHTML = `
        <span>${type === 'success' ? '✅' : type === 'error' ? '❌' : '⚠️'}</span>
        <span>${message}</span>
    `;

    container.innerHTML = '';
    container.appendChild(alert);

    setTimeout(() => {
        alert.remove();
    }, 5000);
}

function formatTime(timestamp) {
    if (!timestamp) return 'N/A';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now - date;

    if (diff < 60000) return 'Vừa xong';
    if (diff < 3600000) return Math.floor(diff / 60000) + ' phút trước';
    if (diff < 86400000) return Math.floor(diff / 3600000) + ' giờ trước';

    return date.toLocaleDateString('vi-VN') + ' ' + date.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' });
}

// Service Worker Registration (PWA)
if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
            .then(reg => console.log('Service Worker registered'))
            .catch(err => console.log('Service Worker registration failed'));
    });
}
