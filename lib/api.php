<?php
// api.php

// تنظیم هدرها برای پاسخ JSON و کنترل دسترسی CORS
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// تنظیمات دیتابیس - **اینجا را با اطلاعات سرور خود جایگزین کنید**
$servername = "localhost";
$username = "vghzoegc_hamed";
$password = "Hamed1373r";
$dbname = "vghzoegc_hkray";

// ایجاد اتصال به دیتابیس
$conn = new mysqli($servername, $username, $password, $dbname); // این خط به اینجا منتقل شد

// بررسی اتصال به دیتابیس
if ($conn->connect_error) {
    http_response_code(500);
    die(json_encode(["success" => false, "message" => "Connection failed: " . $conn->connect_error]));
}

$action = $_GET['action'] ?? '';

switch ($action) {
    case 'login':
        $user = $_POST['username'] ?? '';
        $pass = $_POST['password'] ?? '';
        $deviceName = $_POST['device_name'] ?? 'Unknown Device'; // دریافت نام دستگاه

        if (empty($user) || empty($pass)) {
            echo json_encode(["success" => false, "message" => "نام کاربری و رمز عبور را وارد کنید."]);
            break;
        }

        // انتخاب فیلد username نیز برای بازگرداندن در پاسخ
        $stmt = $conn->prepare("SELECT id, username, password, expiry_date, total_volume, used_volume, total_days, status FROM users WHERE username = ?");
        $stmt->bind_param("s", $user);
        $stmt->execute();
        $result = $stmt->get_result();

        if ($result->num_rows > 0) {
            $row = $result->fetch_assoc();
            if (password_verify($pass, $row['password'])) {
                if ($row['status'] !== 'active') {
                    echo json_encode(["success" => false, "message" => "حساب کاربری شما " . $row['status'] . " است."]);
                    $stmt->close();
                    break;
                }
                
                $expiry_date_timestamp = strtotime($row['expiry_date']);
                $current_date_timestamp = time();

                if ($current_date_timestamp > $expiry_date_timestamp) {
                    echo json_encode(["success" => false, "message" => "اشتراک شما منقضی شده است."]);
                } else {
                    $remaining_seconds = $expiry_date_timestamp - $current_date_timestamp;
                    $remaining_days = floor($remaining_seconds / (60 * 60 * 24));
                    if ($remaining_days < 0) $remaining_days = 0;

                    $remaining_volume = $row['total_volume'] - $row['used_volume'];
                    if ($remaining_volume < 0) $remaining_volume = 0;

                    $userId = $row['id'];
                    $currentTimestamp = date('Y-m-d H:i:s');

                    // --- NEW: Check active devices before allowing login ---
                    $activeDevicesStmt = $conn->prepare("SELECT COUNT(*) AS active_count FROM logged_in_devices WHERE user_id = ? AND is_logged_in = 1");
                    $activeDevicesStmt->bind_param("i", $userId);
                    $activeDevicesStmt->execute();
                    $activeDevicesResult = $activeDevicesStmt->get_result();
                    $activeDevicesRow = $activeDevicesResult->fetch_assoc();
                    $activeCount = $activeDevicesRow['active_count'];
                    $activeDevicesStmt->close();

                    // Check if this specific device is already logged in
                    $checkDeviceStmt = $conn->prepare("SELECT id, is_logged_in FROM logged_in_devices WHERE user_id = ? AND device_name = ?");
                    $checkDeviceStmt->bind_param("is", $userId, $deviceName);
                    $checkDeviceStmt->execute();
                    $checkDeviceResult = $checkDeviceStmt->get_result();
                    $deviceExists = $checkDeviceResult->num_rows > 0;
                    $deviceRow = $checkDeviceResult->fetch_assoc();
                    $checkDeviceStmt->close();

                    if ($deviceExists && $deviceRow['is_logged_in'] == 1) {
                        // Device is already logged in, just update last_login
                        $updateDeviceStmt = $conn->prepare("UPDATE logged_in_devices SET last_login = ? WHERE user_id = ? AND device_name = ?");
                        $updateDeviceStmt->bind_param("sis", $currentTimestamp, $userId, $deviceName);
                        $updateDeviceStmt->execute();
                        $updateDeviceStmt->close();
                    } else if ($activeCount >= 2 && !$deviceExists) {
                        // Max devices reached and this is a new device
                        echo json_encode(["success" => false, "message" => "شما به حداکثر تعداد دستگاه‌های فعال (2) رسیده‌اید. لطفاً از یکی از دستگاه‌های دیگر خارج شوید."]);
                        $stmt->close();
                        break;
                    } else {
                        // Either less than 2 active devices, or this device exists but was logged out
                        if ($deviceExists) {
                            // Device exists but was logged out, update its status to logged in
                            $updateDeviceStmt = $conn->prepare("UPDATE logged_in_devices SET is_logged_in = 1, last_login = ? WHERE user_id = ? AND device_name = ?");
                            $updateDeviceStmt->bind_param("sis", $currentTimestamp, $userId, $deviceName);
                            $updateDeviceStmt->execute();
                            $updateDeviceStmt->close();
                        } else {
                            // New device, insert a new record
                            $insertDeviceStmt = $conn->prepare("INSERT INTO logged_in_devices (user_id, username, device_name, last_login, is_logged_in) VALUES (?, ?, ?, ?, 1)");
                            $insertDeviceStmt->bind_param("isss", $userId, $user, $deviceName, $currentTimestamp);
                            $insertDeviceStmt->execute();
                            $insertDeviceStmt->close();
                        }
                    }
                    // --- END NEW ---

                    // Generate a simple token for demonstration
                    $token = bin2hex(random_bytes(16)); // Generates a 32-character hex string

                    echo json_encode([
                        "success" => true,
                        "message" => "ورود موفقیت آمیز",
                        "user_id" => $row['id'],
                        "username" => $row['username'], // اضافه شدن username
                        "total_volume" => (int)$row['total_volume'],
                        "used_volume" => (int)$row['used_volume'],
                        "remaining_volume" => (int)$remaining_volume,
                        "total_days" => (int)$remaining_days, // Changed to remaining_days
                        "expiry_date" => $row['expiry_date'],
                        "token" => $token // Include the generated token
                    ]);
                }
            } else {
                echo json_encode(["success" => false, "message" => "نام کاربری یا رمز عبور اشتباه است."]);
            }
        } else {
            echo json_encode(["success" => false, "message" => "نام کاربری یا رمز عبور اشتباه است."]);
        }
        $stmt->close();
        break;

    case 'getSubscription':
    case 'getServers': // اضافه شدن این خط برای مدیریت درخواست getServers
        // بازگرداندن تمام لینک‌های سابسکریپشن آنلاین
        $stmt = $conn->prepare("SELECT share_link FROM servers WHERE status = 'online'");
        $stmt->execute();
        $result = $stmt->get_result();

        $share_links = [];
        if ($result->num_rows > 0) {
            while($row = $result->fetch_assoc()) {
                $share_links[] = $row['share_link'];
            }
            echo json_encode([
                "success" => true,
                "share_links" => $share_links // تغییر نام فیلد به share_links و ارسال آرایه
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "هیچ لینک سابسکریپشن فعالی یافت نشد."]);
        }
        $stmt->close();
        break;

    case 'getUserDetails':
        $userId = $_GET['user_id'] ?? null;

        if (empty($userId)) {
            echo json_encode(["success" => false, "message" => "User ID is required."]);
            break;
        }

        $stmt = $conn->prepare("SELECT username, total_volume, used_volume, total_days, expiry_date, status FROM users WHERE id = ?");
        $stmt->bind_param("i", $userId); // "i" for integer
        $stmt->execute();
        $result = $stmt->get_result();

        if ($result->num_rows > 0) {
            $row = $result->fetch_assoc();
            
            $expiry_date_timestamp = strtotime($row['expiry_date']);
            $current_date_timestamp = time();

            $remaining_seconds = $expiry_date_timestamp - $current_date_timestamp;
            $remaining_days = floor($remaining_seconds / (60 * 60 * 24));
            if ($remaining_days < 0) $remaining_days = 0;

            $remaining_volume = $row['total_volume'] - $row['used_volume'];
            if ($remaining_volume < 0) $remaining_volume = 0;

            echo json_encode([
                "success" => true,
                "username" => $row['username'],
                "total_volume" => (int)$row['total_volume'],
                "used_volume" => (int)$row['used_volume'],
                "remaining_volume" => (int)$remaining_volume,
                "total_days" => (int)$row['total_days'],
                "remaining_days" => (int)$remaining_days,
                "expiry_date" => $row['expiry_date'],
                "status" => $row['status']
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "User not found."]);
        }
        $stmt->close();
        break;

    case 'updateTraffic':
        $userId = $_POST['user_id'] ?? null;
        $upload = $_POST['upload'] ?? 0;
        $download = $_POST['download'] ?? 0;

        if (empty($userId)) {
            echo json_encode(["success" => false, "message" => "User ID is required."]);
            break;
        }

        // Fetch current used_volume
        $stmt = $conn->prepare("SELECT used_volume FROM users WHERE id = ?");
        $stmt->bind_param("i", $userId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows > 0) {
            $row = $result->fetch_assoc();
            $current_used_volume = (int)$row['used_volume'];
            
            // Convert upload/download from bytes to MB and add to used_volume
            // Assuming upload and download are in bytes, and total_volume is in MB
            $upload_mb = $upload / (1024 * 1024);
            $download_mb = $download / (1024 * 1024);
            $new_used_volume = $current_used_volume + $upload_mb + $download_mb;

            $stmt->close(); // Close previous statement

            $stmt = $conn->prepare("UPDATE users SET used_volume = ? WHERE id = ?");
            $stmt->bind_param("di", $new_used_volume, $userId); // "d" for double (float)
            if ($stmt->execute()) {
                echo json_encode(["success" => true, "message" => "Traffic updated successfully."]);
            } else {
                echo json_encode(["success" => false, "message" => "Failed to update traffic: " . $stmt->error]);
            }
        } else {
            echo json_encode(["success" => false, "message" => "User not found for traffic update."]);
        }
        $stmt->close();
        break;

    case 'updateLoginStatus':
        $userId = $_POST['user_id'] ?? null;
        $isLoggedIn = $_POST['is_logged_in'] ?? null; // '1' or '0'
        $deviceName = $_POST['device_name'] ?? 'Unknown Device'; // دریافت نام دستگاه

        if (empty($userId) || !isset($isLoggedIn) || empty($deviceName)) {
            echo json_encode(["success" => false, "message" => "User ID, login status, and device name are required."]);
            break;
        }

        $currentTimestamp = date('Y-m-d H:i:s');
        
        // Update the specific device's login status
        $stmt = $conn->prepare("UPDATE logged_in_devices SET is_logged_in = ?, last_login = ? WHERE user_id = ? AND device_name = ?");
        $stmt->bind_param("isis", $isLoggedIn, $currentTimestamp, $userId, $deviceName); // "i" for int, "s" for string

        if ($stmt->execute()) {
            echo json_encode(["success" => true, "message" => "Login status updated successfully for device."]);
        } else {
            echo json_encode(["success" => false, "message" => "Failed to update login status for device: " . $stmt->error]);
        }
        $stmt->close();
        break;

    case 'getLoggedInDevices': // Added this case to handle the request
        $username = $_GET['username'] ?? null; 

        if (empty($username)) {
            echo json_encode(["success" => false, "message" => "Username is required."]);
            break;
        }

        // Fetch all logged-in devices for the given username
        $stmt = $conn->prepare("SELECT device_name, last_login, is_logged_in FROM logged_in_devices WHERE username = ?");
        $stmt->bind_param("s", $username);
        $stmt->execute();
        $result = $stmt->get_result();

        $devices = [];
        if ($result->num_rows > 0) {
            while ($row = $result->fetch_assoc()) {
                $devices[] = [
                    "device_name" => $row['device_name'],
                    "last_login" => $row['last_login'],
                    "is_logged_in" => (bool)$row['is_logged_in'],
                    "username" => $username // Add username to each device for consistency
                ];
            }
            echo json_encode([
                "success" => true,
                "message" => "Logged-in devices fetched successfully.",
                "devices" => $devices
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "No logged-in devices found for this user."]);
        }
        $stmt->close();
        break;

    default:
        echo json_encode(["success" => false, "message" => "عملیات نامعتبر."]);
        break;
}

$conn->close();
?>
