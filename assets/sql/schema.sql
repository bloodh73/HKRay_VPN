-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    service_amount DECIMAL(10, 2) COMMENT 'مبلغ سرویس',
    multi_user BOOLEAN DEFAULT FALSE COMMENT 'مولتی یوزر',
    visit_status VARCHAR(50) COMMENT 'وضعیت بازدید',
    username VARCHAR(50) UNIQUE NOT NULL COMMENT 'نام کاربری',
    password VARCHAR(255) NOT NULL COMMENT 'رمز عبور',
    total_volume BIGINT COMMENT 'حجم کلی (به مگابایت)',
    used_volume BIGINT DEFAULT 0 COMMENT 'حجم مصرفی (به مگابایت)',
    remaining_volume BIGINT COMMENT 'حجم مانده (به مگابایت)',
    total_days INT COMMENT 'روزهای کلی',
    remaining_days INT COMMENT 'روزهای مانده',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'تاریخ ایجاد',
    last_login DATETIME COMMENT 'تاریخ آخرین ورود',
    expiry_date DATETIME COMMENT 'تاریخ انقضا',
    is_logged_in BOOLEAN DEFAULT FALSE COMMENT 'وضعیت لاگین',
    multi_account BOOLEAN DEFAULT FALSE COMMENT 'امکان چند اکانت',
    status ENUM('active', 'inactive', 'suspended') DEFAULT 'active' COMMENT 'وضعیت حساب',
    options TEXT COMMENT 'گزینه‌های اضافی (JSON format)'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_persian_ci;

-- Create servers table
CREATE TABLE IF NOT EXISTS servers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    share_link TEXT NOT NULL COMMENT 'لینک اشتراک',
    description TEXT COMMENT 'توضیحات',
    ping INT DEFAULT 0 COMMENT 'پینگ (به میلی‌ثانیه)',
    status ENUM('online', 'offline', 'maintenance') DEFAULT 'offline' COMMENT 'وضعیت سرور',
    last_status_change TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP COMMENT 'تاریخ آخرین تغییر وضعیت',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'تاریخ ایجاد',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'تاریخ به‌روزرسانی'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_persian_ci;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_expiry_date ON users(expiry_date);
CREATE INDEX IF NOT EXISTS idx_server_status ON servers(status);
CREATE INDEX IF NOT EXISTS idx_last_status_change ON servers(last_status_change);
