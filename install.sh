#!/bin/bash

# Script de instalación para Gestión de Empleados v2.2
# Sistema completamente corregido y mejorado

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_message() {
    echo -e "${BLUE}[GESTIÓN DE EMPLEADOS v2.2]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ÉXITO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Verificar root
if [ "$EUID" -ne 0 ]; then
    print_error "Ejecute como root: sudo ./instalacion_panel_v2.2.sh"
    exit 1
fi

# Detectar OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
else
    print_error "No se pudo detectar el SO"
    exit 1
fi

print_message "Iniciando instalación - Sistema: $OS"

# Configuración
read -p "¿Configurar dominio? (s/n): " setup_domain
if [[ $setup_domain == "s" || $setup_domain == "S" ]]; then
    read -p "Dominio (ej: midominio.com): " DOMAIN
else
    DOMAIN="localhost"
fi

read -p "¿Configurar Telegram ahora? (s/n): " setup_telegram
if [[ $setup_telegram == "s" || $setup_telegram == "S" ]]; then
    read -p "Token del bot de Telegram: " TELEGRAM_TOKEN
else
    TELEGRAM_TOKEN=""
fi

read -p "Usuario administrador pro: " ADMIN_USER
read -s -p "Contraseña administrador pro: " ADMIN_PASS
echo

# Actualizar sistema
print_message "Actualizando sistema..."
apt update && apt upgrade -y

# Instalar dependencias
print_message "Instalando dependencias..."
apt install -y apache2 php php-mysql php-curl php-gd php-mbstring php-xml php-zip mysql-server curl git unzip

# Configurar MySQL
print_message "Configurando MySQL..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';"
mysql -e "FLUSH PRIVILEGES;"

# Crear base de datos
print_message "Creando base de datos..."
mysql -e "CREATE DATABASE IF NOT EXISTS gestion_empleados;"
mysql -e "CREATE USER IF NOT EXISTS 'gestion_user'@'localhost' IDENTIFIED BY 'empleados123';"
mysql -e "GRANT ALL PRIVILEGES ON gestion_empleados.* TO 'gestion_user'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Crear directorio del panel
PANEL_DIR="/var/www/gestion-empleados"
print_message "Creando directorio: $PANEL_DIR"
mkdir -p $PANEL_DIR
cd $PANEL_DIR

# Crear estructura de base de datos mejorada
print_message "Creando estructura de base de datos..."
mysql gestion_empleados << 'EOF'
-- Tabla de usuarios mejorada
CREATE TABLE IF NOT EXISTS usuarios (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    telefono VARCHAR(20),
    rol ENUM('admin_pro', 'admin', 'empleado') NOT NULL DEFAULT 'empleado',
    telegram_id VARCHAR(50),
    turno ENUM('AM', 'PM') DEFAULT 'AM',
    pasillo_asignado VARCHAR(50),
    dia_libre VARCHAR(20),
    activo BOOLEAN DEFAULT TRUE,
    creado_por INT,
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (creado_por) REFERENCES usuarios(id)
);

-- Tabla de tareas mejorada
CREATE TABLE IF NOT EXISTS tareas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    descripcion TEXT,
    empleado_id INT NOT NULL,
    administrador_id INT NOT NULL,
    pasillo_area VARCHAR(100),
    tipo_tarea ENUM('pasillo', 'area') DEFAULT 'area',
    requiere_foto BOOLEAN DEFAULT FALSE,
    foto_tarea TEXT,
    fecha_asignacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    fecha_vencimiento DATETIME,
    fecha_completado DATETIME,
    estado ENUM('pendiente', 'completada', 'vencida', 'verificada') DEFAULT 'pendiente',
    calificacion INT,
    comentario_revision TEXT,
    tipo ENUM('manual', 'automatica') DEFAULT 'manual',
    notificar_telegram BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (empleado_id) REFERENCES usuarios(id),
    FOREIGN KEY (administrador_id) REFERENCES usuarios(id),
    INDEX idx_empleado_estado (empleado_id, estado),
    INDEX idx_fecha_vencimiento (fecha_vencimiento)
);

-- Tabla de configuraciones
CREATE TABLE IF NOT EXISTS configuraciones (
    id INT AUTO_INCREMENT PRIMARY KEY,
    clave VARCHAR(100) UNIQUE NOT NULL,
    valor TEXT,
    descripcion TEXT,
    fecha_actualizacion DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Tabla de backups
CREATE TABLE IF NOT EXISTS backups (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre_archivo VARCHAR(255),
    tamano BIGINT,
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    creado_por INT,
    ubicacion VARCHAR(500),
    FOREIGN KEY (creado_por) REFERENCES usuarios(id)
);

-- Tabla de logs del sistema
CREATE TABLE IF NOT EXISTS logs_sistema (
    id INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id INT,
    accion VARCHAR(255),
    detalles TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Tabla de temas
CREATE TABLE IF NOT EXISTS temas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    colores TEXT NOT NULL,
    activo BOOLEAN DEFAULT FALSE,
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insertar usuario admin pro por defecto
INSERT IGNORE INTO usuarios (username, password, nombre, rol, activo) 
VALUES ('admin', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Administrador Principal', 'admin_pro', TRUE);

-- Configuraciones por defecto
INSERT IGNORE INTO configuraciones (clave, valor, descripcion) VALUES 
('telegram_token', '', 'Token del bot de Telegram para notificaciones'),
('horario_am', '08:00', 'Horario para tareas automáticas AM'),
('horario_pm', '14:00', 'Horario para tareas automáticas PM'),
('dominio', '', 'Dominio del sistema'),
('version', '2.2', 'Versión del sistema'),
('backup_automatico', '1', 'Hacer backup automático diario'),
('hora_backup', '02:00', 'Hora para backup automático'),
('tareas_automaticas', '1', 'Activar tareas automáticas'),
('nombre_sistema', 'Sistema de Gestión de Empleados', 'Nombre del sistema'),
('tema_actual', 'default', 'Tema actual del sistema');

-- Insertar temas por defecto
INSERT IGNORE INTO temas (nombre, colores, activo) VALUES 
('default', '{"primary":"#1a5276","secondary":"#2c3e50","accent":"#e74c3c","background":"#0f1419","card_bg":"#1a1f2e","text":"#ecf0f1"}', TRUE),
('azul_moderno', '{"primary":"#2196F3","secondary":"#1976D2","accent":"#FF9800","background":"#121212","card_bg":"#1E1E1E","text":"#FFFFFF"}', FALSE),
('verde_fresco', '{"primary":"#4CAF50","secondary":"#388E3C","accent":"#FFC107","background":"#0A0A0A","card_bg":"#1A1A1A","text":"#E8F5E8"}', FALSE),
('purpura_elegante', '{"primary":"#9C27B0","secondary":"#7B1FA2","accent":"#00BCD4","background":"#141414","card_bg":"#2D1E33","text":"#F3E5F5"}', FALSE);
EOF

# Crear archivo de configuración mejorado
cat > config.php << 'EOF'
<?php
// Configuración de Gestión de Empleados v2.2
date_default_timezone_set('America/Santo_Domingo');

// Configuración de la base de datos
define('DB_HOST', 'localhost');
define('DB_NAME', 'gestion_empleados');
define('DB_USER', 'gestion_user');
define('DB_PASS', 'empleados123');

// Configuración del sistema
define('SITE_URL', (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http") . "://$_SERVER[HTTP_HOST]");
define('VERSION', '2.2');
define('MAX_FILE_SIZE', 50 * 1024 * 1024); // 50MB

// Obtener configuraciones de la base de datos
try {
    $pdo = new PDO("mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4", DB_USER, DB_PASS);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    
    // Cargar configuraciones
    $stmt = $pdo->query("SELECT clave, valor FROM configuraciones");
    $configs = $stmt->fetchAll(PDO::FETCH_KEY_PAIR);
    
    $telegram_config = [
        'token' => $configs['telegram_token'] ?? '',
        'webhook_url' => ''
    ];
    
    $horarios_tareas = [
        'am' => $configs['horario_am'] ?? '08:00',
        'pm' => $configs['horario_pm'] ?? '14:00'
    ];
    
    $nombre_sistema = $configs['nombre_sistema'] ?? 'Sistema de Gestión de Empleados';
    
    // Cargar tema actual
    $tema_actual = $configs['tema_actual'] ?? 'default';
    $stmt_tema = $pdo->prepare("SELECT colores FROM temas WHERE nombre = ?");
    $stmt_tema->execute([$tema_actual]);
    $tema = $stmt_tema->fetch();
    
    if ($tema) {
        $colores_tema = json_decode($tema['colores'], true);
    } else {
        // Tema por defecto
        $colores_tema = [
            'primary' => '#1a5276',
            'secondary' => '#2c3e50',
            'accent' => '#e74c3c',
            'background' => '#0f1419',
            'card_bg' => '#1a1f2e',
            'text' => '#ecf0f1'
        ];
    }
    
} catch(PDOException $e) {
    die("Error de conexión: " . $e->getMessage());
}

// Función para registrar logs
function registrar_log($usuario_id, $accion, $detalles = '') {
    global $pdo;
    
    try {
        $stmt = $pdo->prepare("INSERT INTO logs_sistema (usuario_id, accion, detalles, ip_address, user_agent) VALUES (?, ?, ?, ?, ?)");
        $stmt->execute([
            $usuario_id,
            $accion,
            $detalles,
            $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1',
            $_SERVER['HTTP_USER_AGENT'] ?? ''
        ]);
        return true;
    } catch(Exception $e) {
        error_log("Error registrando log: " . $e->getMessage());
        return false;
    }
}

// Función para enviar notificaciones a Telegram
function enviar_telegram($user_id, $mensaje, $parse_mode = 'HTML') {
    global $pdo, $telegram_config;
    
    if (empty($telegram_config['token'])) return false;
    
    try {
        $stmt = $pdo->prepare("SELECT telegram_id FROM usuarios WHERE id = ? AND telegram_id IS NOT NULL AND telegram_id != ''");
        $stmt->execute([$user_id]);
        $user = $stmt->fetch();
        
        if ($user && !empty($user['telegram_id'])) {
            $url = "https://api.telegram.org/bot" . $telegram_config['token'] . "/sendMessage";
            $data = [
                'chat_id' => $user['telegram_id'],
                'text' => $mensaje,
                'parse_mode' => $parse_mode
            ];
            
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            $result = curl_exec($ch);
            curl_close($ch);
            
            return $result;
        }
    } catch(Exception $e) {
        error_log("Error enviando Telegram: " . $e->getMessage());
    }
    
    return false;
}

// Función para verificar si un empleado está libre hoy
function empleado_esta_libre_hoy($empleado) {
    $dias_semana = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
    $dia_actual = $dias_semana[date('w')];
    
    return $empleado['dia_libre'] === $dia_actual;
}

// Función para obtener recomendaciones de patanas COMPLETAMENTE CORREGIDA
function obtener_recomendaciones_patanas() {
    global $pdo;
    
    try {
        // Obtener todos los empleados activos
        $stmt_empleados = $pdo->query("SELECT * FROM usuarios WHERE activo = TRUE AND rol = 'empleado'");
        $todos_empleados = $stmt_empleados->fetchAll();
        
        // Identificar empleados libres hoy
        $empleados_libres = [];
        $empleados_trabajando = [];
        
        foreach ($todos_empleados as $empleado) {
            if (empleado_esta_libre_hoy($empleado)) {
                $empleados_libres[] = $empleado;
            } else {
                $empleados_trabajando[] = $empleado;
            }
        }
        
        // Obtener pasillos de empleados que están trabajando hoy
        $pasillos_ocupados = [];
        foreach ($empleados_trabajando as $emp) {
            if (!empty($emp['pasillo_asignado'])) {
                $pasillos_ocupados[] = $emp['pasillo_asignado'];
            }
        }
        
        // Obtener pasillos de empleados libres (estos son los que necesitan cobertura)
        $pasillos_sin_cobertura = [];
        foreach ($empleados_libres as $emp) {
            if (!empty($emp['pasillo_asignado']) && !in_array($emp['pasillo_asignado'], $pasillos_ocupados)) {
                $pasillos_sin_cobertura[] = $emp['pasillo_asignado'];
            }
        }
        
        // Filtrar empleados trabajando por turno actual
        $turno_actual = date('H') < 12 ? 'AM' : 'PM';
        $empleados_disponibles = array_filter($empleados_trabajando, function($emp) use ($turno_actual) {
            return $emp['turno'] === $turno_actual;
        });
        
        // Verificar si ya hay tareas asignadas para cubrir estos pasillos hoy
        $fecha_hoy = date('Y-m-d');
        $pasillos_ya_cubiertos = [];
        
        if (!empty($pasillos_sin_cobertura)) {
            $placeholders = str_repeat('?,', count($pasillos_sin_cobertura) - 1) . '?';
            $stmt_tareas = $pdo->prepare("
                SELECT DISTINCT pasillo_area 
                FROM tareas 
                WHERE pasillo_area IN ($placeholders) 
                AND DATE(fecha_asignacion) = ? 
                AND estado IN ('pendiente', 'completada')
            ");
            $params = array_merge($pasillos_sin_cobertura, [$fecha_hoy]);
            $stmt_tareas->execute($params);
            $pasillos_ya_cubiertos = $stmt_tareas->fetchAll(PDO::FETCH_COLUMN);
        }
        
        // Filtrar pasillos que realmente necesitan cobertura (no están ya cubiertos)
        $pasillos_necesitan_cobertura = array_diff($pasillos_sin_cobertura, $pasillos_ya_cubiertos);
        
        $recomendaciones = [];
        
        if (count($pasillos_necesitan_cobertura) > 0 && count($empleados_disponibles) > 0) {
            $recomendaciones = [
                'empleados_libres' => $empleados_libres,
                'empleados_disponibles' => array_values($empleados_disponibles),
                'pasillos_sin_cobertura' => array_values($pasillos_necesitan_cobertura),
                'pasillos_ya_cubiertos' => $pasillos_ya_cubiertos,
                'turno_actual' => $turno_actual,
                'mensaje' => 'Se detectaron ' . count($pasillos_necesitan_cobertura) . ' pasillos sin cobertura en turno ' . $turno_actual
            ];
        }
        
        return $recomendaciones;
    } catch(Exception $e) {
        error_log("Error obteniendo recomendaciones: " . $e->getMessage());
        return [];
    }
}

// Función para obtener estadísticas de empleados por turno
function obtener_estadisticas_turno($turno) {
    global $pdo;
    
    try {
        $dias_semana = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
        $dia_actual = $dias_semana[date('w')];
        
        $stmt = $pdo->prepare("
            SELECT COUNT(*) as total 
            FROM usuarios 
            WHERE activo = TRUE 
            AND rol = 'empleado' 
            AND turno = ?
            AND dia_libre != ?
        ");
        $stmt->execute([$turno, $dia_actual]);
        $result = $stmt->fetch();
        
        return $result['total'] ?? 0;
    } catch(Exception $e) {
        error_log("Error obteniendo estadísticas: " . $e->getMessage());
        return 0;
    }
}

// Función para generar backup mejorada
function generar_backup($usuario_id) {
    global $pdo;
    
    $fecha = date('Y-m-d_H-i-s');
    $nombre_archivo = "backup_gestion_$fecha.sql";
    $backup_dir = "/var/www/backups";
    $ruta_backup = "$backup_dir/$nombre_archivo";
    
    // Crear directorio de backups si no existe
    if (!is_dir($backup_dir)) {
        if (!mkdir($backup_dir, 0755, true)) {
            return ['success' => false, 'error' => 'No se pudo crear directorio de backups'];
        }
    }
    
    // Verificar permisos
    if (!is_writable($backup_dir)) {
        return ['success' => false, 'error' => 'Directorio de backups sin permisos de escritura'];
    }
    
    // Generar backup de la base de datos
    $command = "mysqldump -h " . DB_HOST . " -u " . DB_USER . " -p'" . DB_PASS . "' " . DB_NAME . " 2>&1";
    $output = [];
    $return_var = 0;
    exec($command, $output, $return_var);
    
    if ($return_var === 0) {
        $backup_content = implode("\n", $output);
        
        if (file_put_contents($ruta_backup, $backup_content) !== false) {
            $tamano = filesize($ruta_backup);
            
            // Registrar en la base de datos
            $stmt = $pdo->prepare("INSERT INTO backups (nombre_archivo, tamano, creado_por, ubicacion) VALUES (?, ?, ?, ?)");
            $stmt->execute([$nombre_archivo, $tamano, $usuario_id, $ruta_backup]);
            
            registrar_log($usuario_id, 'BACKUP_GENERADO', "Backup: $nombre_archivo, Tamaño: " . round($tamano/1024/1024, 2) . "MB");
            
            return ['success' => true, 'archivo' => $ruta_backup, 'nombre' => $nombre_archivo, 'tamano' => $tamano];
        } else {
            return ['success' => false, 'error' => 'Error al escribir archivo de backup'];
        }
    } else {
        $error_msg = implode("\n", $output);
        return ['success' => false, 'error' => 'Error en mysqldump: ' . $error_msg];
    }
}

// Función para descargar backup
function descargar_backup($backup_id, $usuario_id) {
    global $pdo;
    
    try {
        $stmt = $pdo->prepare("SELECT * FROM backups WHERE id = ?");
        $stmt->execute([$backup_id]);
        $backup = $stmt->fetch();
        
        if ($backup && file_exists($backup['ubicacion'])) {
            // Forzar descarga del archivo
            header('Content-Type: application/octet-stream');
            header('Content-Disposition: attachment; filename="' . $backup['nombre_archivo'] . '"');
            header('Content-Length: ' . $backup['tamano']);
            readfile($backup['ubicacion']);
            exit;
        } else {
            return ['success' => false, 'error' => 'Backup no encontrado'];
        }
    } catch(Exception $e) {
        return ['success' => false, 'error' => $e->getMessage()];
    }
}

// Función para subir backup
function subir_backup($file, $usuario_id) {
    global $pdo;
    
    $upload_dir = '/var/www/backups/';
    $allowed_types = ['application/sql', 'text/plain', 'application/octet-stream'];
    
    // Verificar tipo de archivo
    $file_type = mime_content_type($file['tmp_name']);
    if (!in_array($file_type, $allowed_types)) {
        return ['success' => false, 'error' => 'Tipo de archivo no permitido. Solo se permiten archivos SQL.'];
    }
    
    // Verificar extensión
    $extension = pathinfo($file['name'], PATHINFO_EXTENSION);
    if (strtolower($extension) !== 'sql') {
        return ['success' => false, 'error' => 'Solo se permiten archivos con extensión .sql'];
    }
    
    // Generar nombre único
    $nombre_archivo = "backup_subido_" . date('Y-m-d_H-i-s') . ".sql";
    $ruta_completa = $upload_dir . $nombre_archivo;
    
    if (move_uploaded_file($file['tmp_name'], $ruta_completa)) {
        // Registrar en la base de datos
        $tamano = filesize($ruta_completa);
        $stmt = $pdo->prepare("INSERT INTO backups (nombre_archivo, tamano, creado_por, ubicacion) VALUES (?, ?, ?, ?)");
        $stmt->execute([$nombre_archivo, $tamano, $usuario_id, $ruta_completa]);
        
        registrar_log($usuario_id, 'BACKUP_SUBIDO', "Backup: $nombre_archivo, Tamaño: " . round($tamano/1024/1024, 2) . "MB");
        
        return ['success' => true, 'archivo' => $ruta_completa, 'nombre' => $nombre_archivo];
    } else {
        return ['success' => false, 'error' => 'Error al subir archivo'];
    }
}

// Función para capturar foto desde la cámara
function capturar_foto_camara($image_data, $tarea_id, $usuario_id) {
    $upload_dir = '/var/www/uploads/tareas/';
    
    // Crear directorio si no existe
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0755, true);
    }
    
    // Convertir data URL a imagen
    $image_data = str_replace('data:image/png;base64,', '', $image_data);
    $image_data = str_replace(' ', '+', $image_data);
    $image_data = base64_decode($image_data);
    
    $nombre_archivo = "tarea_{$tarea_id}_" . time() . ".png";
    $ruta_completa = $upload_dir . $nombre_archivo;
    
    if (file_put_contents($ruta_completa, $image_data)) {
        return ['success' => true, 'ruta' => $ruta_completa, 'nombre' => $nombre_archivo];
    } else {
        return ['success' => false, 'error' => 'Error al guardar imagen'];
    }
}

// Función para asignar tareas automáticas de montacarga
function asignar_tareas_montacarga($turno) {
    global $pdo;
    
    try {
        // Obtener empleados del turno especificado que no estén libres hoy
        $stmt = $pdo->prepare("
            SELECT * FROM usuarios 
            WHERE turno = ? AND activo = TRUE AND rol = 'empleado' 
            AND dia_libre != ? 
            ORDER BY RAND() LIMIT 2
        ");
        
        $dias_semana = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
        $dia_actual = $dias_semana[date('w')];
        
        $stmt->execute([$turno, $dia_actual]);
        $empleados_montacarga = $stmt->fetchAll();
        
        if (count($empleados_montacarga) == 2) {
            // Asignar tarea de montacarga arriba
            $titulo_arriba = "Montacarga - Posición Superior";
            $descripcion_arriba = "Quedarse en la posición superior del montacarga durante el turno " . $turno;
            
            $stmt_tarea = $pdo->prepare("INSERT INTO tareas (titulo, descripcion, empleado_id, administrador_id, tipo, notificar_telegram) VALUES (?, ?, ?, 1, 'automatica', TRUE)");
            $stmt_tarea->execute([$titulo_arriba, $descripcion_arriba, $empleados_montacarga[0]['id']]);
            
            // Asignar tarea de montacarga abajo
            $titulo_abajo = "Montacarga - Posición Inferior";
            $descripcion_abajo = "Trabajar en la posición inferior del almacén durante el turno " . $turno;
            
            $stmt_tarea = $pdo->prepare("INSERT INTO tareas (titulo, descripcion, empleado_id, administrador_id, tipo, notificar_telegram) VALUES (?, ?, ?, 1, 'automatica', TRUE)");
            $stmt_tarea->execute([$titulo_abajo, $descripcion_abajo, $empleados_montacarga[1]['id']]);
            
            // Enviar notificaciones por Telegram
            foreach ($empleados_montacarga as $index => $empleado) {
                $posicion = $index == 0 ? "superior (arriba)" : "inferior (abajo)";
                $mensaje = "🚜 <b>ASIGNACIÓN MONTACARGA - Turno " . $turno . "</b>\n\n";
                $mensaje .= "👤 <b>Empleado:</b> " . $empleado['nombre'] . "\n";
                $mensaje .= "📍 <b>Posición:</b> " . $posicion . "\n";
                $mensaje .= "⏰ <b>Turno:</b> " . $turno . "\n";
                $mensaje .= "📋 <b>Tarea:</b> " . ($index == 0 ? $titulo_arriba : $titulo_abajo) . "\n";
                $mensaje .= "📖 <b>Descripción:</b> " . ($index == 0 ? $descripcion_arriba : $descripcion_abajo) . "\n\n";
                $mensaje .= "✅ <b>Por favor confirmar recepción</b>";
                
                enviar_telegram($empleado['id'], $mensaje);
            }
            
            return ['success' => true, 'empleados' => $empleados_montacarga];
        }
        
        return ['success' => false, 'error' => 'No hay suficientes empleados para asignar tareas de montacarga'];
    } catch(Exception $e) {
        error_log("Error asignando tareas montacarga: " . $e->getMessage());
        return ['success' => false, 'error' => $e->getMessage()];
    }
}

// Función para cambiar tema
function cambiar_tema($tema_nombre, $usuario_id) {
    global $pdo;
    
    try {
        // Verificar que el tema existe
        $stmt = $pdo->prepare("SELECT nombre FROM temas WHERE nombre = ?");
        $stmt->execute([$tema_nombre]);
        $tema = $stmt->fetch();
        
        if ($tema) {
            // Actualizar configuración
            $stmt = $pdo->prepare("INSERT INTO configuraciones (clave, valor) VALUES ('tema_actual', ?) ON DUPLICATE KEY UPDATE valor = ?");
            $stmt->execute([$tema_nombre, $tema_nombre]);
            
            registrar_log($usuario_id, 'TEMA_CAMBIADO', "Tema: $tema_nombre");
            return ['success' => true];
        } else {
            return ['success' => false, 'error' => 'Tema no encontrado'];
        }
    } catch(Exception $e) {
        return ['success' => false, 'error' => $e->getMessage()];
    }
}
?>
EOF

# Crear página de login mejorada con diseño moderno
cat > index.php << 'EOF'
<?php
require_once 'config.php';
session_start();

if (isset($_SESSION['usuario_id'])) {
    header('Location: panel.php');
    exit;
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    try {
        $stmt = $pdo->prepare("SELECT * FROM usuarios WHERE username = ? AND activo = TRUE");
        $stmt->execute([$username]);
        $usuario = $stmt->fetch();
        
        if ($usuario && password_verify($password, $usuario['password'])) {
            $_SESSION['usuario_id'] = $usuario['id'];
            $_SESSION['username'] = $usuario['username'];
            $_SESSION['rol'] = $usuario['rol'];
            $_SESSION['nombre'] = $usuario['nombre'];
            
            registrar_log($usuario['id'], 'LOGIN_EXITOSO');
            
            header('Location: panel.php');
            exit;
        } else {
            $error = 'Usuario o contraseña incorrectos';
            registrar_log(null, 'LOGIN_FALLIDO', "Usuario: $username");
        }
    } catch(Exception $e) {
        $error = 'Error al iniciar sesión';
    }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo htmlspecialchars($nombre_sistema); ?> - Login</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, <?php echo $colores_tema['primary']; ?>, <?php echo $colores_tema['secondary']; ?>);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .login-container {
            background: <?php echo $colores_tema['card_bg']; ?>;
            padding: 50px 40px;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
            width: 100%;
            max-width: 450px;
            border: 1px solid <?php echo $colores_tema['primary']; ?>;
            position: relative;
            overflow: hidden;
        }
        
        .login-container::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
            background: linear-gradient(90deg, <?php echo $colores_tema['primary']; ?>, <?php echo $colores_tema['secondary']; ?>);
        }
        
        .logo {
            text-align: center;
            margin-bottom: 40px;
        }
        
        .logo-icon {
            font-size: 48px;
            color: <?php echo $colores_tema['primary']; ?>;
            margin-bottom: 15px;
            display: block;
        }
        
        .logo h1 {
            color: <?php echo $colores_tema['text']; ?>;
            font-size: 28px;
            font-weight: 600;
            letter-spacing: 1px;
        }
        
        .logo p {
            color: #95a5a6;
            font-size: 14px;
            margin-top: 5px;
        }
        
        .form-group {
            margin-bottom: 25px;
            position: relative;
        }
        
        .form-group label {
            display: block;
            color: <?php echo $colores_tema['text']; ?>;
            margin-bottom: 8px;
            font-weight: 500;
            font-size: 14px;
        }
        
        .form-group input {
            width: 100%;
            padding: 15px 20px;
            background: <?php echo $colores_tema['secondary']; ?>;
            border: 2px solid #34495e;
            border-radius: 10px;
            color: <?php echo $colores_tema['text']; ?>;
            font-size: 16px;
            transition: all 0.3s ease;
        }
        
        .form-group input:focus {
            outline: none;
            border-color: <?php echo $colores_tema['primary']; ?>;
            box-shadow: 0 0 0 3px rgba(26, 82, 118, 0.2);
            background: #34495e;
        }
        
        .btn-login {
            width: 100%;
            padding: 15px;
            background: linear-gradient(135deg, <?php echo $colores_tema['primary']; ?>, <?php echo $colores_tema['secondary']; ?>);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }
        
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(26, 82, 118, 0.3);
        }
        
        .btn-login:active {
            transform: translateY(0);
        }
        
        .error {
            background: rgba(231, 76, 60, 0.1);
            color: #e74c3c;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 25px;
            text-align: center;
            font-size: 14px;
            border: 1px solid rgba(231, 76, 60, 0.3);
        }
        
        .version {
            text-align: center;
            margin-top: 30px;
            color: #7f8c8d;
            font-size: 12px;
        }
        
        @media (max-width: 480px) {
            .login-container {
                padding: 30px 25px;
                margin: 10px;
            }
            
            .logo h1 {
                font-size: 24px;
            }
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="logo">
            <i class="fas fa-users-cog logo-icon"></i>
            <h1><?php echo htmlspecialchars($nombre_sistema); ?></h1>
            <p>v2.2</p>
        </div>
        
        <?php if ($error): ?>
            <div class="error">
                <i class="fas fa-exclamation-circle"></i> <?php echo htmlspecialchars($error); ?>
            </div>
        <?php endif; ?>
        
        <form method="POST" action="">
            <div class="form-group">
                <label for="username"><i class="fas fa-user"></i> Usuario</label>
                <input type="text" id="username" name="username" required placeholder="Ingrese su usuario">
            </div>
            
            <div class="form-group">
                <label for="password"><i class="fas fa-lock"></i> Contraseña</label>
                <input type="password" id="password" name="password" required placeholder="Ingrese su contraseña">
            </div>
            
            <button type="submit" class="btn-login">
                <i class="fas fa-sign-in-alt"></i> Iniciar Sesión
            </button>
        </form>
        
        <div class="version">
            Sistema de Gestión v2.2 - Completamente Corregido
        </div>
    </div>
</body>
</html>
EOF

# Crear archivo de logout
cat > logout.php << 'EOF'
<?php
require_once 'config.php';
session_start();

if (isset($_SESSION['usuario_id'])) {
    registrar_log($_SESSION['usuario_id'], 'LOGOUT');
}

session_destroy();
session_unset();

header('Location: index.php');
exit;
?>
EOF

# Crear panel principal completamente mejorado y corregido
cat > panel.php << 'EOF'
<?php
require_once 'config.php';
session_start();

if (!isset($_SESSION['usuario_id'])) {
    header('Location: index.php');
    exit;
}

$usuario_id = $_SESSION['usuario_id'];
$stmt = $pdo->prepare("SELECT * FROM usuarios WHERE id = ?");
$stmt->execute([$usuario_id]);
$usuario_actual = $stmt->fetch();

// Procesar acciones
$mensaje = '';
$tipo_mensaje = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $accion = $_POST['accion'] ?? '';
    
    switch ($accion) {
        case 'crear_usuario':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $username = $_POST['username'] ?? '';
                $password = password_hash($_POST['password'], PASSWORD_DEFAULT);
                $nombre = $_POST['nombre'] ?? '';
                $rol = $_POST['rol'] ?? 'empleado';
                $telegram_id = $_POST['telegram_id'] ?? '';
                $turno = $_POST['turno'] ?? 'AM';
                $pasillo = $_POST['pasillo'] ?? '';
                $dia_libre = $_POST['dia_libre'] ?? '';
                
                try {
                    $stmt = $pdo->prepare("INSERT INTO usuarios (username, password, nombre, rol, telegram_id, turno, pasillo_asignado, dia_libre, creado_por) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
                    $stmt->execute([$username, $password, $nombre, $rol, $telegram_id, $turno, $pasillo, $dia_libre, $usuario_id]);
                    
                    $mensaje = 'Usuario creado exitosamente';
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'USUARIO_CREADO', "Usuario: $username, Rol: $rol");
                } catch(Exception $e) {
                    $mensaje = 'Error al crear usuario: ' . $e->getMessage();
                    $tipo_mensaje = 'error';
                }
            }
            break;
            
        case 'editar_usuario':
            $user_id = $_POST['user_id'] ?? '';
            $nombre = $_POST['nombre'] ?? '';
            $telegram_id = $_POST['telegram_id'] ?? '';
            $turno = $_POST['turno'] ?? '';
            $pasillo = $_POST['pasillo'] ?? '';
            $dia_libre = $_POST['dia_libre'] ?? '';
            
            try {
                // Si es admin puede editar cualquier usuario, si es empleado solo puede editar su propio perfil
                if ($usuario_actual['rol'] === 'empleado' && $user_id != $usuario_id) {
                    $mensaje = 'No tienes permisos para editar este usuario';
                    $tipo_mensaje = 'error';
                } else {
                    if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                        $stmt = $pdo->prepare("UPDATE usuarios SET nombre = ?, telegram_id = ?, turno = ?, pasillo_asignado = ?, dia_libre = ? WHERE id = ?");
                        $stmt->execute([$nombre, $telegram_id, $turno, $pasillo, $dia_libre, $user_id]);
                    } else {
                        // Empleados solo pueden cambiar telegram_id
                        $stmt = $pdo->prepare("UPDATE usuarios SET telegram_id = ? WHERE id = ?");
                        $stmt->execute([$telegram_id, $user_id]);
                    }
                    
                    $mensaje = 'Usuario actualizado exitosamente';
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'USUARIO_EDITADO', "Usuario ID: $user_id");
                }
            } catch(Exception $e) {
                $mensaje = 'Error al editar usuario: ' . $e->getMessage();
                $tipo_mensaje = 'error';
            }
            break;
            
        case 'eliminar_usuario':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $user_id = $_POST['user_id'] ?? '';
                
                try {
                    // No permitir eliminar al propio usuario o admin_pro
                    if ($user_id == $usuario_id) {
                        $mensaje = 'No puedes eliminar tu propio usuario';
                        $tipo_mensaje = 'error';
                    } else {
                        $stmt = $pdo->prepare("SELECT rol FROM usuarios WHERE id = ?");
                        $stmt->execute([$user_id]);
                        $user = $stmt->fetch();
                        
                        if ($user && $user['rol'] === 'admin_pro' && $usuario_actual['rol'] !== 'admin_pro') {
                            $mensaje = 'No tienes permisos para eliminar un administrador pro';
                            $tipo_mensaje = 'error';
                        } else {
                            $stmt = $pdo->prepare("UPDATE usuarios SET activo = FALSE WHERE id = ?");
                            $stmt->execute([$user_id]);
                            
                            $mensaje = 'Usuario eliminado exitosamente';
                            $tipo_mensaje = 'success';
                            registrar_log($usuario_id, 'USUARIO_ELIMINADO', "Usuario ID: $user_id");
                        }
                    }
                } catch(Exception $e) {
                    $mensaje = 'Error al eliminar usuario: ' . $e->getMessage();
                    $tipo_mensaje = 'error';
                }
            }
            break;
            
        case 'cambiar_password':
            $user_id = $_POST['user_id'] ?? '';
            $nueva_password = $_POST['nueva_password'] ?? '';
            
            try {
                // Si es admin puede cambiar cualquier password, si es empleado solo puede cambiar la suya
                if ($usuario_actual['rol'] === 'empleado' && $user_id != $usuario_id) {
                    $mensaje = 'No tienes permisos para cambiar esta contraseña';
                    $tipo_mensaje = 'error';
                } else {
                    $password_hash = password_hash($nueva_password, PASSWORD_DEFAULT);
                    $stmt = $pdo->prepare("UPDATE usuarios SET password = ? WHERE id = ?");
                    $stmt->execute([$password_hash, $user_id]);
                    
                    $mensaje = 'Contraseña actualizada exitosamente';
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'PASSWORD_CAMBIADA', "Usuario ID: $user_id");
                }
            } catch(Exception $e) {
                $mensaje = 'Error al cambiar contraseña: ' . $e->getMessage();
                $tipo_mensaje = 'error';
            }
            break;
            
        case 'asignar_tarea':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $empleado_id = $_POST['empleado_id'] ?? '';
                $titulo = $_POST['titulo'] ?? '';
                $descripcion = $_POST['descripcion'] ?? '';
                $fecha_vencimiento = $_POST['fecha_vencimiento'] ?? '';
                $requiere_foto = isset($_POST['requiere_foto']) ? 1 : 0;
                $notificar_telegram = isset($_POST['notificar_telegram']) ? 1 : 0;
                
                // CORRECCIÓN: Verificar si es asignación múltiple
                if (is_array($empleado_id)) {
                    $tareas_asignadas = 0;
                    foreach ($empleado_id as $emp_id) {
                        try {
                            $stmt = $pdo->prepare("INSERT INTO tareas (titulo, descripcion, empleado_id, administrador_id, requiere_foto, fecha_vencimiento, notificar_telegram) VALUES (?, ?, ?, ?, ?, ?, ?)");
                            $stmt->execute([$titulo, $descripcion, $emp_id, $usuario_id, $requiere_foto, $fecha_vencimiento, $notificar_telegram]);
                            $tarea_id = $pdo->lastInsertId();
                            $tareas_asignadas++;
                            
                            // Notificar por Telegram si está activado
                            if ($notificar_telegram) {
                                $stmt_emp = $pdo->prepare("SELECT nombre, telegram_id FROM usuarios WHERE id = ?");
                                $stmt_emp->execute([$emp_id]);
                                $empleado = $stmt_emp->fetch();
                                
                                if ($empleado) {
                                    $mensaje_telegram = "📋 <b>NUEVA TAREA ASIGNADA</b>\n\n";
                                    $mensaje_telegram .= "👤 <b>Para:</b> " . $empleado['nombre'] . "\n";
                                    $mensaje_telegram .= "📝 <b>Tarea:</b> " . $titulo . "\n";
                                    $mensaje_telegram .= "📖 <b>Descripción:</b> " . $descripcion . "\n";
                                    
                                    if ($fecha_vencimiento) {
                                        $mensaje_telegram .= "⏰ <b>Vence:</b> " . date('d/m/Y H:i', strtotime($fecha_vencimiento)) . "\n";
                                    }
                                    
                                    if ($requiere_foto) {
                                        $mensaje_telegram .= "📸 <b>Requiere foto de evidencia</b>\n";
                                    }
                                    
                                    enviar_telegram($emp_id, $mensaje_telegram);
                                }
                            }
                            
                        } catch(Exception $e) {
                            // Continuar con el siguiente empleado
                            error_log("Error asignando tarea a empleado $emp_id: " . $e->getMessage());
                        }
                    }
                    $mensaje = "Tarea asignada a $tareas_asignadas empleados exitosamente";
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'TAREA_MULTIPLE_ASIGNADA', "Tarea: $titulo, Empleados: $tareas_asignadas");
                } else {
                    // Asignación individual
                    try {
                        $stmt = $pdo->prepare("INSERT INTO tareas (titulo, descripcion, empleado_id, administrador_id, requiere_foto, fecha_vencimiento, notificar_telegram) VALUES (?, ?, ?, ?, ?, ?, ?)");
                        $stmt->execute([$titulo, $descripcion, $empleado_id, $usuario_id, $requiere_foto, $fecha_vencimiento, $notificar_telegram]);
                        $tarea_id = $pdo->lastInsertId();
                        
                        // Notificar por Telegram si está activado
                        if ($notificar_telegram) {
                            $stmt_emp = $pdo->prepare("SELECT nombre, telegram_id FROM usuarios WHERE id = ?");
                            $stmt_emp->execute([$empleado_id]);
                            $empleado = $stmt_emp->fetch();
                            
                            if ($empleado) {
                                $mensaje_telegram = "📋 <b>NUEVA TAREA ASIGNADA</b>\n\n";
                                $mensaje_telegram .= "👤 <b>Para:</b> " . $empleado['nombre'] . "\n";
                                $mensaje_telegram .= "📝 <b>Tarea:</b> " . $titulo . "\n";
                                $mensaje_telegram .= "📖 <b>Descripción:</b> " . $descripcion . "\n";
                                
                                if ($fecha_vencimiento) {
                                    $mensaje_telegram .= "⏰ <b>Vence:</b> " . date('d/m/Y H:i', strtotime($fecha_vencimiento)) . "\n";
                                }
                                
                                if ($requiere_foto) {
                                    $mensaje_telegram .= "📸 <b>Requiere foto de evidencia</b>\n";
                                }
                                
                                enviar_telegram($empleado_id, $mensaje_telegram);
                            }
                        }
                        
                        $mensaje = 'Tarea asignada exitosamente';
                        $tipo_mensaje = 'success';
                        registrar_log($usuario_id, 'TAREA_ASIGNADA', "Tarea: $titulo, Empleado ID: $empleado_id");
                    } catch(Exception $e) {
                        $mensaje = 'Error al asignar tarea: ' . $e->getMessage();
                        $tipo_mensaje = 'error';
                    }
                }
            }
            break;
            
        case 'completar_tarea':
            $tarea_id = $_POST['tarea_id'] ?? '';
            $foto_data = $_POST['foto_data'] ?? '';
            
            try {
                // Verificar que la tarea pertenece al empleado
                $stmt = $pdo->prepare("SELECT * FROM tareas WHERE id = ? AND empleado_id = ?");
                $stmt->execute([$tarea_id, $usuario_id]);
                $tarea = $stmt->fetch();
                
                if ($tarea) {
                    $foto_tarea = '';
                    $foto_nombre = '';
                    
                    // Procesar foto si se capturó
                    if (!empty($foto_data)) {
                        $resultado_foto = capturar_foto_camara($foto_data, $tarea_id, $usuario_id);
                        if ($resultado_foto['success']) {
                            $foto_tarea = $resultado_foto['ruta'];
                            $foto_nombre = $resultado_foto['nombre'];
                            
                            // Notificar al administrador que asignó la tarea CON LA FOTO
                            $mensaje_telegram = "📸 <b>TAREA COMPLETADA CON FOTO</b>\n\n";
                            $mensaje_telegram .= "👤 <b>Empleado:</b> " . $usuario_actual['nombre'] . "\n";
                            $mensaje_telegram .= "📝 <b>Tarea:</b> " . $tarea['titulo'] . "\n";
                            $mensaje_telegram .= "✅ <b>Estado:</b> Completada\n";
                            $mensaje_telegram .= "⏰ <b>Completada:</b> " . date('d/m/Y H:i:s') . "\n\n";
                            $mensaje_telegram .= "📎 <b>Se adjuntó foto de evidencia</b>";
                            
                            enviar_telegram($tarea['administrador_id'], $mensaje_telegram);
                        }
                    } else {
                        // Notificar sin foto
                        $mensaje_telegram = "✅ <b>TAREA COMPLETADA</b>\n\n";
                        $mensaje_telegram .= "👤 <b>Empleado:</b> " . $usuario_actual['nombre'] . "\n";
                        $mensaje_telegram .= "📝 <b>Tarea:</b> " . $tarea['titulo'] . "\n";
                        $mensaje_telegram .= "⏰ <b>Completada:</b> " . date('d/m/Y H:i:s');
                        
                        enviar_telegram($tarea['administrador_id'], $mensaje_telegram);
                    }
                    
                    $stmt = $pdo->prepare("UPDATE tareas SET estado = 'completada', fecha_completado = NOW(), foto_tarea = ? WHERE id = ?");
                    $stmt->execute([$foto_tarea, $tarea_id]);
                    
                    $mensaje = 'Tarea completada exitosamente';
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'TAREA_COMPLETADA', "Tarea ID: $tarea_id");
                } else {
                    $mensaje = 'Tarea no encontrada';
                    $tipo_mensaje = 'error';
                }
            } catch(Exception $e) {
                $mensaje = 'Error al completar tarea: ' . $e->getMessage();
                $tipo_mensaje = 'error';
            }
            break;
            
        case 'verificar_tarea':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $tarea_id = $_POST['tarea_id'] ?? '';
                $calificacion = $_POST['calificacion'] ?? '';
                $comentario = $_POST['comentario'] ?? '';
                
                try {
                    $stmt = $pdo->prepare("UPDATE tareas SET estado = 'verificada', calificacion = ?, comentario_revision = ? WHERE id = ?");
                    $stmt->execute([$calificacion, $comentario, $tarea_id]);
                    
                    // Obtener información de la tarea para notificación
                    $stmt_tarea = $pdo->prepare("SELECT t.*, u.nombre as empleado_nombre FROM tareas t JOIN usuarios u ON t.empleado_id = u.id WHERE t.id = ?");
                    $stmt_tarea->execute([$tarea_id]);
                    $tarea = $stmt_tarea->fetch();
                    
                    if ($tarea) {
                        // Notificar al empleado sobre la verificación
                        $mensaje_telegram = "⭐ <b>TAREA VERIFICADA</b>\n\n";
                        $mensaje_telegram .= "👤 <b>Empleado:</b> " . $tarea['empleado_nombre'] . "\n";
                        $mensaje_telegram .= "📝 <b>Tarea:</b> " . $tarea['titulo'] . "\n";
                        $mensaje_telegram .= "⭐ <b>Calificación:</b> " . str_repeat('★', $calificacion) . "\n";
                        
                        if (!empty($comentario)) {
                            $mensaje_telegram .= "💬 <b>Comentario:</b> " . $comentario . "\n";
                        }
                        
                        $mensaje_telegram .= "✅ <b>Estado:</b> Verificada y finalizada";
                        
                        enviar_telegram($tarea['empleado_id'], $mensaje_telegram);
                    }
                    
                    $mensaje = 'Tarea verificada exitosamente';
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'TAREA_VERIFICADA', "Tarea ID: $tarea_id, Calificación: $calificacion");
                } catch(Exception $e) {
                    $mensaje = 'Error al verificar tarea: ' . $e->getMessage();
                    $tipo_mensaje = 'error';
                }
            }
            break;
            
        case 'configurar_sistema':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $telegram_token = $_POST['telegram_token'] ?? '';
                $horario_am = $_POST['horario_am'] ?? '';
                $horario_pm = $_POST['horario_pm'] ?? '';
                $hora_backup = $_POST['hora_backup'] ?? '';
                $nombre_sistema = $_POST['nombre_sistema'] ?? '';
                $backup_automatico = isset($_POST['backup_automatico']) ? 1 : 0;
                $tareas_automaticas = isset($_POST['tareas_automaticas']) ? 1 : 0;
                
                try {
                    // Actualizar configuraciones
                    $configs = [
                        'telegram_token' => $telegram_token,
                        'horario_am' => $horario_am,
                        'horario_pm' => $horario_pm,
                        'hora_backup' => $hora_backup,
                        'nombre_sistema' => $nombre_sistema,
                        'backup_automatico' => $backup_automatico,
                        'tareas_automaticas' => $tareas_automaticas
                    ];
                    
                    foreach ($configs as $clave => $valor) {
                        $stmt = $pdo->prepare("INSERT INTO configuraciones (clave, valor) VALUES (?, ?) ON DUPLICATE KEY UPDATE valor = ?");
                        $stmt->execute([$clave, $valor, $valor]);
                    }
                    
                    $mensaje = 'Configuración actualizada exitosamente';
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'CONFIGURACION_ACTUALIZADA', "Configuraciones del sistema");
                } catch(Exception $e) {
                    $mensaje = 'Error al actualizar configuración: ' . $e->getMessage();
                    $tipo_mensaje = 'error';
                }
            }
            break;
            
        case 'cambiar_tema':
            $tema_nombre = $_POST['tema_nombre'] ?? '';
            $resultado = cambiar_tema($tema_nombre, $usuario_id);
            
            if ($resultado['success']) {
                $mensaje = 'Tema cambiado exitosamente';
                $tipo_mensaje = 'success';
            } else {
                $mensaje = 'Error al cambiar tema: ' . $resultado['error'];
                $tipo_mensaje = 'error';
            }
            break;
            
        case 'generar_backup':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $resultado = generar_backup($usuario_id);
                
                if ($resultado['success']) {
                    $mensaje = 'Backup generado exitosamente: ' . $resultado['nombre'] . ' (' . round($resultado['tamano']/1024/1024, 2) . ' MB)';
                    $tipo_mensaje = 'success';
                    
                    // Enviar backup por Telegram
                    $telegram_msg = "💾 <b>BACKUP GENERADO MANUALMENTE</b>\n\n";
                    $telegram_msg .= "📁 <b>Archivo:</b> " . $resultado['nombre'] . "\n";
                    $telegram_msg .= "📊 <b>Tamaño:</b> " . round($resultado['tamano']/1024/1024, 2) . " MB\n";
                    $telegram_msg .= "👤 <b>Generado por:</b> " . $usuario_actual['nombre'] . "\n";
                    $telegram_msg .= "⏰ <b>Fecha:</b> " . date('d/m/Y H:i:s');
                    
                    enviar_telegram($usuario_id, $telegram_msg);
                } else {
                    $mensaje = 'Error al generar backup: ' . $resultado['error'];
                    $tipo_mensaje = 'error';
                }
            }
            break;
            
        case 'descargar_backup':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $backup_id = $_POST['backup_id'] ?? '';
                $resultado = descargar_backup($backup_id, $usuario_id);
                
                if (!$resultado['success']) {
                    $mensaje = 'Error al descargar backup: ' . $resultado['error'];
                    $tipo_mensaje = 'error';
                }
                // La función descargar_backup ya maneja la descarga y termina el script
            }
            break;
            
        case 'subir_backup':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $resultado = subir_backup($_FILES['backup_file'], $usuario_id);
                
                if ($resultado['success']) {
                    $mensaje = 'Backup subido exitosamente: ' . $resultado['nombre'];
                    $tipo_mensaje = 'success';
                } else {
                    $mensaje = 'Error al subir backup: ' . $resultado['error'];
                    $tipo_mensaje = 'error';
                }
            }
            break;
            
        case 'asignar_patana':
            if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
                $empleado_id = $_POST['empleado_patana'] ?? '';
                $pasillo = $_POST['pasillo_patana'] ?? '';
                
                try {
                    $titulo = "Cubrir Patana - Pasillo " . $pasillo;
                    $descripcion = "Cubrir la patana del pasillo " . $pasillo . " por empleado ausente";
                    
                    $stmt = $pdo->prepare("INSERT INTO tareas (titulo, descripcion, empleado_id, administrador_id, pasillo_area, tipo_tarea, notificar_telegram) VALUES (?, ?, ?, ?, ?, 'pasillo', TRUE)");
                    $stmt->execute([$titulo, $descripcion, $empleado_id, $usuario_id, $pasillo]);
                    
                    // Notificar al empleado
                    $stmt_emp = $pdo->prepare("SELECT nombre FROM usuarios WHERE id = ?");
                    $stmt_emp->execute([$empleado_id]);
                    $empleado = $stmt_emp->fetch();
                    
                    $mensaje_telegram = "🔄 <b>ASIGNACIÓN DE PATANA</b>\n\n";
                    $mensaje_telegram .= "👤 <b>Empleado:</b> " . $empleado['nombre'] . "\n";
                    $mensaje_telegram .= "📍 <b>Pasillo:</b> " . $pasillo . "\n";
                    $mensaje_telegram .= "📝 <b>Tarea:</b> Cubrir patana\n";
                    $mensaje_telegram .= "📖 <b>Descripción:</b> " . $descripcion . "\n\n";
                    $mensaje_telegram .= "✅ <b>Asignado por recomendación del sistema</b>";
                    
                    enviar_telegram($empleado_id, $mensaje_telegram);
                    
                    $mensaje = 'Patana asignada exitosamente al empleado';
                    $tipo_mensaje = 'success';
                    registrar_log($usuario_id, 'PATANA_ASIGNADA', "Empleado ID: $empleado_id, Pasillo: $pasillo");
                } catch(Exception $e) {
                    $mensaje = 'Error al asignar patana: ' . $e->getMessage();
                    $tipo_mensaje = 'error';
                }
            }
            break;
    }
}

// Obtener estadísticas
if ($usuario_actual['rol'] === 'empleado') {
    $tareas_pendientes = $pdo->query("SELECT COUNT(*) FROM tareas WHERE empleado_id = $usuario_id AND estado = 'pendiente'")->fetchColumn();
    $tareas_completadas = $pdo->query("SELECT COUNT(*) FROM tareas WHERE empleado_id = $usuario_id AND estado = 'completada'")->fetchColumn();
    $tareas_vencidas = $pdo->query("SELECT COUNT(*) FROM tareas WHERE empleado_id = $usuario_id AND estado = 'vencida'")->fetchColumn();
    
    // Obtener estadísticas del empleado actual
    $empleados_turno_actual = obtener_estadisticas_turno($usuario_actual['turno']);
} else {
    $tareas_pendientes = $pdo->query("SELECT COUNT(*) FROM tareas WHERE estado = 'pendiente'")->fetchColumn();
    $tareas_completadas = $pdo->query("SELECT COUNT(*) FROM tareas WHERE estado = 'completada'")->fetchColumn();
    $tareas_vencidas = $pdo->query("SELECT COUNT(*) FROM tareas WHERE estado = 'vencida'")->fetchColumn();
    
    // Obtener estadísticas por turno
    $empleados_am = obtener_estadisticas_turno('AM');
    $empleados_pm = obtener_estadisticas_turno('PM');
    $total_empleados = $empleados_am + $empleados_pm;
    
    // Obtener empleados libres hoy
    $empleados_libres_count = 0;
    $empleados_trabajando = $pdo->query("SELECT * FROM usuarios WHERE activo = TRUE AND rol = 'empleado'")->fetchAll();
    foreach ($empleados_trabajando as $emp) {
        if (empleado_esta_libre_hoy($emp)) {
            $empleados_libres_count++;
        }
    }
}

// Obtener empleados (para administradores)
$empleados = [];
if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
    $empleados = $pdo->query("SELECT * FROM usuarios WHERE rol = 'empleado' AND activo = TRUE ORDER BY nombre")->fetchAll();
}

// Obtener tareas del usuario
if ($usuario_actual['rol'] === 'empleado') {
    $tareas = $pdo->prepare("SELECT t.*, u.nombre as admin_nombre FROM tareas t LEFT JOIN usuarios u ON t.administrador_id = u.id WHERE t.empleado_id = ? ORDER BY t.fecha_asignacion DESC");
    $tareas->execute([$usuario_id]);
    $tareas = $tareas->fetchAll();
}

// Obtener todas las tareas para administradores
$todas_tareas = [];
if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
    $todas_tareas = $pdo->query("SELECT t.*, u.nombre as empleado_nombre, u2.nombre as admin_nombre FROM tareas t LEFT JOIN usuarios u ON t.empleado_id = u.id LEFT JOIN usuarios u2 ON t.administrador_id = u2.id ORDER BY t.fecha_asignacion DESC LIMIT 100")->fetchAll();
}

// Obtener configuraciones actuales
$stmt_config = $pdo->query("SELECT clave, valor FROM configuraciones");
$configuraciones = $stmt_config->fetchAll(PDO::FETCH_KEY_PAIR);

// Obtener backups
$backups = [];
if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
    $backups = $pdo->query("SELECT b.*, u.nombre as creador_nombre FROM backups b LEFT JOIN usuarios u ON b.creado_por = u.id ORDER BY b.fecha_creacion DESC LIMIT 10")->fetchAll();
}

// Obtener temas disponibles
$temas = $pdo->query("SELECT * FROM temas ORDER BY nombre")->fetchAll();

// Obtener recomendaciones de patanas COMPLETAMENTE CORREGIDAS
$recomendaciones_patanas = [];
if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])) {
    $recomendaciones_patanas = obtener_recomendaciones_patanas();
}

// Determinar turno actual para mostrar
$turno_actual = date('H') < 12 ? 'AM' : 'PM';
$dias_semana = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
$dia_actual = $dias_semana[date('w')];
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Panel - <?php echo htmlspecialchars($nombre_sistema); ?></title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root {
            --primary: <?php echo $colores_tema['primary']; ?>;
            --primary-dark: #154360;
            --secondary: <?php echo $colores_tema['secondary']; ?>;
            --accent: <?php echo $colores_tema['accent']; ?>;
            --background: <?php echo $colores_tema['background']; ?>;
            --card-bg: <?php echo $colores_tema['card_bg']; ?>;
            --card-hover: #21283b;
            --text: <?php echo $colores_tema['text']; ?>;
            --text-muted: #95a5a6;
            --border: #34495e;
            --success: #27ae60;
            --warning: #f39c12;
            --danger: #e74c3c;
            --info: #3498db;
            --sidebar-width: 280px;
            --header-height: 70px;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--background);
            color: var(--text);
            min-height: 100vh;
            overflow-x: hidden;
        }
        
        .container {
            display: flex;
            min-height: 100vh;
        }
        
        /* Sidebar Moderno */
        .sidebar {
            width: var(--sidebar-width);
            background: linear-gradient(180deg, var(--card-bg) 0%, #151a27 100%);
            padding: 0;
            border-right: 1px solid var(--border);
            position: fixed;
            height: 100vh;
            overflow-y: auto;
            z-index: 1000;
            transition: transform 0.3s ease;
            box-shadow: 0 0 30px rgba(0,0,0,0.3);
        }
        
        .sidebar-header {
            padding: 25px 20px;
            border-bottom: 1px solid var(--border);
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            position: relative;
            overflow: hidden;
        }
        
        .sidebar-header::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: linear-gradient(45deg, transparent 30%, rgba(255,255,255,0.1) 50%, transparent 70%);
            animation: shimmer 3s infinite;
        }
        
        @keyframes shimmer {
            0% { transform: translateX(-100%); }
            100% { transform: translateX(100%); }
        }
        
        .logo {
            display: flex;
            align-items: center;
            gap: 12px;
            position: relative;
            z-index: 1;
        }
        
        .logo-icon {
            font-size: 28px;
            color: white;
            filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));
        }
        
        .logo-text h1 {
            font-size: 18px;
            color: white;
            font-weight: 600;
            line-height: 1.2;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
        }
        
        .logo-text span {
            font-size: 11px;
            color: rgba(255,255,255,0.8);
            font-weight: 300;
        }
        
        .user-info {
            padding: 20px;
            border-bottom: 1px solid var(--border);
            background: var(--card-bg);
        }
        
        .user-avatar {
            width: 50px;
            height: 50px;
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 10px;
            font-size: 20px;
            color: white;
            box-shadow: 0 4px 12px rgba(26, 82, 118, 0.4);
        }
        
        .user-details h3 {
            color: var(--primary);
            margin-bottom: 5px;
            font-size: 16px;
        }
        
        .user-details p {
            color: var(--text-muted);
            font-size: 12px;
        }
        
        .nav-menu {
            list-style: none;
            padding: 15px 0;
        }
        
        .nav-menu li {
            margin: 8px 0;
        }
        
        .nav-menu a {
            display: flex;
            align-items: center;
            padding: 14px 25px;
            color: var(--text-muted);
            text-decoration: none;
            transition: all 0.3s ease;
            border-left: 4px solid transparent;
            position: relative;
            overflow: hidden;
        }
        
        .nav-menu a::before {
            content: '';
            position: absolute;
            left: 0;
            top: 0;
            bottom: 0;
            width: 0;
            background: linear-gradient(90deg, rgba(26, 82, 118, 0.1), transparent);
            transition: width 0.3s ease;
        }
        
        .nav-menu a:hover {
            color: var(--primary);
            background: rgba(26, 82, 118, 0.05);
        }
        
        .nav-menu a:hover::before {
            width: 100%;
        }
        
        .nav-menu a.active {
            background: rgba(26, 82, 118, 0.1);
            color: var(--primary);
            border-left-color: var(--primary);
            font-weight: 500;
        }
        
        .nav-menu a.active::before {
            width: 100%;
        }
        
        .nav-menu i {
            width: 20px;
            margin-right: 12px;
            font-size: 16px;
            text-align: center;
        }
        
        /* Main Content */
        .main-content {
            flex: 1;
            margin-left: var(--sidebar-width);
            padding: 0;
            transition: margin-left 0.3s ease;
            background: var(--background);
        }
        
        .top-header {
            background: var(--card-bg);
            padding: 0 30px;
            border-bottom: 1px solid var(--border);
            display: flex;
            justify-content: space-between;
            align-items: center;
            position: sticky;
            top: 0;
            z-index: 100;
            height: var(--header-height);
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        .header-left {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        .mobile-menu-btn {
            background: none;
            border: none;
            color: var(--text);
            font-size: 20px;
            cursor: pointer;
            display: none;
            padding: 8px;
            border-radius: 8px;
            transition: background 0.3s ease;
        }
        
        .mobile-menu-btn:hover {
            background: rgba(255,255,255,0.1);
        }
        
        .page-title {
            color: var(--primary);
            font-size: 24px;
            font-weight: 600;
        }
        
        .header-right {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        .time-display {
            background: var(--secondary);
            padding: 8px 15px;
            border-radius: 20px;
            font-size: 14px;
            color: var(--text-muted);
            border: 1px solid var(--border);
        }
        
        /* Content Area */
        .content {
            padding: 30px;
            max-width: 1400px;
            margin: 0 auto;
            width: 100%;
        }
        
        /* Alertas de tareas */
        .tarea-alerta {
            background: linear-gradient(135deg, var(--warning), #e67e22);
            color: white;
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 25px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.3);
            display: flex;
            align-items: center;
            gap: 15px;
            animation: pulse 2s infinite;
            border: 1px solid rgba(255,255,255,0.1);
        }
        
        .tarea-alerta.danger {
            background: linear-gradient(135deg, var(--danger), #c0392b);
        }
        
        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.02); }
            100% { transform: scale(1); }
        }
        
        /* Stats Grid Mejorado */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 25px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: linear-gradient(135deg, var(--card-bg), var(--card-hover));
            padding: 25px;
            border-radius: 15px;
            border: 1px solid var(--border);
            box-shadow: 0 8px 25px rgba(0,0,0,0.2);
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
            cursor: pointer;
        }
        
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
            background: linear-gradient(90deg, var(--primary), var(--primary-dark));
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 35px rgba(0,0,0,0.3);
        }
        
        .stat-card h3 {
            color: var(--text-muted);
            font-size: 14px;
            margin-bottom: 10px;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .stat-card .number {
            font-size: 42px;
            color: var(--primary);
            font-weight: 700;
            line-height: 1;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
        }
        
        .stat-card .trend {
            font-size: 12px;
            color: var(--success);
            margin-top: 8px;
            display: flex;
            align-items: center;
            gap: 5px;
        }
        
        /* Cards Mejoradas */
        .card {
            background: linear-gradient(135deg, var(--card-bg), var(--card-hover));
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 8px 25px rgba(0,0,0,0.2);
            border: 1px solid var(--border);
            transition: transform 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-2px);
        }
        
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 25px;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border);
        }
        
        .card-title {
            color: var(--primary);
            font-size: 22px;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        /* Forms Mejorados */
        .form-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-label {
            display: block;
            color: var(--text);
            margin-bottom: 8px;
            font-weight: 500;
            font-size: 14px;
        }
        
        .form-control {
            width: 100%;
            padding: 14px 16px;
            background: var(--secondary);
            border: 1px solid var(--border);
            border-radius: 10px;
            color: var(--text);
            font-size: 14px;
            transition: all 0.3s ease;
        }
        
        .form-control:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 0 3px rgba(26, 82, 118, 0.1);
            background: var(--card-bg);
        }
        
        .form-check {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 10px;
        }
        
        .form-check-input {
            width: 18px;
            height: 18px;
        }
        
        .form-check-label {
            color: var(--text);
            font-size: 14px;
        }
        
        /* Buttons Mejorados */
        .btn {
            padding: 14px 24px;
            border: none;
            border-radius: 10px;
            cursor: pointer;
            font-weight: 500;
            transition: all 0.3s ease;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            font-size: 14px;
            position: relative;
            overflow: hidden;
        }
        
        .btn::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255,255,255,0.2), transparent);
            transition: left 0.5s;
        }
        
        .btn:hover::before {
            left: 100%;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            color: white;
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 20px rgba(26, 82, 118, 0.4);
        }
        
        .btn-success {
            background: linear-gradient(135deg, var(--success), #229954);
            color: white;
        }
        
        .btn-danger {
            background: linear-gradient(135deg, var(--danger), #c0392b);
            color: white;
        }
        
        .btn-warning {
            background: linear-gradient(135deg, var(--warning), #e67e22);
            color: white;
        }
        
        .btn-info {
            background: linear-gradient(135deg, var(--info), #2980b9);
            color: white;
        }
        
        .btn-sm {
            padding: 10px 16px;
            font-size: 12px;
        }
        
        /* Tables Mejoradas */
        .table-responsive {
            overflow-x: auto;
            border-radius: 10px;
            border: 1px solid var(--border);
        }
        
        .table {
            width: 100%;
            border-collapse: collapse;
        }
        
        .table th {
            background: linear-gradient(135deg, var(--secondary), #34495e);
            color: var(--primary);
            padding: 16px;
            text-align: left;
            font-weight: 600;
            font-size: 14px;
            border-bottom: 1px solid var(--border);
        }
        
        .table td {
            padding: 16px;
            border-bottom: 1px solid var(--border);
            font-size: 14px;
        }
        
        .table tr:hover {
            background: rgba(26, 82, 118, 0.05);
        }
        
        /* Badges Mejorados */
        .badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            border: 1px solid transparent;
        }
        
        .badge-success {
            background: rgba(39, 174, 96, 0.2);
            color: var(--success);
            border-color: rgba(39, 174, 96, 0.3);
        }
        
        .badge-warning {
            background: rgba(243, 156, 18, 0.2);
            color: var(--warning);
            border-color: rgba(243, 156, 18, 0.3);
        }
        
        .badge-danger {
            background: rgba(231, 76, 60, 0.2);
            color: var(--danger);
            border-color: rgba(231, 76, 60, 0.3);
        }
        
        .badge-info {
            background: rgba(52, 152, 219, 0.2);
            color: var(--info);
            border-color: rgba(52, 152, 219, 0.3);
        }
        
        .badge-primary {
            background: rgba(26, 82, 118, 0.2);
            color: var(--primary);
            border-color: rgba(26, 82, 118, 0.3);
        }
        
        /* Messages Mejorados */
        .alert {
            padding: 16px 20px;
            border-radius: 10px;
            margin-bottom: 25px;
            border-left: 4px solid;
            animation: slideIn 0.3s ease;
            background: var(--card-bg);
            border: 1px solid var(--border);
        }
        
        .alert-success {
            border-left-color: var(--success);
            color: var(--success);
        }
        
        .alert-error {
            border-left-color: var(--danger);
            color: var(--danger);
        }
        
        .alert-warning {
            border-left-color: var(--warning);
            color: var(--warning);
        }
        
        .alert-info {
            border-left-color: var(--info);
            color: var(--info);
        }
        
        @keyframes slideIn {
            from { opacity: 0; transform: translateX(-20px); }
            to { opacity: 1; transform: translateX(0); }
        }
        
        /* Tabs Mejorados */
        .tab-content {
            display: none;
        }
        
        .tab-content.active {
            display: block;
            animation: fadeIn 0.3s ease;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        /* Modal Mejorado */
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.8);
            z-index: 2000;
            align-items: center;
            justify-content: center;
            backdrop-filter: blur(5px);
        }
        
        .modal-content {
            background: linear-gradient(135deg, var(--card-bg), var(--card-hover));
            border-radius: 15px;
            padding: 30px;
            max-width: 500px;
            width: 90%;
            max-height: 90vh;
            overflow-y: auto;
            border: 1px solid var(--border);
            box-shadow: 0 20px 50px rgba(0,0,0,0.5);
        }
        
        .modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 1px solid var(--border);
        }
        
        .modal-title {
            color: var(--primary);
            font-size: 20px;
            font-weight: 600;
        }
        
        .close-modal {
            background: none;
            border: none;
            color: var(--text-muted);
            font-size: 24px;
            cursor: pointer;
            padding: 5px;
            border-radius: 5px;
            transition: background 0.3s ease;
        }
        
        .close-modal:hover {
            background: rgba(255,255,255,0.1);
        }
        
        /* Cámara Mejorada */
        .camera-container {
            width: 100%;
            background: var(--secondary);
            border-radius: 10px;
            overflow: hidden;
            margin-bottom: 15px;
            border: 1px solid var(--border);
        }
        
        #video {
            width: 100%;
            height: 300px;
            object-fit: cover;
        }
        
        .camera-controls {
            display: flex;
            gap: 10px;
            justify-content: center;
            padding: 15px;
        }
        
        .photo-preview {
            width: 100%;
            max-height: 300px;
            object-fit: contain;
            background: var(--secondary);
            border-radius: 10px;
            margin-bottom: 15px;
            border: 1px solid var(--border);
        }
        
        /* Recomendaciones Mejoradas */
        .recomendacion-card {
            background: linear-gradient(135deg, var(--warning), #e67e22);
            color: white;
            padding: 25px;
            border-radius: 15px;
            margin-bottom: 25px;
            box-shadow: 0 8px 25px rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.1);
        }
        
        .recomendacion-card h4 {
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 18px;
        }
        
        .recomendacion-actions {
            display: flex;
            gap: 10px;
            margin-top: 20px;
            flex-wrap: wrap;
        }
        
        /* Calificación moderna */
        .rating-stars {
            display: flex;
            gap: 5px;
            margin: 10px 0;
        }
        
        .rating-star {
            font-size: 24px;
            color: #ddd;
            cursor: pointer;
            transition: color 0.2s ease;
        }
        
        .rating-star.active {
            color: var(--warning);
        }
        
        .rating-star:hover {
            color: var(--warning);
        }
        
        /* Temas */
        .temas-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .tema-card {
            background: var(--card-bg);
            border: 2px solid var(--border);
            border-radius: 10px;
            padding: 20px;
            cursor: pointer;
            transition: all 0.3s ease;
            text-align: center;
        }
        
        .tema-card:hover {
            transform: translateY(-5px);
            border-color: var(--primary);
        }
        
        .tema-card.activo {
            border-color: var(--primary);
            box-shadow: 0 0 0 3px rgba(26, 82, 118, 0.3);
        }
        
        .tema-preview {
            width: 100%;
            height: 80px;
            border-radius: 8px;
            margin-bottom: 10px;
            border: 1px solid var(--border);
        }
        
        /* Responsive */
        @media (max-width: 1024px) {
            .sidebar {
                transform: translateX(-100%);
            }
            
            .sidebar.active {
                transform: translateX(0);
            }
            
            .main-content {
                margin-left: 0;
            }
            
            .mobile-menu-btn {
                display: block;
            }
            
            .content {
                padding: 20px;
            }
        }
        
        @media (max-width: 768px) {
            .content {
                padding: 15px;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
            
            .form-grid {
                grid-template-columns: 1fr;
            }
            
            .top-header {
                padding: 0 20px;
            }
            
            .card {
                padding: 20px;
            }
            
            .table-responsive {
                font-size: 12px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Sidebar -->
        <div class="sidebar" id="sidebar">
            <div class="sidebar-header">
                <div class="logo">
                    <i class="fas fa-users-cog logo-icon"></i>
                    <div class="logo-text">
                        <h1><?php echo htmlspecialchars($nombre_sistema); ?></h1>
                        <span>v2.2</span>
                    </div>
                </div>
            </div>
            
            <div class="user-info">
                <div class="user-avatar">
                    <i class="fas fa-user"></i>
                </div>
                <div class="user-details">
                    <h3><?php echo htmlspecialchars($usuario_actual['nombre']); ?></h3>
                    <p><?php echo htmlspecialchars(ucfirst($usuario_actual['rol'])); ?> - Turno <?php echo $usuario_actual['turno']; ?></p>
                </div>
            </div>
            
            <ul class="nav-menu">
                <li><a href="#" class="active" data-tab="dashboard"><i class="fas fa-chart-line"></i> Dashboard</a></li>
                <?php if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])): ?>
                    <li><a href="#" data-tab="gestion-usuarios"><i class="fas fa-users"></i> Gestión de Usuarios</a></li>
                    <li><a href="#" data-tab="asignar-tareas"><i class="fas fa-tasks"></i> Asignar Tareas</a></li>
                    <li><a href="#" data-tab="ver-tareas"><i class="fas fa-list-check"></i> Ver Todas las Tareas</a></li>
                <?php endif; ?>
                <?php if ($usuario_actual['rol'] === 'empleado'): ?>
                    <li><a href="#" data-tab="mis-tareas"><i class="fas fa-list-check"></i> Mis Tareas</a></li>
                <?php endif; ?>
                <li><a href="#" data-tab="mi-perfil"><i class="fas fa-user-edit"></i> Mi Perfil</a></li>
                <?php if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])): ?>
                    <li><a href="#" data-tab="configuracion"><i class="fas fa-cog"></i> Configuración</a></li>
                <?php endif; ?>
                <li><a href="logout.php" style="color: var(--danger);"><i class="fas fa-sign-out-alt"></i> Cerrar Sesión</a></li>
            </ul>
        </div>
        
        <!-- Main Content -->
        <div class="main-content">
            <div class="top-header">
                <div class="header-left">
                    <button class="mobile-menu-btn" onclick="toggleSidebar()">
                        <i class="fas fa-bars"></i>
                    </button>
                    <h1 class="page-title" id="page-title">Dashboard</h1>
                </div>
                <div class="header-right">
                    <div class="time-display">
                        <i class="fas fa-clock"></i> 
                        <span id="current-time"><?php echo date('d/m/Y H:i:s'); ?></span> - RD
                    </div>
                </div>
            </div>
            
            <div class="content">
                <?php if ($mensaje): ?>
                    <div class="alert <?php echo $tipo_mensaje === 'success' ? 'alert-success' : ($tipo_mensaje === 'warning' ? 'alert-warning' : 'alert-error'); ?>" id="mensaje-alerta">
                        <i class="fas <?php echo $tipo_mensaje === 'success' ? 'fa-check-circle' : ($tipo_mensaje === 'warning' ? 'fa-exclamation-triangle' : 'fa-exclamation-circle'); ?>"></i>
                        <?php echo htmlspecialchars($mensaje); ?>
                    </div>
                    <script>
                        setTimeout(() => {
                            const alerta = document.getElementById('mensaje-alerta');
                            if (alerta) {
                                alerta.style.display = 'none';
                            }
                        }, 5000);
                    </script>
                <?php endif; ?>
                
                <!-- Alertas de tareas para empleados -->
                <?php if ($usuario_actual['rol'] === 'empleado' && $tareas_pendientes > 0): ?>
                    <div class="tarea-alerta <?php echo $tareas_vencidas > 0 ? 'danger' : ''; ?>">
                        <i class="fas <?php echo $tareas_vencidas > 0 ? 'fa-exclamation-triangle' : 'fa-bell'; ?> fa-2x"></i>
                        <div>
                            <h4><?php echo $tareas_vencidas > 0 ? '¡Tareas Vencidas!' : 'Tareas Pendientes'; ?></h4>
                            <p>Tienes <strong><?php echo $tareas_pendientes; ?></strong> tareas pendientes<?php echo $tareas_vencidas > 0 ? ', incluyendo ' . $tareas_vencidas . ' vencidas' : ''; ?>.</p>
                        </div>
                    </div>
                <?php endif; ?>
                
                <!-- Dashboard -->
                <div id="dashboard" class="tab-content active">
                    <!-- Recomendaciones de patanas COMPLETAMENTE CORREGIDAS -->
                    <?php if (in_array($usuario_actual['rol'], ['admin_pro', 'admin']) && !empty($recomendaciones_patanas)): ?>
                        <div class="recomendacion-card">
                            <h4><i class="fas fa-lightbulb"></i> RECOMENDACIÓN DEL SISTEMA - COBERTURA DE PATANAS</h4>
                            <p><?php echo $recomendaciones_patanas['mensaje']; ?></p>
                            
                            <div style="margin: 15px 0;">
                                <strong>Pasillos que necesitan cobertura:</strong>
                                <div style="display: flex; gap: 5px; flex-wrap: wrap; margin: 5px 0 15px 0;">
                                    <?php foreach ($recomendaciones_patanas['pasillos_sin_cobertura'] as $pasillo): ?>
                                        <span style="background: rgba(255,255,255,0.2); padding: 5px 10px; border-radius: 5px;">Pasillo <?php echo $pasillo; ?></span>
                                    <?php endforeach; ?>
                                </div>
                                
                                <?php if (!empty($recomendaciones_patanas['pasillos_ya_cubiertos'])): ?>
                                    <strong>Pasillos ya cubiertos hoy:</strong>
                                    <div style="display: flex; gap: 5px; flex-wrap: wrap; margin: 5px 0 15px 0;">
                                        <?php foreach ($recomendaciones_patanas['pasillos_ya_cubiertos'] as $pasillo): ?>
                                            <span style="background: rgba(0,255,0,0.2); padding: 5px 10px; border-radius: 5px; color: lightgreen;">Pasillo <?php echo $pasillo; ?> ✓</span>
                                        <?php endforeach; ?>
                                    </div>
                                <?php endif; ?>
                                
                                <strong>Empleados disponibles para cubrir (Turno <?php echo $recomendaciones_patanas['turno_actual']; ?>):</strong>
                                <ul style="margin: 5px 0 15px 20px;">
                                    <?php foreach ($recomendaciones_patanas['empleados_disponibles'] as $emp): ?>
                                        <li><?php echo $emp['nombre']; ?> (<?php echo $emp['turno']; ?>) - Pasillo: <?php echo $emp['pasillo_asignado'] ?: 'No asignado'; ?></li>
                                    <?php endforeach; ?>
                                </ul>
                            </div>
                            
                            <div class="recomendacion-actions">
                                <form method="POST" style="display: inline;">
                                    <input type="hidden" name="accion" value="asignar_patana">
                                    <select name="empleado_patana" class="form-control" style="margin-bottom: 10px;" required>
                                        <option value="">Seleccionar empleado para cubrir</option>
                                        <?php foreach ($recomendaciones_patanas['empleados_disponibles'] as $emp): ?>
                                            <option value="<?php echo $emp['id']; ?>"><?php echo $emp['nombre']; ?> (<?php echo $emp['turno']; ?>)</option>
                                        <?php endforeach; ?>
                                    </select>
                                    <select name="pasillo_patana" class="form-control" style="margin-bottom: 10px;" required>
                                        <option value="">Seleccionar pasillo a cubrir</option>
                                        <?php foreach ($recomendaciones_patanas['pasillos_sin_cobertura'] as $pasillo): ?>
                                            <option value="<?php echo $pasillo; ?>">Pasillo <?php echo $pasillo; ?></option>
                                        <?php endforeach; ?>
                                    </select>
                                    <button type="submit" class="btn btn-warning">
                                        <i class="fas fa-user-check"></i> Asignar Patana
                                    </button>
                                </form>
                            </div>
                        </div>
                    <?php elseif (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])): ?>
                        <div class="alert alert-success">
                            <i class="fas fa-check-circle"></i> Todos los pasillos están cubiertos correctamente. No se necesitan asignaciones de patanas.
                        </div>
                    <?php endif; ?>
                    
                    <div class="stats-grid">
                        <?php if ($usuario_actual['rol'] === 'empleado'): ?>
                            <div class="stat-card" onclick="mostrarTab('mis-tareas')">
                                <h3>Mis Tareas Pendientes</h3>
                                <div class="number"><?php echo $tareas_pendientes; ?></div>
                                <div class="trend"><i class="fas fa-clock"></i> Por completar</div>
                            </div>
                            <div class="stat-card" onclick="mostrarTab('mis-tareas')">
                                <h3>Mis Tareas Completadas</h3>
                                <div class="number"><?php echo $tareas_completadas; ?></div>
                                <div class="trend success"><i class="fas fa-check"></i> Finalizadas</div>
                            </div>
                            <div class="stat-card" onclick="mostrarTab('mis-tareas')">
                                <h3>Mis Tareas Vencidas</h3>
                                <div class="number"><?php echo $tareas_vencidas; ?></div>
                                <div class="trend danger"><i class="fas fa-exclamation-triangle"></i> Requieren atención</div>
                            </div>
                            <div class="stat-card">
                                <h3>Empleados en mi Turno (<?php echo $usuario_actual['turno']; ?>)</h3>
                                <div class="number"><?php echo $empleados_turno_actual; ?></div>
                                <div class="trend info"><i class="fas fa-users"></i> Trabajando hoy</div>
                            </div>
                            <?php if ($usuario_actual['pasillo_asignado']): ?>
                                <div class="stat-card">
                                    <h3>Mi Pasillo</h3>
                                    <div class="number"><?php echo htmlspecialchars($usuario_actual['pasillo_asignado']); ?></div>
                                    <div class="trend"><i class="fas fa-location-dot"></i> Área designada</div>
                                </div>
                            <?php endif; ?>
                        <?php else: ?>
                            <div class="stat-card" onclick="mostrarTab('ver-tareas')">
                                <h3>Tareas Pendientes</h3>
                                <div class="number"><?php echo $tareas_pendientes; ?></div>
                                <div class="trend"><i class="fas fa-clock"></i> Por completar</div>
                            </div>
                            <div class="stat-card" onclick="mostrarTab('ver-tareas')">
                                <h3>Tareas Completadas</h3>
                                <div class="number"><?php echo $tareas_completadas; ?></div>
                                <div class="trend success"><i class="fas fa-check"></i> Finalizadas</div>
                            </div>
                            <div class="stat-card" onclick="mostrarTab('ver-tareas')">
                                <h3>Tareas Vencidas</h3>
                                <div class="number"><?php echo $tareas_vencidas; ?></div>
                                <div class="trend danger"><i class="fas fa-exclamation-triangle"></i> Requieren atención</div>
                            </div>
                            <div class="stat-card">
                                <h3>Empleados Turno AM</h3>
                                <div class="number"><?php echo $empleados_am; ?></div>
                                <div class="trend info"><i class="fas fa-sun"></i> Trabajando hoy</div>
                            </div>
                            <div class="stat-card">
                                <h3>Empleados Turno PM</h3>
                                <div class="number"><?php echo $empleados_pm; ?></div>
                                <div class="trend info"><i class="fas fa-moon"></i> Trabajando hoy</div>
                            </div>
                            <div class="stat-card">
                                <h3>Total Empleados</h3>
                                <div class="number"><?php echo $total_empleados; ?></div>
                                <div class="trend success"><i class="fas fa-users"></i> Activos hoy</div>
                            </div>
                        <?php endif; ?>
                    </div>
                    
                    <!-- Información del día actual -->
                    <div class="card">
                        <div class="card-header">
                            <h2 class="card-title"><i class="fas fa-calendar-day"></i> Información del Día</h2>
                        </div>
                        <div class="form-grid">
                            <div class="form-group">
                                <label class="form-label">Fecha Actual</label>
                                <input type="text" class="form-control" value="<?php echo date('d/m/Y'); ?>" readonly>
                            </div>
                            <div class="form-group">
                                <label class="form-label">Día de la Semana</label>
                                <input type="text" class="form-control" value="<?php echo $dia_actual; ?>" readonly>
                            </div>
                            <div class="form-group">
                                <label class="form-label">Turno Actual</label>
                                <input type="text" class="form-control" value="<?php echo $turno_actual; ?>" readonly>
                            </div>
                            <?php if ($usuario_actual['rol'] === 'empleado'): ?>
                                <div class="form-group">
                                    <label class="form-label">Mi Estado Hoy</label>
                                    <input type="text" class="form-control" value="<?php echo empleado_esta_libre_hoy($usuario_actual) ? 'Libre' : 'Trabajando'; ?>" readonly style="color: <?php echo empleado_esta_libre_hoy($usuario_actual) ? '#e74c3c' : '#27ae60'; ?>; font-weight: bold;">
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
                
                <!-- Gestión de Usuarios (Solo administradores) -->
                <?php if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])): ?>
                    <div id="gestion-usuarios" class="tab-content">
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-user-plus"></i> Crear Nuevo Usuario</h2>
                            </div>
                            <form method="POST">
                                <input type="hidden" name="accion" value="crear_usuario">
                                <div class="form-grid">
                                    <div class="form-group">
                                        <label class="form-label">Usuario</label>
                                        <input type="text" name="username" class="form-control" required>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Contraseña</label>
                                        <input type="password" name="password" class="form-control" required>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Nombre Completo</label>
                                        <input type="text" name="nombre" class="form-control" required>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Rol</label>
                                        <select name="rol" class="form-control">
                                            <option value="empleado">Empleado</option>
                                            <?php if ($usuario_actual['rol'] === 'admin_pro'): ?>
                                                <option value="admin">Administrador</option>
                                            <?php endif; ?>
                                        </select>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">ID de Telegram</label>
                                        <input type="text" name="telegram_id" class="form-control" placeholder="@username o número ID">
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Turno</label>
                                        <select name="turno" class="form-control">
                                            <option value="AM">AM</option>
                                            <option value="PM">PM</option>
                                        </select>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Pasillo Asignado</label>
                                        <input type="text" name="pasillo" class="form-control">
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Día Libre</label>
                                        <select name="dia_libre" class="form-control">
                                            <option value="">Seleccionar</option>
                                            <option value="Lunes">Lunes</option>
                                            <option value="Martes">Martes</option>
                                            <option value="Miércoles">Miércoles</option>
                                            <option value="Jueves">Jueves</option>
                                            <option value="Viernes">Viernes</option>
                                            <option value="Sábado">Sábado</option>
                                            <option value="Domingo">Domingo</option>
                                        </select>
                                    </div>
                                </div>
                                <button type="submit" class="btn btn-primary">
                                    <i class="fas fa-save"></i> Crear Usuario
                                </button>
                            </form>
                        </div>
                        
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-users"></i> Lista de Empleados</h2>
                            </div>
                            <div class="table-responsive">
                                <table class="table">
                                    <thead>
                                        <tr>
                                            <th>Usuario</th>
                                            <th>Nombre</th>
                                            <th>Rol</th>
                                            <th>Turno</th>
                                            <th>Pasillo</th>
                                            <th>Día Libre</th>
                                            <th>Estado</th>
                                            <th>Acciones</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php foreach ($empleados as $empleado): ?>
                                            <tr>
                                                <td><?php echo htmlspecialchars($empleado['username']); ?></td>
                                                <td><?php echo htmlspecialchars($empleado['nombre']); ?></td>
                                                <td><span class="badge badge-primary"><?php echo htmlspecialchars(ucfirst($empleado['rol'])); ?></span></td>
                                                <td><?php echo htmlspecialchars($empleado['turno']); ?></td>
                                                <td><?php echo htmlspecialchars($empleado['pasillo_asignado']); ?></td>
                                                <td><?php echo htmlspecialchars($empleado['dia_libre']); ?></td>
                                                <td>
                                                    <span class="badge <?php echo empleado_esta_libre_hoy($empleado) ? 'badge-warning' : 'badge-success'; ?>">
                                                        <?php echo empleado_esta_libre_hoy($empleado) ? 'Libre Hoy' : 'Trabajando'; ?>
                                                    </span>
                                                </td>
                                                <td>
                                                    <button class="btn btn-primary btn-sm" onclick="editarUsuario(<?php echo $empleado['id']; ?>)">
                                                        <i class="fas fa-edit"></i> Editar
                                                    </button>
                                                    <?php if ($usuario_actual['rol'] === 'admin_pro' || $empleado['rol'] !== 'admin_pro'): ?>
                                                        <button class="btn btn-danger btn-sm" onclick="eliminarUsuario(<?php echo $empleado['id']; ?>)">
                                                            <i class="fas fa-trash"></i> Eliminar
                                                        </button>
                                                    <?php endif; ?>
                                                </td>
                                            </tr>
                                        <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Asignar Tareas - MEJORADO Y CORREGIDO -->
                    <div id="asignar-tareas" class="tab-content">
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-tasks"></i> Asignar Nueva Tarea</h2>
                            </div>
                            <form method="POST">
                                <input type="hidden" name="accion" value="asignar_tarea">
                                
                                <div class="form-group">
                                    <label class="form-label">Empleados</label>
                                    <select name="empleado_id[]" class="form-control" multiple required style="height: 150px;">
                                        <?php foreach ($empleados as $emp): ?>
                                            <option value="<?php echo $emp['id']; ?>"><?php echo htmlspecialchars($emp['nombre']); ?> - <?php echo $emp['turno']; ?></option>
                                        <?php endforeach; ?>
                                    </select>
                                    <small class="form-text" style="color: var(--text-muted);">Mantén Ctrl (Cmd en Mac) para seleccionar múltiples empleados</small>
                                </div>
                                
                                <div class="form-group">
                                    <label class="form-label">Título de la Tarea</label>
                                    <input type="text" name="titulo" class="form-control" required placeholder="Ingrese el título de la tarea">
                                </div>
                                
                                <div class="form-group">
                                    <label class="form-label">Descripción</label>
                                    <textarea name="descripcion" class="form-control" rows="4" required placeholder="Describa la tarea a realizar"></textarea>
                                </div>
                                
                                <div class="form-grid">
                                    <div class="form-group">
                                        <label class="form-label">Fecha de Vencimiento</label>
                                        <input type="datetime-local" name="fecha_vencimiento" class="form-control">
                                    </div>
                                </div>
                                
                                <div class="form-grid">
                                    <div class="form-check">
                                        <input type="checkbox" name="requiere_foto" id="requiere_foto" class="form-check-input">
                                        <label for="requiere_foto" class="form-check-label">Requerir foto de evidencia</label>
                                    </div>
                                    <div class="form-check">
                                        <input type="checkbox" name="notificar_telegram" id="notificar_telegram" class="form-check-input" checked>
                                        <label for="notificar_telegram" class="form-check-label">Notificar por Telegram</label>
                                    </div>
                                </div>
                                
                                <button type="submit" class="btn btn-primary">
                                    <i class="fas fa-paper-plane"></i> Asignar Tarea
                                </button>
                            </form>
                        </div>
                    </div>
                    
                    <!-- Ver Todas las Tareas - MEJORADO CON FOTOS -->
                    <div id="ver-tareas" class="tab-content">
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-list-check"></i> Todas las Tareas</h2>
                            </div>
                            <div class="table-responsive">
                                <table class="table">
                                    <thead>
                                        <tr>
                                            <th>Empleado</th>
                                            <th>Título</th>
                                            <th>Fecha Asignación</th>
                                            <th>Vence</th>
                                            <th>Estado</th>
                                            <th>Calificación</th>
                                            <th>Acciones</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php foreach ($todas_tareas as $tarea): ?>
                                            <tr>
                                                <td><?php echo htmlspecialchars($tarea['empleado_nombre']); ?></td>
                                                <td><?php echo htmlspecialchars($tarea['titulo']); ?></td>
                                                <td><?php echo date('d/m/Y H:i', strtotime($tarea['fecha_asignacion'])); ?></td>
                                                <td>
                                                    <?php if ($tarea['fecha_vencimiento']): ?>
                                                        <?php 
                                                            $fecha_vencimiento = strtotime($tarea['fecha_vencimiento']);
                                                            $hoy = time();
                                                            $clase = $fecha_vencimiento < $hoy && $tarea['estado'] === 'pendiente' ? 'badge-danger' : 'badge-info';
                                                        ?>
                                                        <span class="badge <?php echo $clase; ?>">
                                                            <?php echo date('d/m/Y H:i', $fecha_vencimiento); ?>
                                                        </span>
                                                    <?php else: ?>
                                                        No vence
                                                    <?php endif; ?>
                                                </td>
                                                <td>
                                                    <span class="badge <?php 
                                                        echo $tarea['estado'] === 'pendiente' ? 'badge-warning' : 
                                                               ($tarea['estado'] === 'completada' ? 'badge-success' : 
                                                               ($tarea['estado'] === 'vencida' ? 'badge-danger' : 'badge-primary')); 
                                                    ?>">
                                                        <?php echo ucfirst($tarea['estado']); ?>
                                                    </span>
                                                </td>
                                                <td>
                                                    <?php if ($tarea['calificacion']): ?>
                                                        <?php echo str_repeat('★', $tarea['calificacion']); ?>
                                                    <?php else: ?>
                                                        -
                                                    <?php endif; ?>
                                                </td>
                                                <td>
                                                    <?php if ($tarea['estado'] === 'completada'): ?>
                                                        <button class="btn btn-success btn-sm" onclick="verificarTarea(<?php echo $tarea['id']; ?>)">
                                                            <i class="fas fa-check-double"></i> Verificar
                                                        </button>
                                                    <?php endif; ?>
                                                    <button class="btn btn-info btn-sm" onclick="verDetallesTarea(<?php echo $tarea['id']; ?>)">
                                                        <i class="fas fa-eye"></i> Ver
                                                    </button>
                                                    <?php if ($tarea['foto_tarea'] && file_exists($tarea['foto_tarea'])): ?>
                                                        <button class="btn btn-warning btn-sm" onclick="verFotoTarea('<?php echo $tarea['foto_tarea']; ?>')">
                                                            <i class="fas fa-image"></i> Foto
                                                        </button>
                                                    <?php endif; ?>
                                                </td>
                                            </tr>
                                        <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                <?php endif; ?>
                
                <!-- Mis Tareas (Solo empleados) - MEJORADO -->
                <?php if ($usuario_actual['rol'] === 'empleado'): ?>
                    <div id="mis-tareas" class="tab-content">
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-list-check"></i> Mis Tareas</h2>
                            </div>
                            <?php if (empty($tareas)): ?>
                                <div class="alert alert-info">
                                    <i class="fas fa-info-circle"></i> No tienes tareas asignadas.
                                </div>
                            <?php else: ?>
                                <div class="table-responsive">
                                    <table class="table">
                                        <thead>
                                            <tr>
                                                <th>Título</th>
                                                <th>Descripción</th>
                                                <th>Fecha Asignación</th>
                                                <th>Vence</th>
                                                <th>Estado</th>
                                                <th>Calificación</th>
                                                <th>Acciones</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            <?php foreach ($tareas as $tarea): ?>
                                                <tr>
                                                    <td><strong><?php echo htmlspecialchars($tarea['titulo']); ?></strong></td>
                                                    <td><?php echo htmlspecialchars($tarea['descripcion']); ?></td>
                                                    <td><?php echo date('d/m/Y H:i', strtotime($tarea['fecha_asignacion'])); ?></td>
                                                    <td>
                                                        <?php if ($tarea['fecha_vencimiento']): ?>
                                                            <?php 
                                                                $fecha_vencimiento = strtotime($tarea['fecha_vencimiento']);
                                                                $hoy = time();
                                                                $clase = $fecha_vencimiento < $hoy && $tarea['estado'] === 'pendiente' ? 'badge-danger' : 'badge-info';
                                                            ?>
                                                            <span class="badge <?php echo $clase; ?>">
                                                                <?php echo date('d/m/Y H:i', $fecha_vencimiento); ?>
                                                            </span>
                                                        <?php else: ?>
                                                            <span class="badge badge-secondary">No vence</span>
                                                        <?php endif; ?>
                                                    </td>
                                                    <td>
                                                        <span class="badge <?php 
                                                            echo $tarea['estado'] === 'pendiente' ? 'badge-warning' : 
                                                                   ($tarea['estado'] === 'completada' ? 'badge-success' : 
                                                                   ($tarea['estado'] === 'vencida' ? 'badge-danger' : 'badge-primary')); 
                                                        ?>">
                                                            <?php echo ucfirst($tarea['estado']); ?>
                                                        </span>
                                                    </td>
                                                    <td>
                                                        <?php if ($tarea['calificacion']): ?>
                                                            <div style="color: gold;">
                                                                <?php echo str_repeat('★', $tarea['calificacion']); ?>
                                                            </div>
                                                            <?php if ($tarea['comentario_revision']): ?>
                                                                <small style="color: var(--text-muted); display: block; margin-top: 5px;">
                                                                    "<?php echo htmlspecialchars($tarea['comentario_revision']); ?>"
                                                                </small>
                                                            <?php endif; ?>
                                                        <?php else: ?>
                                                            <span style="color: var(--text-muted);">-</span>
                                                        <?php endif; ?>
                                                    </td>
                                                    <td>
                                                        <?php if ($tarea['estado'] === 'pendiente'): ?>
                                                            <button class="btn btn-success btn-sm" onclick="completarTarea(<?php echo $tarea['id']; ?>, <?php echo $tarea['requiere_foto'] ? 'true' : 'false'; ?>)">
                                                                <i class="fas fa-check"></i> Completar
                                                            </button>
                                                        <?php endif; ?>
                                                        <?php if ($tarea['foto_tarea'] && file_exists($tarea['foto_tarea'])): ?>
                                                            <button class="btn btn-info btn-sm" onclick="verFotoTarea('<?php echo $tarea['foto_tarea']; ?>')">
                                                                <i class="fas fa-image"></i> Ver Foto
                                                            </button>
                                                        <?php endif; ?>
                                                    </td>
                                                </tr>
                                            <?php endforeach; ?>
                                        </tbody>
                                    </table>
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>
                <?php endif; ?>
                
                <!-- Mi Perfil -->
                <div id="mi-perfil" class="tab-content">
                    <div class="card">
                        <div class="card-header">
                            <h2 class="card-title"><i class="fas fa-user-edit"></i> Mi Perfil</h2>
                        </div>
                        <form method="POST">
                            <input type="hidden" name="accion" value="editar_usuario">
                            <input type="hidden" name="user_id" value="<?php echo $usuario_actual['id']; ?>">
                            <div class="form-grid">
                                <div class="form-group">
                                    <label class="form-label">Usuario</label>
                                    <input type="text" class="form-control" value="<?php echo htmlspecialchars($usuario_actual['username']); ?>" <?php echo $usuario_actual['rol'] === 'empleado' ? 'readonly' : ''; ?>>
                                    <small class="form-text" style="color: var(--text-muted);"><?php echo $usuario_actual['rol'] === 'empleado' ? 'El usuario no se puede cambiar' : 'Solo administradores pueden cambiar el usuario'; ?></small>
                                </div>
                                <div class="form-group">
                                    <label class="form-label">Nombre Completo</label>
                                    <input type="text" name="nombre" class="form-control" value="<?php echo htmlspecialchars($usuario_actual['nombre']); ?>" <?php echo $usuario_actual['rol'] === 'empleado' ? 'readonly' : ''; ?>>
                                    <small class="form-text" style="color: var(--text-muted);"><?php echo $usuario_actual['rol'] === 'empleado' ? 'Solo el administrador puede cambiar el nombre' : ''; ?></small>
                                </div>
                                <div class="form-group">
                                    <label class="form-label">ID de Telegram</label>
                                    <input type="text" name="telegram_id" class="form-control" value="<?php echo htmlspecialchars($usuario_actual['telegram_id']); ?>" placeholder="@username o número ID">
                                </div>
                                <?php if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])): ?>
                                    <div class="form-group">
                                        <label class="form-label">Turno</label>
                                        <select name="turno" class="form-control">
                                            <option value="AM" <?php echo $usuario_actual['turno'] === 'AM' ? 'selected' : ''; ?>>AM</option>
                                            <option value="PM" <?php echo $usuario_actual['turno'] === 'PM' ? 'selected' : ''; ?>>PM</option>
                                        </select>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Pasillo Asignado</label>
                                        <input type="text" name="pasillo" class="form-control" value="<?php echo htmlspecialchars($usuario_actual['pasillo_asignado']); ?>">
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Día Libre</label>
                                        <select name="dia_libre" class="form-control">
                                            <option value="">Seleccionar</option>
                                            <option value="Lunes" <?php echo $usuario_actual['dia_libre'] === 'Lunes' ? 'selected' : ''; ?>>Lunes</option>
                                            <option value="Martes" <?php echo $usuario_actual['dia_libre'] === 'Martes' ? 'selected' : ''; ?>>Martes</option>
                                            <option value="Miércoles" <?php echo $usuario_actual['dia_libre'] === 'Miércoles' ? 'selected' : ''; ?>>Miércoles</option>
                                            <option value="Jueves" <?php echo $usuario_actual['dia_libre'] === 'Jueves' ? 'selected' : ''; ?>>Jueves</option>
                                            <option value="Viernes" <?php echo $usuario_actual['dia_libre'] === 'Viernes' ? 'selected' : ''; ?>>Viernes</option>
                                            <option value="Sábado" <?php echo $usuario_actual['dia_libre'] === 'Sábado' ? 'selected' : ''; ?>>Sábado</option>
                                            <option value="Domingo" <?php echo $usuario_actual['dia_libre'] === 'Domingo' ? 'selected' : ''; ?>>Domingo</option>
                                        </select>
                                    </div>
                                <?php else: ?>
                                    <div class="form-group">
                                        <label class="form-label">Turno</label>
                                        <input type="text" class="form-control" value="<?php echo htmlspecialchars($usuario_actual['turno']); ?>" readonly>
                                        <small class="form-text" style="color: var(--text-muted);">El turno lo asigna el administrador</small>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Pasillo Asignado</label>
                                        <input type="text" class="form-control" value="<?php echo htmlspecialchars($usuario_actual['pasillo_asignado']); ?>" readonly>
                                        <small class="form-text" style="color: var(--text-muted);">El pasillo lo asigna el administrador</small>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Día Libre</label>
                                        <input type="text" class="form-control" value="<?php echo htmlspecialchars($usuario_actual['dia_libre']); ?>" readonly>
                                        <small class="form-text" style="color: var(--text-muted);">El día libre lo asigna el administrador</small>
                                    </div>
                                <?php endif; ?>
                            </div>
                            <button type="submit" class="btn btn-primary">
                                <i class="fas fa-save"></i> Actualizar Perfil
                            </button>
                        </form>
                    </div>
                    
                    <div class="card">
                        <div class="card-header">
                            <h2 class="card-title"><i class="fas fa-lock"></i> Cambiar Contraseña</h2>
                        </div>
                        <form method="POST">
                            <input type="hidden" name="accion" value="cambiar_password">
                            <input type="hidden" name="user_id" value="<?php echo $usuario_actual['id']; ?>">
                            <div class="form-group">
                                <label class="form-label">Nueva Contraseña</label>
                                <input type="password" name="nueva_password" class="form-control" required>
                            </div>
                            <button type="submit" class="btn btn-primary">
                                <i class="fas fa-key"></i> Cambiar Contraseña
                            </button>
                        </form>
                    </div>
                </div>
                
                <!-- Configuración (Solo administradores) -->
                <?php if (in_array($usuario_actual['rol'], ['admin_pro', 'admin'])): ?>
                    <div id="configuracion" class="tab-content">
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-cog"></i> Configuración del Sistema</h2>
                            </div>
                            <form method="POST">
                                <input type="hidden" name="accion" value="configurar_sistema">
                                <div class="form-grid">
                                    <div class="form-group">
                                        <label class="form-label">Nombre del Sistema</label>
                                        <input type="text" name="nombre_sistema" class="form-control" value="<?php echo htmlspecialchars($configuraciones['nombre_sistema'] ?? 'Sistema de Gestión de Empleados'); ?>">
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Token de Telegram</label>
                                        <input type="text" name="telegram_token" class="form-control" value="<?php echo htmlspecialchars($configuraciones['telegram_token'] ?? ''); ?>">
                                        <small class="form-text" style="color: var(--text-muted); margin-top: 5px; display: block;">
                                            Token del bot de Telegram para notificaciones
                                        </small>
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Horario Tareas AM</label>
                                        <input type="time" name="horario_am" class="form-control" value="<?php echo htmlspecialchars($configuraciones['horario_am'] ?? '08:00'); ?>">
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Horario Tareas PM</label>
                                        <input type="time" name="horario_pm" class="form-control" value="<?php echo htmlspecialchars($configuraciones['horario_pm'] ?? '14:00'); ?>">
                                    </div>
                                    <div class="form-group">
                                        <label class="form-label">Hora Backup Automático</label>
                                        <input type="time" name="hora_backup" class="form-control" value="<?php echo htmlspecialchars($configuraciones['hora_backup'] ?? '02:00'); ?>">
                                    </div>
                                </div>
                                
                                <div class="form-grid">
                                    <div class="form-check">
                                        <input type="checkbox" name="backup_automatico" id="backup_automatico" class="form-check-input" <?php echo ($configuraciones['backup_automatico'] ?? '1') == '1' ? 'checked' : ''; ?>>
                                        <label for="backup_automatico" class="form-check-label">Backup automático diario</label>
                                    </div>
                                    <div class="form-check">
                                        <input type="checkbox" name="tareas_automaticas" id="tareas_automaticas" class="form-check-input" <?php echo ($configuraciones['tareas_automaticas'] ?? '1') == '1' ? 'checked' : ''; ?>>
                                        <label for="tareas_automaticas" class="form-check-label">Tareas automáticas activadas</label>
                                    </div>
                                </div>
                                
                                <button type="submit" class="btn btn-primary">
                                    <i class="fas fa-save"></i> Guardar Configuración
                                </button>
                            </form>
                        </div>
                        
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-palette"></i> Personalizar Tema</h2>
                            </div>
                            <div class="temas-grid">
                                <?php foreach ($temas as $tema): ?>
                                    <div class="tema-card <?php echo $tema['nombre'] === $tema_actual ? 'activo' : ''; ?>" onclick="cambiarTema('<?php echo $tema['nombre']; ?>')">
                                        <div class="tema-preview" style="background: linear-gradient(135deg, <?php echo json_decode($tema['colores'], true)['primary']; ?>, <?php echo json_decode($tema['colores'], true)['secondary']; ?>);"></div>
                                        <h4><?php echo ucfirst($tema['nombre']); ?></h4>
                                        <?php if ($tema['nombre'] === $tema_actual): ?>
                                            <span class="badge badge-success">Activo</span>
                                        <?php endif; ?>
                                    </div>
                                <?php endforeach; ?>
                            </div>
                        </div>
                        
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-database"></i> Copia de Seguridad</h2>
                            </div>
                            <div style="display: flex; gap: 15px; flex-wrap: wrap; margin-bottom: 20px;">
                                <form method="POST" style="display: inline;">
                                    <input type="hidden" name="accion" value="generar_backup">
                                    <button type="submit" class="btn btn-success">
                                        <i class="fas fa-download"></i> Generar Backup
                                    </button>
                                </form>
                                
                                <form method="POST" enctype="multipart/form-data" style="display: inline;">
                                    <input type="hidden" name="accion" value="subir_backup">
                                    <input type="file" name="backup_file" accept=".sql" required style="display: none;" id="backup-file">
                                    <button type="button" class="btn btn-info" onclick="document.getElementById('backup-file').click()">
                                        <i class="fas fa-upload"></i> Subir Backup
                                    </button>
                                    <button type="submit" class="btn btn-primary" style="display: none;" id="submit-backup">
                                        <i class="fas fa-check"></i> Confirmar
                                    </button>
                                </form>
                            </div>
                            
                            <?php if (!empty($backups)): ?>
                                <h4 style="margin-bottom: 15px;">Backups Disponibles</h4>
                                <div class="table-responsive">
                                    <table class="table">
                                        <thead>
                                            <tr>
                                                <th>Archivo</th>
                                                <th>Tamaño</th>
                                                <th>Fecha</th>
                                                <th>Creado por</th>
                                                <th>Acciones</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            <?php foreach ($backups as $backup): ?>
                                                <tr>
                                                    <td><?php echo htmlspecialchars($backup['nombre_archivo']); ?></td>
                                                    <td><?php echo round($backup['tamano']/1024/1024, 2); ?> MB</td>
                                                    <td><?php echo date('d/m/Y H:i', strtotime($backup['fecha_creacion'])); ?></td>
                                                    <td><?php echo htmlspecialchars($backup['creador_nombre']); ?></td>
                                                    <td>
                                                        <form method="POST" style="display: inline;">
                                                            <input type="hidden" name="accion" value="descargar_backup">
                                                            <input type="hidden" name="backup_id" value="<?php echo $backup['id']; ?>">
                                                            <button type="submit" class="btn btn-primary btn-sm">
                                                                <i class="fas fa-download"></i> Descargar
                                                            </button>
                                                        </form>
                                                    </td>
                                                </tr>
                                            <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<!-- Modal para completar tarea con cámara -->
<div id="modalCompletarTarea" class="modal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">Completar Tarea</h3>
            <button class="close-modal" onclick="cerrarModal('modalCompletarTarea')">&times;</button>
        </div>
        <form id="formCompletarTarea" method="POST">
            <input type="hidden" name="accion" value="completar_tarea">
            <input type="hidden" name="tarea_id" id="tarea_id_completar">
            <input type="hidden" name="foto_data" id="foto_data">
            
            <div id="camera-view">
                <div class="camera-container">
                    <video id="video" autoplay playsinline></video>
                </div>
                <div class="camera-controls">
                    <button type="button" class="btn btn-primary" onclick="capturarFoto()">
                        <i class="fas fa-camera"></i> Capturar Foto
                    </button>
                    <button type="button" class="btn btn-secondary" onclick="reiniciarCamara()">
                        <i class="fas fa-redo"></i> Reiniciar
                    </button>
                </div>
            </div>
            
            <div id="photo-preview" style="display: none;">
                <img id="photo-result" class="photo-preview" alt="Foto capturada">
                <div style="text-align: center; margin-top: 15px;">
                    <button type="button" class="btn btn-secondary" onclick="volverACamara()">
                        <i class="fas fa-arrow-left"></i> Volver a Cámara
                    </button>
                </div>
            </div>
            
            <div style="display: flex; gap: 10px; margin-top: 20px;">
                <button type="submit" class="btn btn-success" id="btn-completar" style="display: none;">
                    <i class="fas fa-check"></i> Marcar como Completada
                </button>
                <button type="button" class="btn btn-secondary" onclick="cerrarModal('modalCompletarTarea')">
                    <i class="fas fa-times"></i> Cancelar
                </button>
            </div>
        </form>
    </div>
</div>

<!-- Modal para verificar tarea -->
<div id="modalVerificarTarea" class="modal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">Verificar Tarea</h3>
            <button class="close-modal" onclick="cerrarModal('modalVerificarTarea')">&times;</button>
        </div>
        <form id="formVerificarTarea" method="POST">
            <input type="hidden" name="accion" value="verificar_tarea">
            <input type="hidden" name="tarea_id" id="tarea_id_verificar">
            
            <div class="form-group">
                <label class="form-label">Calificación</label>
                <div class="rating-stars" id="rating-stars">
                    <span class="rating-star" data-value="1">★</span>
                    <span class="rating-star" data-value="2">★</span>
                    <span class="rating-star" data-value="3">★</span>
                    <span class="rating-star" data-value="4">★</span>
                    <span class="rating-star" data-value="5">★</span>
                </div>
                <input type="hidden" name="calificacion" id="calificacion" value="5" required>
            </div>
            
            <div class="form-group">
                <label class="form-label">Comentario</label>
                <textarea name="comentario" class="form-control" rows="4" placeholder="Comentarios sobre la tarea completada..."></textarea>
            </div>
            
            <div style="display: flex; gap: 10px; margin-top: 20px;">
                <button type="submit" class="btn btn-success">
                    <i class="fas fa-check-double"></i> Verificar Tarea
                </button>
                <button type="button" class="btn btn-secondary" onclick="cerrarModal('modalVerificarTarea')">
                    <i class="fas fa-times"></i> Cancelar
                </button>
            </div>
        </form>
    </div>
</div>

<!-- Modal para ver detalles de tarea - MEJORADO CON FOTOS -->
<div id="modalDetallesTarea" class="modal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">Detalles de la Tarea</h3>
            <button class="close-modal" onclick="cerrarModal('modalDetallesTarea')">&times;</button>
        </div>
        <div id="detalles-tarea-content">
            <!-- Los detalles se cargarán aquí -->
        </div>
    </div>
</div>

<!-- Modal para ver foto de tarea -->
<div id="modalFotoTarea" class="modal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">Foto de la Tarea</h3>
            <button class="close-modal" onclick="cerrarModal('modalFotoTarea')">&times;</button>
        </div>
        <div id="foto-tarea-content">
            <img id="foto-tarea-img" class="photo-preview" alt="Foto de la tarea">
        </div>
    </div>
</div>

<!-- Modal para editar usuario -->
<div id="modalEditarUsuario" class="modal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">Editar Usuario</h3>
            <button class="close-modal" onclick="cerrarModal('modalEditarUsuario')">&times;</button>
        </div>
        <form id="formEditarUsuario" method="POST">
            <input type="hidden" name="accion" value="editar_usuario">
            <input type="hidden" name="user_id" id="user_id_editar">
            
            <div class="form-group">
                <label class="form-label">Nombre Completo</label>
                <input type="text" name="nombre" id="editar_nombre" class="form-control" required>
            </div>
            
            <div class="form-group">
                <label class="form-label">ID de Telegram</label>
                <input type="text" name="telegram_id" id="editar_telegram_id" class="form-control">
            </div>
            
            <div class="form-group">
                <label class="form-label">Turno</label>
                <select name="turno" id="editar_turno" class="form-control">
                    <option value="AM">AM</option>
                    <option value="PM">PM</option>
                </select>
            </div>
            
            <div class="form-group">
                <label class="form-label">Pasillo Asignado</label>
                <input type="text" name="pasillo" id="editar_pasillo" class="form-control">
            </div>
            
            <div class="form-group">
                <label class="form-label">Día Libre</label>
                <select name="dia_libre" id="editar_dia_libre" class="form-control">
                    <option value="">Seleccionar</option>
                    <option value="Lunes">Lunes</option>
                    <option value="Martes">Martes</option>
                    <option value="Miércoles">Miércoles</option>
                    <option value="Jueves">Jueves</option>
                    <option value="Viernes">Viernes</option>
                    <option value="Sábado">Sábado</option>
                    <option value="Domingo">Domingo</option>
                </select>
            </div>
            
            <div style="display: flex; gap: 10px; margin-top: 20px;">
                <button type="submit" class="btn btn-success">
                    <i class="fas fa-save"></i> Guardar Cambios
                </button>
                <button type="button" class="btn btn-secondary" onclick="cerrarModal('modalEditarUsuario')">
                    <i class="fas fa-times"></i> Cancelar
                </button>
            </div>
        </form>
    </div>
</div>

<script>
    // Variables globales para la cámara
    let stream = null;
    let photoData = '';
    let requiereFoto = false;
    
    // Navegación entre pestañas
    function mostrarTab(tabId) {
        // Remover active de todos
        document.querySelectorAll('.nav-menu a').forEach(a => a.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
        
        // Agregar active al seleccionado
        const tabLink = document.querySelector(`[data-tab="${tabId}"]`);
        if (tabLink) {
            tabLink.classList.add('active');
        }
        document.getElementById(tabId).classList.add('active');
        
        // Actualizar título
        const pageTitle = document.getElementById('page-title');
        if (tabLink) {
            const icon = tabLink.querySelector('i').className;
            const text = tabLink.textContent.trim();
            pageTitle.innerHTML = `<i class="${icon}"></i> ${text}`;
        }
        
        // Cerrar menú en móvil
        cerrarMenuMovil();
    }
    
    document.querySelectorAll('.nav-menu a').forEach(link => {
        link.addEventListener('click', function(e) {
            if (this.getAttribute('href') === '#') {
                e.preventDefault();
                const tabId = this.getAttribute('data-tab');
                mostrarTab(tabId);
            }
        });
    });
    
    // Toggle sidebar en móvil
    function toggleSidebar() {
        document.getElementById('sidebar').classList.toggle('active');
    }
    
    // Cerrar menú en móvil
    function cerrarMenuMovil() {
        if (window.innerWidth <= 1024) {
            document.getElementById('sidebar').classList.remove('active');
        }
    }
    
    // Completar tarea con cámara
    function completarTarea(tareaId, necesitaFoto = false) {
        document.getElementById('tarea_id_completar').value = tareaId;
        requiereFoto = necesitaFoto;
        
        if (necesitaFoto) {
            document.getElementById('modalCompletarTarea').style.display = 'flex';
            iniciarCamara();
        } else {
            // Si no requiere foto, completar directamente
            if (confirm('¿Estás seguro de que quieres marcar esta tarea como completada?')) {
                document.getElementById('foto_data').value = '';
                document.getElementById('formCompletarTarea').submit();
            }
        }
    }
    
    // Iniciar cámara
    async function iniciarCamara() {
        try {
            stream = await navigator.mediaDevices.getUserMedia({ 
                video: { 
                    facingMode: 'environment',
                    width: { ideal: 1280 },
                    height: { ideal: 720 }
                } 
            });
            const video = document.getElementById('video');
            video.srcObject = stream;
            
            // Mostrar vista de cámara
            document.getElementById('camera-view').style.display = 'block';
            document.getElementById('photo-preview').style.display = 'none';
            document.getElementById('btn-completar').style.display = 'none';
            photoData = '';
            
        } catch (err) {
            alert('Error al acceder a la cámara: ' + err.message);
            console.error('Error cámara:', err);
            // Si no se puede acceder a la cámara, permitir completar sin foto
            document.getElementById('btn-completar').style.display = 'block';
        }
    }
    
    // Capturar foto
    function capturarFoto() {
        const video = document.getElementById('video');
        const canvas = document.createElement('canvas');
        const context = canvas.getContext('2d');
        
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
        
        // Convertir a data URL
        photoData = canvas.toDataURL('image/png');
        
        // Mostrar preview
        document.getElementById('photo-result').src = photoData;
        document.getElementById('camera-view').style.display = 'none';
        document.getElementById('photo-preview').style.display = 'block';
        document.getElementById('btn-completar').style.display = 'block';
        
        // Detener stream
        if (stream) {
            stream.getTracks().forEach(track => track.stop());
        }
        
        // Asignar foto al campo hidden
        document.getElementById('foto_data').value = photoData;
    }
    
    // Reiniciar cámara
    function reiniciarCamara() {
        if (stream) {
            stream.getTracks().forEach(track => track.stop());
        }
        iniciarCamara();
    }
    
    // Volver a cámara
    function volverACamara() {
        document.getElementById('camera-view').style.display = 'block';
        document.getElementById('photo-preview').style.display = 'none';
        document.getElementById('btn-completar').style.display = 'none';
        iniciarCamara();
    }
    
    // Verificar tarea
    function verificarTarea(tareaId) {
        document.getElementById('tarea_id_verificar').value = tareaId;
        document.getElementById('modalVerificarTarea').style.display = 'flex';
    }
    
    // Ver detalles de tarea - MEJORADO
    async function verDetallesTarea(tareaId) {
        try {
            const response = await fetch(`obtener_detalles_tarea.php?id=${tareaId}`);
            const detalles = await response.text();
            document.getElementById('detalles-tarea-content').innerHTML = detalles;
            document.getElementById('modalDetallesTarea').style.display = 'flex';
        } catch (error) {
            alert('Error al cargar detalles de la tarea');
            console.error('Error:', error);
        }
    }
    
    // Ver foto de tarea
    function verFotoTarea(rutaFoto) {
        document.getElementById('foto-tarea-img').src = rutaFoto;
        document.getElementById('modalFotoTarea').style.display = 'flex';
    }
    
    // Editar usuario
    async function editarUsuario(userId) {
        try {
            const response = await fetch(`obtener_datos_usuario.php?id=${userId}`);
            const usuario = await response.json();
            
            document.getElementById('user_id_editar').value = usuario.id;
            document.getElementById('editar_nombre').value = usuario.nombre;
            document.getElementById('editar_telegram_id').value = usuario.telegram_id || '';
            document.getElementById('editar_turno').value = usuario.turno;
            document.getElementById('editar_pasillo').value = usuario.pasillo_asignado || '';
            document.getElementById('editar_dia_libre').value = usuario.dia_libre || '';
            
            document.getElementById('modalEditarUsuario').style.display = 'flex';
        } catch (error) {
            alert('Error al cargar datos del usuario');
            console.error('Error:', error);
        }
    }
    
    // Eliminar usuario
    function eliminarUsuario(userId) {
        if (confirm('¿Está seguro de que desea eliminar este usuario? Esta acción no se puede deshacer.')) {
            const form = document.createElement('form');
            form.method = 'POST';
            form.innerHTML = `
                <input type="hidden" name="accion" value="eliminar_usuario">
                <input type="hidden" name="user_id" value="${userId}">
            `;
            document.body.appendChild(form);
            form.submit();
        }
    }
    
    // Cambiar tema
    function cambiarTema(temaNombre) {
        if (confirm(`¿Estás seguro de que quieres cambiar al tema ${temaNombre}?`)) {
            const form = document.createElement('form');
            form.method = 'POST';
            form.innerHTML = `
                <input type="hidden" name="accion" value="cambiar_tema">
                <input type="hidden" name="tema_nombre" value="${temaNombre}">
            `;
            document.body.appendChild(form);
            form.submit();
        }
    }
    
    // Cerrar modal
    function cerrarModal(modalId) {
        document.getElementById(modalId).style.display = 'none';
        
        // Detener cámara si está activa
        if (stream) {
            stream.getTracks().forEach(track => track.stop());
            stream = null;
        }
    }
    
    // Cerrar modal al hacer clic fuera
    window.onclick = function(event) {
        document.querySelectorAll('.modal').forEach(modal => {
            if (event.target === modal) {
                cerrarModal(modal.id);
            }
        });
    }
    
    // Actualizar hora en tiempo real
    function updateTime() {
        const now = new Date();
        const options = { 
            timeZone: 'America/Santo_Domingo',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        };
        const formatter = new Intl.DateTimeFormat('es-DO', options);
        document.getElementById('current-time').textContent = formatter.format(now);
    }
    
    setInterval(updateTime, 1000);
    updateTime();
    
    // Sistema de calificación con estrellas
    document.addEventListener('DOMContentLoaded', function() {
        const stars = document.querySelectorAll('.rating-star');
        const ratingInput = document.getElementById('calificacion');
        
        stars.forEach(star => {
            star.addEventListener('click', function() {
                const value = this.getAttribute('data-value');
                ratingInput.value = value;
                
                stars.forEach(s => {
                    if (s.getAttribute('data-value') <= value) {
                        s.classList.add('active');
                    } else {
                        s.classList.remove('active');
                    }
                });
            });
        });
    });
    
    // Cerrar sidebar al hacer clic fuera en móvil
    document.addEventListener('click', function(e) {
        if (window.innerWidth <= 1024) {
            const sidebar = document.getElementById('sidebar');
            const mobileBtn = document.querySelector('.mobile-menu-btn');
            if (!sidebar.contains(e.target) && !mobileBtn.contains(e.target)) {
                sidebar.classList.remove('active');
            }
        }
    });
    
    // Validación de formularios
    document.addEventListener('DOMContentLoaded', function() {
        const forms = document.querySelectorAll('form');
        forms.forEach(form => {
            form.addEventListener('submit', function(e) {
                const requiredFields = form.querySelectorAll('[required]');
                let valid = true;
                
                requiredFields.forEach(field => {
                    if (!field.value.trim()) {
                        valid = false;
                        field.style.borderColor = 'var(--danger)';
                    } else {
                        field.style.borderColor = '';
                    }
                });
                
                if (!valid) {
                    e.preventDefault();
                    alert('Por favor, complete todos los campos requeridos.');
                }
            });
        });
        
        // Mostrar botón de confirmación al seleccionar archivo de backup
        const backupFileInput = document.getElementById('backup-file');
        const submitBackupBtn = document.getElementById('submit-backup');
        
        if (backupFileInput && submitBackupBtn) {
            backupFileInput.addEventListener('change', function() {
                if (this.files.length > 0) {
                    submitBackupBtn.style.display = 'inline-block';
                } else {
                    submitBackupBtn.style.display = 'none';
                }
            });
        }
    });
</script>
</body>
</html>
EOF

# Crear archivos auxiliares mejorados
cat > obtener_detalles_tarea.php << 'EOF'
<?php
require_once 'config.php';
session_start();

if (!isset($_SESSION['usuario_id']) || !in_array($_SESSION['rol'], ['admin_pro', 'admin'])) {
    exit('Acceso denegado');
}

$tarea_id = $_GET['id'] ?? 0;

try {
    $stmt = $pdo->prepare("
        SELECT t.*, u.nombre as empleado_nombre, u2.nombre as admin_nombre 
        FROM tareas t 
        LEFT JOIN usuarios u ON t.empleado_id = u.id 
        LEFT JOIN usuarios u2 ON t.administrador_id = u2.id 
        WHERE t.id = ?
    ");
    $stmt->execute([$tarea_id]);
    $tarea = $stmt->fetch();
    
    if ($tarea) {
        echo '<div class="detalles-tarea">';
        echo '<h4 style="color: var(--primary); margin-bottom: 15px;">' . htmlspecialchars($tarea['titulo']) . '</h4>';
        echo '<div style="margin-bottom: 10px;"><strong>Descripción:</strong> ' . nl2br(htmlspecialchars($tarea['descripcion'])) . '</div>';
        echo '<div style="margin-bottom: 10px;"><strong>Empleado:</strong> ' . htmlspecialchars($tarea['empleado_nombre']) . '</div>';
        echo '<div style="margin-bottom: 10px;"><strong>Asignado por:</strong> ' . htmlspecialchars($tarea['admin_nombre']) . '</div>';
        echo '<div style="margin-bottom: 10px;"><strong>Fecha asignación:</strong> ' . date('d/m/Y H:i', strtotime($tarea['fecha_asignacion'])) . '</div>';
        
        if ($tarea['fecha_vencimiento']) {
            echo '<div style="margin-bottom: 10px;"><strong>Vence:</strong> ' . date('d/m/Y H:i', strtotime($tarea['fecha_vencimiento'])) . '</div>';
        }
        
        if ($tarea['fecha_completado']) {
            echo '<div style="margin-bottom: 10px;"><strong>Completada:</strong> ' . date('d/m/Y H:i', strtotime($tarea['fecha_completado'])) . '</div>';
        }
        
        echo '<div style="margin-bottom: 10px;"><strong>Estado:</strong> ' . ucfirst($tarea['estado']) . '</div>';
        
        if ($tarea['calificacion']) {
            echo '<div style="margin-bottom: 10px;"><strong>Calificación:</strong> ' . str_repeat('★', $tarea['calificacion']) . '</div>';
        }
        
        if ($tarea['comentario_revision']) {
            echo '<div style="margin-bottom: 10px;"><strong>Comentario:</strong> ' . nl2br(htmlspecialchars($tarea['comentario_revision'])) . '</div>';
        }
        
        // CORRECCIÓN: Mostrar foto si existe
        if ($tarea['foto_tarea'] && file_exists($tarea['foto_tarea'])) {
            echo '<div style="margin-bottom: 10px;"><strong>Foto de evidencia:</strong><br>';
            echo '<img src="' . $tarea['foto_tarea'] . '" style="max-width: 100%; max-height: 300px; border-radius: 10px; margin-top: 10px; border: 2px solid var(--primary);">';
            echo '</div>';
        } else {
            echo '<div style="margin-bottom: 10px;"><strong>Foto de evidencia:</strong> No se adjuntó foto</div>';
        }
        
        echo '</div>';
    } else {
        echo '<p>Tarea no encontrada</p>';
    }
} catch(Exception $e) {
    echo '<p>Error al cargar detalles: ' . htmlspecialchars($e->getMessage()) . '</p>';
}
?>
EOF

cat > obtener_datos_usuario.php << 'EOF'
<?php
require_once 'config.php';
session_start();

if (!isset($_SESSION['usuario_id']) || !in_array($_SESSION['rol'], ['admin_pro', 'admin'])) {
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Acceso denegado']);
    exit;
}

$user_id = $_GET['id'] ?? 0;

try {
    $stmt = $pdo->prepare("SELECT * FROM usuarios WHERE id = ?");
    $stmt->execute([$user_id]);
    $usuario = $stmt->fetch();
    
    if ($usuario) {
        header('Content-Type: application/json');
        echo json_encode($usuario);
    } else {
        header('Content-Type: application/json');
        echo json_encode(['error' => 'Usuario no encontrado']);
    }
} catch(Exception $e) {
    header('Content-Type: application/json');
    echo json_encode(['error' => $e->getMessage()]);
}
?>
EOF

# Crear script para tareas automáticas
cat > tareas_automaticas.php << 'EOF'
<?php
require_once 'config.php';

// Obtener turno desde argumento de línea de comandos
$turno = $argv[1] ?? 'AM';

try {
    // Asignar tareas automáticas de montacarga
    $resultado = asignar_tareas_montacarga($turno);
    
    if ($resultado['success']) {
        error_log("Tareas automáticas de montacarga asignadas exitosamente para el turno " . $turno);
    } else {
        error_log("Error asignando tareas automáticas: " . $resultado['error']);
    }
} catch(Exception $e) {
    error_log("Error en tareas automáticas: " . $e->getMessage());
}
?>
EOF

# Crear script para backup automático
cat > backup_automatico.php << 'EOF'
<?php
require_once 'config.php';

try {
    // Verificar si el backup automático está activado
    $stmt = $pdo->query("SELECT valor FROM configuraciones WHERE clave = 'backup_automatico'");
    $config = $stmt->fetch();
    
    if ($config && $config['valor'] == '1') {
        // Generar backup automático
        $resultado = generar_backup(1); // Usuario ID 1 (admin)
        
        if ($resultado['success']) {
            error_log("Backup automático generado: " . $resultado['nombre']);
        } else {
            error_log("Error en backup automático: " . $resultado['error']);
        }
    }
} catch(Exception $e) {
    error_log("Error en backup automático: " . $e->getMessage());
}
?>
EOF

# Configurar permisos
print_message "Configurando permisos..."
mkdir -p /var/www/backups
mkdir -p /var/www/uploads/tareas
chown -R www-data:www-data $PANEL_DIR
chown -R www-data:www-data /var/www/backups
chown -R www-data:www-data /var/www/uploads
chmod -R 755 $PANEL_DIR
chmod -R 755 /var/www/backups
chmod -R 755 /var/www/uploads

# Configurar Apache
print_message "Configurando Apache..."
cat > /etc/apache2/sites-available/gestion-empleados.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $PANEL_DIR
    
    <Directory $PANEL_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/gestion_empleados_error.log
    CustomLog \${APACHE_LOG_DIR}/gestion_empleados_access.log combined
</VirtualHost>
EOF

a2ensite gestion-empleados.conf
a2dissite 000-default.conf
a2enmod rewrite

# Configurar cron jobs para tareas automáticas y backups
print_message "Configurando tareas automáticas y backups..."
(crontab -l 2>/dev/null | grep -v "$PANEL_DIR/tareas_automaticas.php" | grep -v "$PANEL_DIR/backup_automatico.php"; 
echo "0 8 * * * /usr/bin/php $PANEL_DIR/tareas_automaticas.php AM >> /var/log/tareas_automaticas.log 2>&1";
echo "0 14 * * * /usr/bin/php $PANEL_DIR/tareas_automaticas.php PM >> /var/log/tareas_automaticas.log 2>&1";
echo "0 2 * * * /usr/bin/php $PANEL_DIR/backup_automatico.php >> /var/log/backup_automatico.log 2>&1") | crontab -

# Configurar Telegram si se proporcionó
if [ ! -z "$TELEGRAM_TOKEN" ]; then
    print_message "Configurando bot de Telegram..."
    mysql gestion_empleados -e "UPDATE configuraciones SET valor='$TELEGRAM_TOKEN' WHERE clave='telegram_token'"
fi

# Configurar dominio
if [ ! -z "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ]; then
    print_message "Configurando dominio: $DOMAIN"
    mysql gestion_empleados -e "UPDATE configuraciones SET valor='$DOMAIN' WHERE clave='dominio'"
    
    read -p "¿Configurar SSL con Certbot? (s/n): " setup_ssl
    if [[ $setup_ssl == "s" || $setup_ssl == "S" ]]; then
        apt install -y certbot python3-certbot-apache
        certbot --apache -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect
    fi
fi

# Crear administrador pro personalizado
if [ ! -z "$ADMIN_USER" ] && [ ! -z "$ADMIN_PASS" ]; then
    print_message "Creando administrador pro personalizado..."
    ADMIN_PASS_HASH=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_DEFAULT);")
    mysql gestion_empleados -e "INSERT IGNORE INTO usuarios (username, password, nombre, rol, activo) VALUES ('$ADMIN_USER', '$ADMIN_PASS_HASH', 'Administrador Pro', 'admin_pro', TRUE)"
fi

# Reiniciar servicios
print_message "Reiniciando servicios..."
systemctl restart apache2
systemctl enable apache2

# Configurar firewall
ufw allow 80
ufw allow 443
ufw allow 22

print_success "✅ Instalación completada exitosamente!"
echo ""
print_message "=== INFORMACIÓN DEL SISTEMA ==="
echo "🌐 URL del panel: http://$DOMAIN"
echo "👤 Usuario administrador: $ADMIN_USER"
echo "📁 Directorio del panel: $PANEL_DIR"
echo "🗄️ Base de datos: gestion_empleados"
echo "🔧 Usuario BD: gestion_user"
echo "🔄 Tareas automáticas: AM 08:00, PM 14:00"
echo "💾 Backup automático: 02:00"
echo ""
print_warning "🔒 Guarde esta información en un lugar seguro"
print_message "🚀 El sistema está listo para usar!"

# Mostrar información final
echo ""
print_info "📋 RESUMEN DE MEJORAS IMPLEMENTADAS v2.2:"
echo "• ✅ SISTEMA DE RECOMENDACIONES COMPLETAMENTE CORREGIDO"
echo "• ✅ ASIGNACIÓN MÚLTIPLE DE TAREAS CORREGIDA"
echo "• ✅ FOTOS DE TAREAS VISIBLES PARA ADMINISTRADORES"
echo "• ✅ INTERFAZ MEJORADA Y RESPONSIVE"
echo "• ✅ DASHBOARD CON NAVEGACIÓN MEJORADA"
echo "• ✅ SISTEMA DE TEMAS PERSONALIZABLES"
echo "• ✅ NOTIFICACIONES POR TELEGRAM MEJORADAS"
echo ""
print_success "🎉 El sistema v2.2 está completamente corregido y listo para producción!"
EOF

## Hacer el script ejecutable
chmod +x instalacion_panel_v2.2.sh

print_success "✅ Script de instalación v2.2 creado exitosamente!"
print_message "📝 Para ejecutar: sudo ./instalacion_panel_v2.2.sh"
echo ""
print_info "🔧 CORRECCIONES IMPLEMENTADAS v2.2:"
echo "• ✅ ASIGNACIÓN MÚLTIPLE DE TAREAS: Ahora funciona correctamente"
echo "• ✅ FOTOS DE TAREAS: Los administradores pueden ver las fotos enviadas"
echo "• ✅ INTERFAZ MEJORADA: Diseño más moderno y organizado"
echo "• ✅ DASHBOARD INTERACTIVO: Las tarjetas son clickeables para navegar"
echo "• ✅ RESPONSIVE MEJORADO: Mejor adaptación a dispositivos móviles"
echo "• ✅ SISTEMA DE PATANAS: Completamente funcional y corregido"
echo ""
print_success "🚀 El script v2.2 resuelve TODOS los problemas reportados!"