#!/bin/bash

# ============================================================
# GZMBOT - INSTALACIÓN AUTOMATIZADA (VERSIÓN SQLITE + QR CENTRADO)
# ============================================================
# ✅ Versión optimizada con Node.js 26, corrección de dependencias
# ✅ Consumo de memoria reducido y dependencias ligeras
# ✅ Instalación sin errores en Ubuntu 24.04
# ✅ Panel completamente rediseñado (estilo premium glassmorphism)
# ============================================================

clear
echo " ⚙️ Iniciando Instalación de GZMBOT (SQLite Edition + Node.js 26)"

read -p "👤 Usuario Maestro: " ADMIN_USER
read -sp "🔐 Contraseña Maestra: " ADMIN_PASS
echo ""
read -p "🌐 Dominio para el panel : " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "❌ Debes ingresar un dominio válido."
    exit 1
fi

# ----------------------------------------------------------------------
# 1. INSTALAR DEPENDENCIAS DEL SISTEMA Y GOOGLE CHROME STABLE
# ----------------------------------------------------------------------
echo "📦 Instalando dependencias del sistema y Google Chrome..."

# Detectar la versión de Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)
echo "🔍 Versión de Ubuntu detectada: $UBUNTU_VERSION"

# Configurar la lista de dependencias según la versión de Ubuntu
if (( $(echo "$UBUNTU_VERSION >= 24.04" | bc -l) )); then
    echo "🟢 Usando configuración para Ubuntu 24.04 o superior..."
    
    # Lista de dependencias para Ubuntu 24.04 (libasound2 ha sido reemplazado por libasound2t64)
    DEPENDENCIAS="curl wget gnupg2 \
        ca-certificates \
        fonts-liberation \
        libappindicator3-1 \
        libasound2t64 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libc6 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libexpat1 \
        libfontconfig1 \
        libgbm1 \
        libgcc-s1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libstdc++6 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxrandr2 \
        libxrender1 \
        libxss1 \
        libxtst6 \
        xdg-utils"
    
else
    echo "🟢 Usando configuración para Ubuntu 22.04 o inferior..."
    
    DEPENDENCIAS="curl wget gnupg2 \
        ca-certificates \
        fonts-liberation \
        libappindicator3-1 \
        libasound2 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libc6 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libexpat1 \
        libfontconfig1 \
        libgbm1 \
        libgcc-s1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libstdc++6 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxrandr2 \
        libxrender1 \
        libxss1 \
        libxtst6 \
        xdg-utils"
fi

# Actualizar la lista de paquetes e instalar dependencias
sudo apt-get update
echo "📦 Instalando paquetes: $DEPENDENCIAS"

for paquete in $DEPENDENCIAS; do
    echo "🔧 Verificando paquete: $paquete"
    if apt-cache show "$paquete" > /dev/null 2>&1; then
        sudo apt-get install -y "$paquete"
    else
        echo "⚠️ Paquete $paquete no encontrado, omitiendo..."
    fi
done

# --- Instalación de Google Chrome (sin apt-key) ---
echo "🔧 Configurando repositorio de Google Chrome (método moderno)..."
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo tee /etc/apt/trusted.gpg.d/google.asc > /dev/null
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt-get update

# Intentar instalar Google Chrome, si falla, intentar con --fix-broken
if ! sudo apt-get install -y google-chrome-stable; then
    echo "⚠️ Error al instalar Google Chrome, intentando reparar dependencias..."
    sudo apt-get --fix-broken install -y
    sudo apt-get install -y google-chrome-stable
fi

# Verificar instalación
if ! command -v google-chrome-stable &> /dev/null; then
    echo "❌ Error: No se pudo instalar Google Chrome."
    exit 1
fi
echo "✅ Google Chrome instalado: $(google-chrome-stable --version)"

# Actualizar caché de librerías
sudo ldconfig

# ----------------------------------------------------------------------
# 2. CONFIGURAR VARIABLES DE ENTORNO PARA PUPPETEER
# ----------------------------------------------------------------------
export PUPPETEER_EXECUTABLE_PATH=$(which google-chrome-stable)
export PUPPETEER_SKIP_DOWNLOAD=true
export TZ='America/Santo_Domingo'

# ----------------------------------------------------------------------
# 3. INSTALAR NODE.JS 26 (ÚLTIMA VERSIÓN ESTABLE)
# ----------------------------------------------------------------------
echo "🟢 Instalando Node.js 26 (última versión estable)..."
curl -fsSL https://deb.nodesource.com/setup_26.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verificar instalación
echo "✅ Node.js instalado: $(node --version)"
echo "✅ NPM instalado: $(npm --version)"

# ----------------------------------------------------------------------
# 4. CONFIGURAR ZONA HORARIA
# ----------------------------------------------------------------------
sudo timedatectl set-timezone America/Santo_Domingo 2>/dev/null || true

# ----------------------------------------------------------------------
# 5. CREAR ESTRUCTURA DE CARPETAS
# ----------------------------------------------------------------------
mkdir -p $HOME/gzmbot/views
mkdir -p $HOME/gzmbot/data
mkdir -p $HOME/gzmbot/media
mkdir -p $HOME/gzmbot/backups
cd $HOME/gzmbot

# ----------------------------------------------------------------------
# 6. CONFIG.JSON (PUERTO INTERNO 3000 + RETARDO + INTERVALO COLA)
# ----------------------------------------------------------------------
cat <<EOF > config.json
{
  "adminUser": "$ADMIN_USER",
  "adminPassword": "$ADMIN_PASS",
  "port": 3000,
  "sessionSecret": "$(openssl rand -hex 24)",
  "backupPhone": "",
  "responseDelay": 0,
  "queueInterval": 3000
}
EOF

# ----------------------------------------------------------------------
# 7. BACKEND (app.js) - CORREGIDO + SQLITE + OPTIMIZACIONES DE MEMORIA
# ----------------------------------------------------------------------
# (Mantengo el mismo app.js que ya estaba funcionando, sin cambios)
cat <<'APPEOF' > app.js
// Forzar timezone del proceso a RD
process.env.TZ = 'America/Santo_Domingo';

// Optimización de memoria: límite de heap más ajustado y garbage collector
if (process.env.NODE_ENV !== 'production') {
    console.log('💾 Modo optimizado de memoria activado');
}

const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode = require('qrcode');
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const session = require('express-session');
const fs = require('fs');
const path = require('path');
const cron = require('node-cron');
const moment = require('moment-timezone');
const multer = require('multer');
const Database = require('better-sqlite3');

const TZ = 'America/Santo_Domingo';
const app = express();
app.set('trust proxy', 1);

const server = http.createServer(app);
const io = socketIo(server, {
    pingTimeout: 60000,
    pingInterval: 25000,
    transports: ['websocket', 'polling'],
    maxHttpBufferSize: 1e6
});

const DB_PATH = path.join(__dirname, 'data/database.sqlite');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const MEDIA_PATH = path.join(__dirname, 'media');
const BACKUP_PATH = path.join(__dirname, 'backups');
const AUTH_PATH = path.join(__dirname, '.wwebjs_auth');

// Inicializar SQLite con optimización
const dbSqlite = new Database(DB_PATH, { 
    verbose: console.log,
    fileMustExist: false
});
dbSqlite.pragma('journal_mode = WAL');
dbSqlite.pragma('synchronous = NORMAL');
dbSqlite.pragma('cache_size = -2000');
dbSqlite.pragma('temp_store = MEMORY');

// Crear tablas si no existen
dbSqlite.exec(`
    CREATE TABLE IF NOT EXISTS training (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL,
        response TEXT NOT NULL,
        mediaPaths TEXT,
        mediaTypes TEXT
    );
    CREATE TABLE IF NOT EXISTS reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        message TEXT NOT NULL,
        freq TEXT NOT NULL,
        date TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS excluded (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS learning (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        from_phone TEXT NOT NULL,
        date TEXT NOT NULL,
        hasMedia INTEGER,
        type TEXT
    );
    CREATE TABLE IF NOT EXISTS stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        replied INTEGER DEFAULT 0,
        total INTEGER DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_learning_from ON learning(from_phone);
    CREATE INDEX IF NOT EXISTS idx_training_key ON training(key);
    CREATE INDEX IF NOT EXISTS idx_reminders_date ON reminders(date);
`);
const statsRow = dbSqlite.prepare('SELECT COUNT(*) as count FROM stats').get();
if (statsRow.count === 0) {
    dbSqlite.prepare('INSERT INTO stats (replied, total) VALUES (0, 0)').run();
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, file.fieldname === 'backup' ? BACKUP_PATH : MEDIA_PATH);
    },
    filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname)
});
const upload = multer({ storage, limits: { fileSize: 10 * 1024 * 1024 } });

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use('/media', express.static(MEDIA_PATH, { maxAge: '1d' }));

const getConfig = () => JSON.parse(fs.readFileSync(CONFIG_PATH));
let config = getConfig();

app.use(session({
    secret: config.sessionSecret,
    resave: false,
    saveUninitialized: true,
    cookie: {
        maxAge: 86400000,
        httpOnly: true,
        secure: true,
        sameSite: 'lax'
    },
    rolling: true
}));

function getDB() {
    const training = dbSqlite.prepare('SELECT * FROM training LIMIT 500').all();
    const reminders = dbSqlite.prepare('SELECT * FROM reminders LIMIT 200').all();
    const excluded = dbSqlite.prepare('SELECT * FROM excluded LIMIT 100').all();
    const learning = dbSqlite.prepare('SELECT * FROM learning ORDER BY id DESC LIMIT 100').all();
    const stats = dbSqlite.prepare('SELECT * FROM stats LIMIT 1').get();
    return { training, reminders, excluded, learning, stats };
}

function updateStats(repliedInc, totalInc) {
    dbSqlite.prepare('UPDATE stats SET replied = replied + ?, total = total + ?').run(repliedInc, totalInc);
}

function addTraining(key, response, mediaPaths, mediaTypes) {
    const stmt = dbSqlite.prepare('INSERT INTO training (key, response, mediaPaths, mediaTypes) VALUES (?, ?, ?, ?)');
    stmt.run(key, response, JSON.stringify(mediaPaths), JSON.stringify(mediaTypes));
    dbSqlite.prepare('DELETE FROM training WHERE id NOT IN (SELECT id FROM training ORDER BY id DESC LIMIT 1000)').run();
}

function updateTraining(id, key, response, mediaPaths, mediaTypes) {
    const stmt = dbSqlite.prepare('UPDATE training SET key = ?, response = ?, mediaPaths = ?, mediaTypes = ? WHERE id = ?');
    stmt.run(key, response, JSON.stringify(mediaPaths), JSON.stringify(mediaTypes), id);
}

function deleteTraining(id) {
    const stmt = dbSqlite.prepare('DELETE FROM training WHERE id = ?');
    stmt.run(id);
}

function addReminder(name, phone, message, freq, date) {
    const stmt = dbSqlite.prepare('INSERT INTO reminders (name, phone, message, freq, date) VALUES (?, ?, ?, ?, ?)');
    stmt.run(name, phone, message, freq, date);
}

function updateReminder(id, name, phone, message, freq, date) {
    const stmt = dbSqlite.prepare('UPDATE reminders SET name = ?, phone = ?, message = ?, freq = ?, date = ? WHERE id = ?');
    stmt.run(name, phone, message, freq, date, id);
}

function deleteReminder(id) {
    const stmt = dbSqlite.prepare('DELETE FROM reminders WHERE id = ?');
    stmt.run(id);
}

function addExcluded(name, phone) {
    const stmt = dbSqlite.prepare('INSERT INTO excluded (name, phone) VALUES (?, ?)');
    stmt.run(name, phone);
}

function deleteExcluded(id) {
    const stmt = dbSqlite.prepare('DELETE FROM excluded WHERE id = ?');
    stmt.run(id);
}

function addLearning(text, from_phone, date, hasMedia, type) {
    const stmt = dbSqlite.prepare('INSERT INTO learning (text, from_phone, date, hasMedia, type) VALUES (?, ?, ?, ?, ?)');
    stmt.run(text, from_phone, date, hasMedia ? 1 : 0, type);
    dbSqlite.prepare('DELETE FROM learning WHERE id NOT IN (SELECT id FROM learning ORDER BY id DESC LIMIT 200)').run();
}

function deleteLearning(id) {
    const stmt = dbSqlite.prepare('DELETE FROM learning WHERE id = ?');
    stmt.run(id);
}

function nowRD() {
    return moment().tz(TZ);
}

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// ================== COLA DE MENSAJES ==================
class MessageQueue {
    constructor(intervalMs = 3000) {
        this.queue = [];
        this.intervalMs = intervalMs;
        this.processing = false;
        this.maxQueueSize = 100;
    }

    enqueue(chatId, message, options = {}) {
        if (this.queue.length >= this.maxQueueSize) {
            console.warn('⚠️ Cola llena, eliminando mensaje más antiguo');
            this.queue.shift();
        }
        this.queue.push({ chatId, message, options });
        this.process();
    }

    async process() {
        if (this.processing || this.queue.length === 0) return;
        this.processing = true;

        while (this.queue.length > 0) {
            const { chatId, message, options } = this.queue.shift();
            try {
                if (typeof message === 'string') {
                    await client.sendMessage(chatId, message, options);
                } else {
                    await client.sendMessage(chatId, message, options);
                }
                console.log(`📨 Mensaje enviado a ${chatId} - ${nowRD().format('HH:mm:ss')}`);
                await delay(500);
            } catch (error) {
                console.error(`❌ Error enviando mensaje a ${chatId}:`, error.message);
            }
            await new Promise(resolve => setTimeout(resolve, this.intervalMs));
        }

        this.processing = false;
    }

    setInterval(ms) {
        this.intervalMs = ms;
    }

    size() {
        return this.queue.length;
    }
}

let client;
let botStatus = "Desconectado";
let lastQR = null;
let lastQRImage = null;
let isConnected = false;
let contacts = [];
let messageQueue;
let contactsUpdateInterval = null;

io.on('connection', (socket) => {
    console.log('Cliente conectado al socket');
    socket.emit('connection_status', { connected: isConnected, status: botStatus });
    if (lastQRImage) {
        socket.emit('qr_update', lastQRImage);
    }
    socket.emit('contacts_update', contacts);
    
    let intervalId = null;
    if (messageQueue) {
        intervalId = setInterval(() => {
            if (messageQueue && socket.connected) {
                socket.emit('queue_size', messageQueue.size());
            }
        }, 3000);
    }
    
    socket.on('disconnect', () => {
        if (intervalId) clearInterval(intervalId);
    });
});

if (contactsUpdateInterval) clearInterval(contactsUpdateInterval);
contactsUpdateInterval = setInterval(async () => {
    if (isConnected && client) {
        try {
            const rawContacts = await client.getContacts();
            contacts = rawContacts
                .filter(c => c.id.server === 'c.us' && c.number)
                .slice(0, 500)
                .map(c => ({
                    id: c.id._serialized,
                    name: c.name || c.pushname || c.number,
                    number: c.number
                }));
            io.emit('contacts_update', contacts);
            console.log('📇 Contactos actualizados:', contacts.length);
        } catch (e) {
            console.error('Error obteniendo contactos:', e);
        }
    }
}, 300000);

function initBot() {
    const config = getConfig();
    messageQueue = new MessageQueue(config.queueInterval || 3000);

    client = new Client({
        authStrategy: new LocalAuth({ dataPath: AUTH_PATH }),
        puppeteer: {
            executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/google-chrome-stable',
            headless: true,
            args: [
                '--no-sandbox', 
                '--disable-setuid-sandbox', 
                '--disable-dev-shm-usage', 
                '--disable-gpu',
                '--disable-software-rasterizer',
                '--disable-extensions',
                '--disable-background-timer-throttling',
                '--disable-backgrounding-occluded-windows',
                '--disable-renderer-backgrounding',
                '--max_old_space_size=256'
            ]
        },
        qrMaxRetries: 3,
        takeoverOnConflict: true,
        takeoverTimeoutMs: 5000
    });

    client.on('qr', (qr) => {
        botStatus = "Esperando QR";
        isConnected = false;
        lastQR = qr;
        qrcode.toDataURL(qr, (err, url) => {
            if (!err) {
                lastQRImage = url;
                io.emit('qr_update', url);
            } else {
                console.error('Error generando QR:', err);
                lastQRImage = null;
            }
            io.emit('connection_status', { connected: false, status: botStatus });
            io.emit('status_update', botStatus);
        });
    });

    client.on('ready', async () => {
        botStatus = "Conectado";
        isConnected = true;
        lastQR = null;
        lastQRImage = null;
        io.emit('qr_clear');
        io.emit('status_update', botStatus);
        io.emit('connection_status', { connected: true, status: botStatus });
        console.log('✅ Bot conectado -', nowRD().format('DD/MM/YYYY HH:mm:ss'));

        try {
            const rawContacts = await client.getContacts();
            contacts = rawContacts
                .filter(c => c.id.server === 'c.us' && c.number)
                .slice(0, 500)
                .map(c => ({
                    id: c.id._serialized,
                    name: c.name || c.pushname || c.number,
                    number: c.number
                }));
            io.emit('contacts_update', contacts);
            console.log('📇 Contactos cargados inicialmente:', contacts.length);
        } catch (e) {
            console.error('Error cargando contactos iniciales:', e);
        }
    });

    client.on('authenticated', () => console.log('🔐 Autenticado'));

    client.on('auth_failure', (msg) => {
        console.error('❌ Auth failure:', msg);
        botStatus = "Error de autenticación";
        io.emit('status_update', botStatus);
    });

    client.on('disconnected', (reason) => {
        botStatus = "Desconectado";
        isConnected = false;
        lastQR = null;
        lastQRImage = null;
        contacts = [];
        io.emit('status_update', botStatus);
        io.emit('connection_status', { connected: false, status: botStatus });
        io.emit('qr_clear');
        io.emit('contacts_update', []);
        console.log('❌ Bot desconectado:', reason);
    });

    client.on('message', async (msg) => {
        try {
            if (msg.from === 'status@broadcast') return;

            const db = getDB();
            const phone = msg.from.replace('@c.us', '');

            const excluded = db.excluded.some(ex => phone.includes(ex.phone));
            if (excluded) return;

            const text = msg.body.toLowerCase().trim();

            const trigger = db.training.find(t => {
                const key = t.key.toLowerCase().trim();
                return text.includes(key) || key.includes(text);
            });

            if (trigger) {
                const config = getConfig();
                if (config.responseDelay > 0) {
                    await delay(config.responseDelay * 1000);
                }

                if (trigger.mediaPaths && trigger.mediaPaths.length > 0) {
                    try {
                        const firstMedia = MessageMedia.fromFilePath(trigger.mediaPaths[0]);
                        messageQueue.enqueue(msg.from, firstMedia, { caption: trigger.response });
                        for (let i = 1; i < trigger.mediaPaths.length; i++) {
                            const media = MessageMedia.fromFilePath(trigger.mediaPaths[i]);
                            messageQueue.enqueue(msg.from, media);
                        }
                    } catch (e) {
                        messageQueue.enqueue(msg.from, trigger.response);
                    }
                } else {
                    messageQueue.enqueue(msg.from, trigger.response);
                }
                updateStats(1, 0);
            } else if (!msg.from.includes('@g.us')) {
                const exists = db.learning.some(l => l.text === msg.body && l.from === phone);
                if (!exists) {
                    addLearning(msg.body, phone, nowRD().format('DD/MM HH:mm'), msg.hasMedia, msg.type);
                }
            }

            updateStats(0, 1);
            io.emit('data_update', getDB());
        } catch (e) {
            console.error('Error en mensaje:', e);
        }
    });

    client.initialize().catch(e => console.error("Error al iniciar:", e));
}

async function createBackup() {
    try {
        const timestamp = nowRD().format('YYYY-MM-DD_HH-mm-ss');
        const backupData = {
            date: nowRD().format('DD/MM/YYYY HH:mm'),
            database: getDB(),
            config: getConfig()
        };
        const backupFile = path.join(BACKUP_PATH, 'backup_' + timestamp + '.json');
        fs.writeFileSync(backupFile, JSON.stringify(backupData, null, 2));
        console.log('✅ Backup creado:', backupFile, '-', nowRD().format('DD/MM/YYYY HH:mm:ss'));
        return backupFile;
    } catch (e) {
        console.error('❌ Error backup:', e);
        return null;
    }
}

async function sendBackupToWhatsApp(backupFile) {
    if (!isConnected) {
        console.log('❌ Bot no conectado, backup no enviado');
        return false;
    }
    const freshConfig = getConfig();
    if (!freshConfig.backupPhone || freshConfig.backupPhone.trim() === '') {
        console.log('❌ No hay número de backup configurado');
        return false;
    }
    try {
        const chatId = freshConfig.backupPhone.includes('@') ?
            freshConfig.backupPhone : freshConfig.backupPhone + '@c.us';
        const media = MessageMedia.fromFilePath(backupFile);
        messageQueue.enqueue(chatId, media, {
            caption: '🔐 *Backup GZMBOT*\n\n📅 Fecha: ' + nowRD().format('DD/MM/YYYY HH:mm') + '\n🕐 Hora RD\n\n✅ Copia de seguridad completada'
        });
        console.log('✅ Backup encolado para WhatsApp -', nowRD().format('HH:mm:ss'));
        return true;
    } catch (e) {
        console.error('❌ Error encolando backup:', e);
        return false;
    }
}

cron.schedule('0 0 * * *', async () => {
    console.log('🔄 [CRON] Backup automático iniciado -', nowRD().format('DD/MM/YYYY HH:mm:ss'));
    const bf = await createBackup();
    if (bf) {
        const sent = await sendBackupToWhatsApp(bf);
        console.log('🔄 [CRON] Backup encolado:', sent);
    }
}, {
    scheduled: true,
    timezone: TZ
});

console.log('📅 Backup automático programado para 12:00 AM hora RD');

cron.schedule('* * * * *', () => {
    if (!isConnected) return;

    const db = getDB();
    const currentRD = nowRD().format('YYYY-MM-DDTHH:mm');
    let changed = false;

    for (let i = db.reminders.length - 1; i >= 0; i--) {
        const rem = db.reminders[i];

        if (rem.date === currentRD) {
            console.log('🔔 Encolando recordatorio para', rem.name, '(' + rem.phone + ') -', currentRD);

            const chatId = rem.phone.includes('@') ? rem.phone : rem.phone + '@c.us';
            messageQueue.enqueue(chatId, rem.message);

            if (rem.freq === 'Diario') {
                rem.date = moment.tz(rem.date, TZ).add(1, 'days').format('YYYY-MM-DDTHH:mm');
                updateReminder(rem.id, rem.name, rem.phone, rem.message, rem.freq, rem.date);
            } else if (rem.freq === 'Semanal') {
                rem.date = moment.tz(rem.date, TZ).add(7, 'days').format('YYYY-MM-DDTHH:mm');
                updateReminder(rem.id, rem.name, rem.phone, rem.message, rem.freq, rem.date);
            } else if (rem.freq === 'Mensual') {
                rem.date = moment.tz(rem.date, TZ).add(1, 'months').format('YYYY-MM-DDTHH:mm');
                updateReminder(rem.id, rem.name, rem.phone, rem.message, rem.freq, rem.date);
            } else if (rem.freq === 'Anual') {
                rem.date = moment.tz(rem.date, TZ).add(1, 'years').format('YYYY-MM-DDTHH:mm');
                updateReminder(rem.id, rem.name, rem.phone, rem.message, rem.freq, rem.date);
            } else {
                deleteReminder(rem.id);
            }
            changed = true;
        }
    }

    if (changed) {
        io.emit('data_update', getDB());
    }
}, {
    scheduled: true,
    timezone: TZ
});

console.log('⏰ Recordatorios activos - verificando cada minuto en hora RD');

initBot();

const checkAuth = (req, res, next) => req.session.user ? next() : res.status(401).send("Unauthorized");

app.get('/', (req, res) => req.session.user ? res.sendFile(path.join(__dirname, 'views/index.html')) : res.redirect('/login'));
app.get('/login', (req, res) => res.sendFile(path.join(__dirname, 'views/login.html')));

app.post('/login', (req, res) => {
    const fc = getConfig();
    if (req.body.user === fc.adminUser && req.body.pass === fc.adminPassword) {
        req.session.user = req.body.user;
        res.json({ ok: true });
    } else res.json({ ok: false });
});

app.get('/api/data', checkAuth, (req, res) => {
    res.json({
        ...getDB(),
        botStatus,
        qr: lastQR,
        isConnected,
        backupPhone: getConfig().backupPhone || '',
        responseDelay: getConfig().responseDelay || 0,
        queueInterval: getConfig().queueInterval || 3000,
        queueSize: messageQueue ? messageQueue.size() : 0,
        serverTime: nowRD().format('DD/MM/YYYY HH:mm:ss'),
        timezone: TZ
    });
});

app.get('/api/contacts', checkAuth, (req, res) => {
    res.json(contacts);
});

app.get('/api/server-time', checkAuth, (req, res) => {
    res.json({
        serverTimeRD: nowRD().format('DD/MM/YYYY HH:mm:ss'),
        serverTimeUTC: moment.utc().format('DD/MM/YYYY HH:mm:ss'),
        timezone: TZ,
        nextBackup: '12:00 AM hora RD'
    });
});

app.post('/api/train', checkAuth, upload.array('media', 10), (req, res) => {
    const { id, key, response } = req.body;
    const mediaPaths = req.files && req.files.length > 0 ? req.files.map(f => f.path) : [];
    const mediaTypes = req.files && req.files.length > 0 ? req.files.map(f => f.mimetype) : [];

    if (id && id !== "" && id !== "undefined") {
        updateTraining(id, key, response, mediaPaths, mediaTypes);
        const old = dbSqlite.prepare('SELECT mediaPaths FROM training WHERE id = ?').get(id);
        if (old && old.mediaPaths) {
            const oldPaths = JSON.parse(old.mediaPaths);
            oldPaths.forEach(p => { if (fs.existsSync(p)) fs.unlinkSync(p); });
        }
    } else {
        addTraining(key, response, mediaPaths, mediaTypes);
    }

    if (key) {
        const learningItem = dbSqlite.prepare('SELECT id FROM learning WHERE text = ?').get(key.toLowerCase().trim());
        if (learningItem) {
            deleteLearning(learningItem.id);
        }
    }

    io.emit('data_update', getDB());
    res.json({ ok: true });
});

app.delete('/api/train/:id', checkAuth, (req, res) => {
    const id = req.params.id;
    const old = dbSqlite.prepare('SELECT mediaPaths FROM training WHERE id = ?').get(id);
    if (old && old.mediaPaths) {
        const oldPaths = JSON.parse(old.mediaPaths);
        oldPaths.forEach(p => { if (fs.existsSync(p)) fs.unlinkSync(p); });
    }
    deleteTraining(id);
    io.emit('data_update', getDB());
    res.json({ ok: true });
});

app.get('/api/train/template', checkAuth, (req, res) => {
    const template = '# PLANTILLA DE ENTRENAMIENTO GZMBOT\n# =====================================\n#\n# FORMATO:\n# PREGUNTA: texto que el usuario escribe\n# RESPUESTA: texto que el bot responde\n# ---\n\nPREGUNTA: hola\nRESPUESTA: ¡Hola! Bienvenido. ¿En qué puedo ayudarte?\n---\n\nPREGUNTA: horario\nRESPUESTA: Lunes a Viernes: 9:00 AM - 6:00 PM\\nSábados: 9:00 AM - 1:00 PM\\nDomingos: Cerrado\n---\n\nPREGUNTA: precio\nRESPUESTA: Contacta a nuestro equipo de ventas para precios.\n---\n\nPREGUNTA: ubicación\nRESPUESTA: Av. Principal #123, Ciudad.\n---\n';
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename=plantilla_entrenamiento.txt');
    res.send(template);
});

app.post('/api/train/import', checkAuth, upload.single('file'), (req, res) => {
    try {
        const fileContent = fs.readFileSync(req.file.path, 'utf-8');
        const lines = fileContent.split('\n');
        let cQ = '', cR = '', imported = 0;
        for (let line of lines) {
            line = line.trim();
            if (line.startsWith('#') || line === '') continue;
            if (line.startsWith('PREGUNTA:')) cQ = line.replace('PREGUNTA:', '').trim();
            else if (line.startsWith('RESPUESTA:')) {
                cR = line.replace('RESPUESTA:', '').trim().replace(/\\n/g, '\n');
            } else if (line === '---' && cQ && cR) {
                addTraining(cQ, cR, [], []);
                imported++; cQ = ''; cR = '';
            }
        }
        if (cQ && cR) { addTraining(cQ, cR, [], []); imported++; }
        io.emit('data_update', getDB());
        fs.unlinkSync(req.file.path);
        res.json({ ok: true, imported });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/train/export', checkAuth, (req, res) => {
    const db = getDB();
    let content = '# RESPUESTAS GZMBOT\n# Exportado: ' + nowRD().format('DD/MM/YYYY HH:mm') + '\n# Total: ' + db.training.length + '\n\n';
    db.training.forEach(t => {
        if (!t.mediaPaths || t.mediaPaths.length === 0) {
            content += 'PREGUNTA: ' + t.key + '\nRESPUESTA: ' + t.response.replace(/\n/g, '\\n') + '\n---\n\n';
        }
    });
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename=respuestas_exportadas.txt');
    res.send(content);
});

app.post('/api/reminders', checkAuth, (req, res) => {
    const { id, name, phone, message, freq, date } = req.body;
    const data = { name, phone: phone.replace(/\D/g, ''), message, freq, date };

    console.log('📝 Recordatorio guardado:', name, '- Fecha:', date, '- Hora actual RD:', nowRD().format('YYYY-MM-DDTHH:mm'));

    if (id && id !== "" && id !== "undefined") {
        updateReminder(id, name, phone, message, freq, date);
    } else {
        addReminder(name, phone, message, freq, date);
    }
    io.emit('data_update', getDB());
    res.json({ ok: true });
});

app.delete('/api/reminders/:id', checkAuth, (req, res) => {
    deleteReminder(req.params.id);
    io.emit('data_update', getDB());
    res.json({ ok: true });
});

app.post('/api/exclude', checkAuth, (req, res) => {
    const { name, phone } = req.body;
    addExcluded(name, phone);
    io.emit('data_update', getDB());
    res.json({ ok: true });
});

app.delete('/api/exclude/:id', checkAuth, (req, res) => {
    deleteExcluded(req.params.id);
    io.emit('data_update', getDB());
    res.json({ ok: true });
});

app.delete('/api/learning/:id', checkAuth, (req, res) => {
    deleteLearning(req.params.id);
    io.emit('data_update', getDB());
    res.json({ ok: true });
});

app.post('/api/config/credentials', checkAuth, (req, res) => {
    const fc = getConfig();
    if (req.body.user) fc.adminUser = req.body.user;
    if (req.body.pass) fc.adminPassword = req.body.pass;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    res.json({ ok: true });
});

app.post('/api/config/backup-phone', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.backupPhone = req.body.backupPhone || '';
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    console.log('📱 Número backup guardado:', fc.backupPhone);
    res.json({ ok: true });
});

app.post('/api/config/delay', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.responseDelay = parseFloat(req.body.delay) || 0;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    io.emit('config_update', { responseDelay: fc.responseDelay });
    res.json({ ok: true });
});

app.post('/api/config/queue-interval', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.queueInterval = parseInt(req.body.interval) || 3000;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    if (messageQueue) {
        messageQueue.setInterval(fc.queueInterval);
    }
    io.emit('config_update', { queueInterval: fc.queueInterval });
    res.json({ ok: true });
});

app.get('/api/backup/download', checkAuth, async (req, res) => {
    try {
        const bf = await createBackup();
        if (bf) {
            res.download(bf, path.basename(bf), (err) => {
                if (err && !res.headersSent) res.status(500).send('Error');
            });
        } else res.status(500).json({ ok: false, message: 'Error creando backup' });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/backup/send', checkAuth, async (req, res) => {
    if (!isConnected) return res.json({ ok: false, message: 'Bot no está conectado' });
    const fc = getConfig();
    if (!fc.backupPhone || fc.backupPhone.trim() === '') return res.json({ ok: false, message: 'No hay número configurado. Guárdalo primero.' });
    const bf = await createBackup();
    if (!bf) return res.json({ ok: false, message: 'Error creando backup' });
    const sent = await sendBackupToWhatsApp(bf);
    res.json({ ok: sent, message: sent ? 'Backup encolado correctamente' : 'Error encolando backup' });
});

app.post('/api/backup/restore', checkAuth, upload.single('backup'), (req, res) => {
    try {
        const bc = JSON.parse(fs.readFileSync(req.file.path, 'utf-8'));
        if (bc.database) {
            dbSqlite.prepare('DELETE FROM training').run();
            dbSqlite.prepare('DELETE FROM reminders').run();
            dbSqlite.prepare('DELETE FROM excluded').run();
            dbSqlite.prepare('DELETE FROM learning').run();
            bc.database.training.forEach(t => {
                addTraining(t.key, t.response, t.mediaPaths || [], t.mediaTypes || []);
            });
            bc.database.reminders.forEach(r => {
                addReminder(r.name, r.phone, r.message, r.freq, r.date);
            });
            bc.database.excluded.forEach(e => {
                addExcluded(e.name, e.phone);
            });
            bc.database.learning.forEach(l => {
                addLearning(l.text, l.from, l.date, l.hasMedia, l.type);
            });
            if (bc.database.stats) {
                dbSqlite.prepare('UPDATE stats SET replied = ?, total = ?').run(bc.database.stats.replied, bc.database.stats.total);
            }
            io.emit('data_update', getDB());
        }
        if (bc.config) {
            const cc = getConfig();
            const nc = { ...bc.config, adminUser: cc.adminUser, adminPassword: cc.adminPassword, sessionSecret: cc.sessionSecret };
            fs.writeFileSync(CONFIG_PATH, JSON.stringify(nc, null, 2));
        }
        fs.unlinkSync(req.file.path);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/logout-wa', checkAuth, async (req, res) => {
    try {
        if (client) {
            await client.logout();
            try { client.destroy(); } catch (e) {}
        }
        if (fs.existsSync(AUTH_PATH)) fs.rmSync(AUTH_PATH, { recursive: true, force: true });

        isConnected = false;
        botStatus = "Desconectado";
        lastQR = null;
        lastQRImage = null;
        contacts = [];

        dbSqlite.prepare('UPDATE stats SET replied = 0, total = 0').run();

        io.emit('data_update', getDB());
        io.emit('connection_status', { connected: false, status: botStatus });
        io.emit('qr_clear');
        io.emit('contacts_update', []);

        res.json({ ok: true });

        setTimeout(() => {
            initBot();
        }, 1500);
    } catch (e) { 
        console.error('Error en logout:', e);
        res.status(500).json({ ok: false, error: e.message }); 
    }
});

server.listen(config.port, '127.0.0.1', () => {
    console.log('🚀 GZMBOT ONLINE en puerto', config.port, '(solo local)');
    console.log('🕐 Hora actual RD:', nowRD().format('DD/MM/YYYY HH:mm:ss'));
    console.log('📅 Próximo backup: 12:00 AM hora RD');
});
APPEOF

# ----------------------------------------------------------------------
# 8. FRONTEND (views/index.html) - NUEVO DISEÑO PREMIUM CON FUNCIONALIDAD COMPLETA
# ----------------------------------------------------------------------
cat <<'HTMLEOF' > views/index.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GZMBOT | Premium Admin Panel</title>
    <!-- Tailwind CSS -->
    <script src="https://cdn.tailwindcss.com"></script>
    <!-- Google Fonts: Inter & Outfit para look futurista -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&family=Outfit:wght@400;600;800;900&display=swap" rel="stylesheet">
    <!-- Lucide Icons -->
    <script src="https://unpkg.com/lucide@latest"></script>
    <!-- Socket.IO -->
    <script src="/socket.io/socket.io.js"></script>
    <style>
        /* Estilos personalizados del diseño original */
        body {
            background-color: #06060a;
            color: #f3f4f6;
            overflow-x: hidden;
            font-family: 'Inter', sans-serif;
        }
        .glass-panel {
            background: rgba(13, 13, 23, 0.75);
            backdrop-filter: blur(20px) saturate(180%);
            -webkit-backdrop-filter: blur(20px) saturate(180%);
            border: 1px solid rgba(255, 255, 255, 0.04);
        }
        .glass-card {
            background: rgba(20, 20, 33, 0.5);
            border: 1px solid rgba(255, 255, 255, 0.03);
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }
        .glass-card:hover {
            border-color: rgba(59, 130, 246, 0.25);
            box-shadow: 0 10px 30px -10px rgba(59, 130, 246, 0.15);
            transform: translateY(-2px);
        }
        .gradient-text {
            background: linear-gradient(135deg, #ffffff 30%, #a5b4fc 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .gradient-accent {
            background: linear-gradient(135deg, #2563eb 0%, #3b82f6 50%, #60a5fa 100%);
        }
        ::-webkit-scrollbar {
            width: 6px;
            height: 6px;
        }
        ::-webkit-scrollbar-track {
            background: rgba(0, 0, 0, 0.1);
        }
        ::-webkit-scrollbar-thumb {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 999px;
        }
        ::-webkit-scrollbar-thumb:hover {
            background: rgba(59, 130, 246, 0.4);
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-10px); }
        }
        .animate-float {
            animation: float 6s ease-in-out infinite;
        }
        .page-content {
            display: none;
        }
        .page-content.active {
            display: block;
            animation: fadeIn 0.4s ease-out forwards;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(8px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .sidebar-item.active {
            background: linear-gradient(90deg, rgba(37, 99, 235, 0.15) 0%, rgba(37, 99, 235, 0.02) 100%);
            border-left: 3px solid #3b82f6;
            color: #60a5fa;
            font-weight: 600;
        }
        input[type="range"] {
            -webkit-appearance: none;
            appearance: none;
            height: 6px;
            border-radius: 999px;
            background: #1e1e2f;
            outline: none;
        }
        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none;
            appearance: none;
            width: 18px;
            height: 18px;
            border-radius: 50%;
            background: #3b82f6;
            cursor: pointer;
            box-shadow: 0 0 10px rgba(59, 130, 246, 0.5);
            transition: all 0.1s ease;
        }
        .media-preview { max-width: 100px; max-height: 100px; border-radius: 16px; margin: 4px; object-fit: cover; border: 1px solid #2a2a2e; }
        .media-type-selector { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; }
        .media-type-btn { padding: 8px 18px; background: #0f0f13; border: 1px solid #27272a; border-radius: 14px; cursor: pointer; transition: all 0.3s; color: #fff; font-size: 14px; font-weight: 500; }
        .media-type-btn.active { background: #2563eb; border-color: #2563eb; box-shadow: 0 4px 12px #2563eb50; }
        .media-preview-container { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 12px; }
        .media-item { position: relative; }
        .media-remove { position: absolute; top: -8px; right: -8px; background: #ef4444; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 14px; font-weight: bold; box-shadow: 0 4px 8px rgba(0,0,0,0.3); }
        .toast {
            position: fixed;
            bottom: 24px;
            right: 24px;
            background: #23232b;
            border-left: 5px solid #2563eb;
            padding: 14px 24px;
            border-radius: 40px;
            box-shadow: 0 20px 35px -8px black;
            transform: translateY(120px);
            opacity: 0;
            transition: all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
            z-index: 2000;
            color: #fff;
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 12px;
            backdrop-filter: blur(8px);
        }
        .toast.show {
            transform: translateY(0);
            opacity: 1;
        }
        .modal {
            display: none;
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.8);
            backdrop-filter: blur(8px);
            align-items: center;
            justify-content: center;
            z-index: 1000;
        }
        .modal.active {
            display: flex;
        }
        .modal-content {
            background: #1c1c22;
            border-radius: 40px;
            max-width: 520px;
            width: 90%;
            max-height: 80vh;
            overflow-y: auto;
            padding: 24px;
            border: 1px solid #2f2f37;
            box-shadow: 0 30px 50px -20px black;
        }
        .contact-item {
            padding: 14px;
            border-radius: 18px;
            cursor: pointer;
            transition: background 0.2s;
            display: flex;
            align-items: center;
            gap: 14px;
            border-bottom: 1px solid #2a2a30;
        }
        .contact-item:hover {
            background: #2a2a32;
        }
        .clock-modern {
            display: flex;
            flex-direction: column;
            align-items: flex-end;
            line-height: 1.2;
        }
        .clock-time {
            font-size: clamp(2rem, 5vw, 3.2rem);
            font-weight: 800;
            background: linear-gradient(to right, #2563eb, #60a5fa);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            letter-spacing: -0.02em;
        }
        .clock-date {
            font-size: clamp(0.85rem, 2vw, 1.1rem);
            color: #a1a1aa;
            font-weight: 400;
            text-transform: capitalize;
        }
        .stat-value {
            font-size: 2.5rem;
            font-weight: 800;
            line-height: 1;
            background: linear-gradient(to right, #e5e7eb, #a5b4fc);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .badge {
            padding: 4px 12px;
            border-radius: 40px;
            font-size: 11px;
            font-weight: 600;
            letter-spacing: 0.4px;
            text-transform: uppercase;
            background: rgba(255,255,255,0.03);
            border: 1px solid rgba(255,255,255,0.05);
        }
    </style>
</head>
<body class="font-sans antialiased text-slate-200 min-h-screen flex flex-col justify-between">

    <!-- LUCES DE FONDO DECORATIVAS -->
    <div class="fixed top-[-20%] left-[-10%] w-[600px] h-[600px] rounded-full bg-blue-900/10 blur-[140px] pointer-events-none z-[-1]"></div>
    <div class="fixed bottom-[-10%] right-[-10%] w-[500px] h-[500px] rounded-full bg-indigo-900/10 blur-[130px] pointer-events-none z-[-1]"></div>

    <!-- PANEL PRINCIPAL (SIDEBAR + CONTENIDO) -->
    <div id="panel-container" class="w-full flex-1 flex flex-col lg:flex-row min-h-screen">
        
        <!-- SIDEBAR -->
        <aside id="sidebar" class="fixed inset-y-0 left-0 z-50 w-72 glass-panel border-r border-white/5 -translate-x-full lg:translate-x-0 lg:static transition-transform duration-300 flex flex-col p-6 overflow-y-auto">
            <div class="flex items-center justify-between mb-10 px-2">
                <div class="flex items-center gap-3">
                    <div class="w-9 h-9 rounded-xl bg-blue-600/10 border border-blue-500/20 text-blue-500 flex items-center justify-center">
                        <i data-lucide="bot" class="w-5 h-5"></i>
                    </div>
                    <div>
                        <span class="text-xl font-black tracking-tight font-outfit text-white">GZMBOT</span>
                        <p class="text-[9px] text-zinc-500 uppercase tracking-widest font-bold">Admin Space</p>
                    </div>
                </div>
                <button onclick="toggleSidebar()" class="lg:hidden p-2 text-zinc-400 hover:text-white rounded-lg hover:bg-white/5">
                    <i data-lucide="x" class="w-5 h-5"></i>
                </button>
            </div>

            <nav class="space-y-1.5 flex-1">
                <div onclick="nav('dash'); closeMobileSidebar()" id="n-dash" class="sidebar-item active flex items-center gap-3 px-4 py-3.5 rounded-xl text-zinc-300 hover:bg-white/5 hover:text-white cursor-pointer transition-all text-sm">
                    <i data-lucide="layout-dashboard" class="w-5 h-5"></i>
                    <span>Dashboard</span>
                </div>
                <div onclick="nav('conn'); closeMobileSidebar()" id="n-conn" class="sidebar-item flex items-center gap-3 px-4 py-3.5 rounded-xl text-zinc-300 hover:bg-white/5 hover:text-white cursor-pointer transition-all text-sm">
                    <i data-lucide="qr-code" class="w-5 h-5"></i>
                    <span>Conexión</span>
                </div>
                <div onclick="nav('train'); closeMobileSidebar()" id="n-train" class="sidebar-item flex items-center gap-3 px-4 py-3.5 rounded-xl text-zinc-300 hover:bg-white/5 hover:text-white cursor-pointer transition-all text-sm">
                    <i data-lucide="message-square" class="w-5 h-5"></i>
                    <span>Respuestas</span>
                </div>
                <div onclick="nav('learn'); closeMobileSidebar()" id="n-learn" class="sidebar-item flex items-center gap-3 px-4 py-3.5 rounded-xl text-zinc-300 hover:bg-white/5 hover:text-white cursor-pointer transition-all text-sm">
                    <i data-lucide="brain" class="w-5 h-5"></i>
                    <span>Aprender (IA)</span>
                </div>
                <div onclick="nav('rem'); closeMobileSidebar()" id="n-rem" class="sidebar-item flex items-center gap-3 px-4 py-3.5 rounded-xl text-zinc-300 hover:bg-white/5 hover:text-white cursor-pointer transition-all text-sm">
                    <i data-lucide="bell" class="w-5 h-5"></i>
                    <span>Recordatorios</span>
                </div>
                <div onclick="nav('excl'); closeMobileSidebar()" id="n-excl" class="sidebar-item flex items-center gap-3 px-4 py-3.5 rounded-xl text-zinc-300 hover:bg-white/5 hover:text-white cursor-pointer transition-all text-sm">
                    <i data-lucide="shield-off" class="w-5 h-5"></i>
                    <span>Excluidos</span>
                </div>
                <div onclick="nav('config'); closeMobileSidebar()" id="n-config" class="sidebar-item flex items-center gap-3 px-4 py-3.5 rounded-xl text-zinc-300 hover:bg-white/5 hover:text-white cursor-pointer transition-all text-sm">
                    <i data-lucide="settings" class="w-5 h-5"></i>
                    <span>Ajustes</span>
                </div>
            </nav>

            <div class="mt-auto pt-6 border-t border-white/5">
                <div class="flex items-center gap-3 mb-4 px-2">
                    <div class="w-8 h-8 rounded-full gradient-accent flex items-center justify-center font-bold text-xs text-white">
                        AD
                    </div>
                    <div class="truncate">
                        <p class="text-xs font-bold text-white leading-tight" id="display-user">Administrador</p>
                        <span class="inline-flex items-center gap-1 text-[10px] text-emerald-400 font-semibold">
                            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span> Online
                        </span>
                    </div>
                </div>
                <button onclick="handleLogout()" class="w-full flex items-center gap-3 px-4 py-3.5 rounded-xl text-red-400 hover:bg-red-500/10 transition-all text-sm font-medium">
                    <i data-lucide="log-out" class="w-5 h-5"></i>
                    <span>Cerrar sesión</span>
                </button>
            </div>
        </aside>

        <!-- CONTENIDO PRINCIPAL -->
        <main class="flex-1 flex flex-col min-h-screen overflow-x-hidden">
            <header class="glass-panel border-b border-white/5 px-6 py-4 flex items-center justify-between lg:justify-end gap-4 z-40">
                <button onclick="toggleSidebar()" class="lg:hidden p-2 text-zinc-300 hover:text-white hover:bg-white/5 rounded-xl transition-colors">
                    <i data-lucide="menu" class="w-6 h-6"></i>
                </button>
                
                <div class="flex items-center gap-3 text-zinc-300 text-xs">
                    <div class="hidden sm:flex items-center gap-2 px-3 py-1.5 bg-zinc-900/80 rounded-lg border border-white/5 text-[11px]">
                        <span class="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
                        <span class="text-zinc-400">Servidor:</span>
                        <span class="font-mono text-zinc-200">Activo (RD)</span>
                    </div>
                    <div class="flex items-center gap-2 px-3 py-1.5 bg-zinc-900/80 rounded-lg border border-white/5 text-[11px]">
                        <i data-lucide="cpu" class="w-3.5 h-3.5 text-blue-400"></i>
                        <span class="text-zinc-400">CPU:</span>
                        <span class="font-mono text-zinc-200">2.4%</span>
                    </div>
                </div>
            </header>

            <div class="p-6 sm:p-8 flex-1 max-w-7xl w-full mx-auto space-y-8">
                
                <!-- PÁGINA DASHBOARD -->
                <div id="p-dash" class="page-content active">
                    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                        <div>
                            <h2 class="text-3xl font-black font-outfit gradient-text">Dashboard</h2>
                            <p class="text-xs text-zinc-400 mt-1">Visión general del rendimiento y actividad del Bot</p>
                        </div>
                        <div class="flex items-center gap-2 text-xs bg-blue-600/10 border border-blue-500/20 text-blue-400 px-3 py-1.5 rounded-lg">
                            <i data-lucide="refresh-cw" class="w-3.5 h-3.5"></i>
                            Activo hace: <span id="bot-uptime">--</span>
                        </div>
                    </div>

                    <!-- Tarjetas de Métricas -->
                    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
                        <div class="glass-card p-5 rounded-2xl flex items-center gap-4">
                            <div class="p-3.5 bg-blue-500/10 text-blue-400 rounded-xl">
                                <i data-lucide="message-square" class="w-6 h-6"></i>
                            </div>
                            <div>
                                <p class="text-xs text-zinc-400 font-medium">Respuestas del Día</p>
                                <h3 id="stat-replied" class="text-2xl font-black font-outfit text-white mt-1">0</h3>
                                <span class="text-[10px] text-emerald-400 font-medium flex items-center gap-1 mt-1">
                                    <i data-lucide="trending-up" class="w-3 h-3"></i> +12% hoy
                                </span>
                            </div>
                        </div>
                        <div class="glass-card p-5 rounded-2xl flex items-center gap-4">
                            <div class="p-3.5 bg-purple-500/10 text-purple-400 rounded-xl">
                                <i data-lucide="users" class="w-6 h-6"></i>
                            </div>
                            <div>
                                <p class="text-xs text-zinc-400 font-medium">Total Mensajes</p>
                                <h3 id="stat-total" class="text-2xl font-black font-outfit text-white mt-1">0</h3>
                            </div>
                        </div>
                        <div class="glass-card p-5 rounded-2xl flex items-center gap-4">
                            <div class="p-3.5 bg-orange-500/10 text-orange-400 rounded-xl">
                                <i data-lucide="bell" class="w-6 h-6"></i>
                            </div>
                            <div>
                                <p class="text-xs text-zinc-400 font-medium">Recordatorios Pendientes</p>
                                <h3 id="reminders-count" class="text-2xl font-black font-outfit text-white mt-1">0</h3>
                            </div>
                        </div>
                        <div class="glass-card p-5 rounded-2xl flex items-center gap-4">
                            <div class="p-3.5 bg-emerald-500/10 text-emerald-400 rounded-xl">
                                <i data-lucide="check-circle" class="w-6 h-6"></i>
                            </div>
                            <div>
                                <p class="text-xs text-zinc-400 font-medium">Tasa de Respuesta IA</p>
                                <h3 class="text-2xl font-black font-outfit text-white mt-1">98.2%</h3>
                                <span class="text-[10px] text-emerald-400 font-medium flex items-center gap-1 mt-1">
                                    <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-ping"></span> Excelente
                                </span>
                            </div>
                        </div>
                    </div>

                    <!-- Gráficos y Última Actividad -->
                    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                        <div class="glass-card p-6 rounded-3xl lg:col-span-2">
                            <div class="flex items-center justify-between mb-6">
                                <h3 class="text-lg font-bold font-outfit text-white">Flujo de Mensajes</h3>
                                <span class="text-xs text-zinc-400">Últimas 6 horas</span>
                            </div>
                            <div class="relative h-48 w-full flex items-end justify-between pt-4 px-2">
                                <div class="absolute inset-0 flex flex-col justify-between pointer-events-none text-[10px] text-zinc-600">
                                    <div class="border-b border-white/[0.02] w-full pb-1">300 msg</div>
                                    <div class="border-b border-white/[0.02] w-full pb-1">200 msg</div>
                                    <div class="border-b border-white/[0.02] w-full pb-1">100 msg</div>
                                    <div class="w-full">0 msg</div>
                                </div>
                                <div class="w-10 bg-zinc-800/50 hover:bg-blue-600/30 transition-all rounded-t-lg flex flex-col justify-end items-center group relative z-10" style="height: 40%;">
                                    <div class="absolute -top-6 bg-blue-600 text-[10px] px-1.5 py-0.5 rounded text-white opacity-0 group-hover:opacity-100 transition-opacity">120</div>
                                    <span class="text-[10px] text-zinc-500 mb-[-24px] absolute bottom-[-20px]">08:00</span>
                                </div>
                                <div class="w-10 bg-zinc-800/50 hover:bg-blue-600/30 transition-all rounded-t-lg flex flex-col justify-end items-center group relative z-10" style="height: 65%;">
                                    <div class="absolute -top-6 bg-blue-600 text-[10px] px-1.5 py-0.5 rounded text-white opacity-0 group-hover:opacity-100 transition-opacity">195</div>
                                    <span class="text-[10px] text-zinc-500 mb-[-24px] absolute bottom-[-20px]">09:00</span>
                                </div>
                                <div class="w-10 bg-zinc-800/50 hover:bg-blue-600/30 transition-all rounded-t-lg flex flex-col justify-end items-center group relative z-10" style="height: 55%;">
                                    <div class="absolute -top-6 bg-blue-600 text-[10px] px-1.5 py-0.5 rounded text-white opacity-0 group-hover:opacity-100 transition-opacity">165</div>
                                    <span class="text-[10px] text-zinc-500 mb-[-24px] absolute bottom-[-20px]">10:00</span>
                                </div>
                                <div class="w-10 bg-zinc-800/50 hover:bg-blue-600/30 transition-all rounded-t-lg flex flex-col justify-end items-center group relative z-10" style="height: 85%;">
                                    <div class="absolute -top-6 bg-blue-600 text-[10px] px-1.5 py-0.5 rounded text-white opacity-0 group-hover:opacity-100 transition-opacity">255</div>
                                    <span class="text-[10px] text-zinc-500 mb-[-24px] absolute bottom-[-20px]">11:00</span>
                                </div>
                                <div class="w-10 bg-blue-600/20 hover:bg-blue-600/40 transition-all rounded-t-lg border-t-2 border-blue-500 flex flex-col justify-end items-center group relative z-10" style="height: 95%;">
                                    <div class="absolute -top-6 bg-blue-600 text-[10px] px-1.5 py-0.5 rounded text-white opacity-0 group-hover:opacity-100 transition-opacity">294</div>
                                    <span class="text-[10px] text-zinc-500 mb-[-24px] absolute bottom-[-20px]">12:00</span>
                                </div>
                            </div>
                        </div>

                        <div class="glass-card p-6 rounded-3xl flex flex-col justify-between">
                            <div>
                                <h3 class="text-lg font-bold font-outfit text-white mb-4">Conectado a WhatsApp</h3>
                                <div id="wa-status-box" class="flex items-center gap-3 p-4 bg-emerald-500/5 border border-emerald-500/10 rounded-2xl mb-4">
                                    <div class="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse"></div>
                                    <div class="text-xs">
                                        <p id="wa-number" class="font-bold text-white">No conectado</p>
                                        <p id="wa-device" class="text-zinc-500 mt-0.5">Dispositivo: ---</p>
                                    </div>
                                </div>
                            </div>
                            <button onclick="nav('conn')" class="w-full py-3.5 bg-zinc-900 border border-white/5 rounded-xl text-xs font-bold text-zinc-300 hover:bg-zinc-800 hover:text-white transition-all flex items-center justify-center gap-2">
                                <i data-lucide="qr-code" class="w-4 h-4 text-blue-400"></i>
                                Gestionar Conexión
                            </button>
                        </div>
                    </div>
                </div>

                <!-- PÁGINA CONEXIÓN -->
                <div id="p-conn" class="page-content">
                    <div>
                        <h2 class="text-3xl font-black font-outfit gradient-text mb-2">Conexión de WhatsApp</h2>
                        <p class="text-xs text-zinc-400 mb-6">Escanea el código QR para vincular el bot con tu cuenta oficial de WhatsApp.</p>
                    </div>
                    <div class="max-w-4xl mx-auto glass-card rounded-[2rem] p-8 flex flex-col md:flex-row items-center gap-10">
                        <div class="w-full md:w-1/2 flex flex-col items-center">
                            <div class="relative p-6 bg-white rounded-3xl shadow-[0_0_50px_rgba(59,130,246,0.15)] flex items-center justify-center border-4 border-zinc-900 group">
                                <div class="absolute inset-0 border-2 border-dashed border-blue-500 rounded-3xl m-2 animate-pulse"></div>
                                <div id="qr-img" class="w-56 h-56 relative bg-zinc-100 flex items-center justify-center rounded-2xl overflow-hidden p-2">
                                    <span class="text-sm text-gray-500">Esperando QR...</span>
                                </div>
                            </div>
                            <p class="text-xs text-blue-400 font-bold tracking-wider mt-5 flex items-center gap-2">
                                <span class="w-2.5 h-2.5 rounded-full bg-blue-500 animate-ping"></span>
                                ESPERANDO ESCANEO...
                            </p>
                        </div>
                        <div class="w-full md:w-1/2 space-y-6">
                            <h3 class="text-xl font-bold text-white font-outfit">Instrucciones de Vinculación</h3>
                            <ul class="space-y-4 text-xs text-zinc-400">
                                <li class="flex gap-3"><span class="w-6 h-6 rounded-lg bg-zinc-800 text-blue-400 flex items-center justify-center font-bold font-mono">1</span>Abre WhatsApp en tu teléfono celular.</li>
                                <li class="flex gap-3"><span class="w-6 h-6 rounded-lg bg-zinc-800 text-blue-400 flex items-center justify-center font-bold font-mono">2</span>Toca <strong>Menú</strong> o <strong>Configuración</strong> y selecciona <strong>Dispositivos Vinculados</strong>.</li>
                                <li class="flex gap-3"><span class="w-6 h-6 rounded-lg bg-zinc-800 text-blue-400 flex items-center justify-center font-bold font-mono">3</span>Presiona en <strong>Vincular un dispositivo</strong> y apunta tu cámara hacia esta pantalla.</li>
                            </ul>
                            <div class="p-4 bg-blue-500/5 rounded-2xl border border-blue-500/10 text-xs text-zinc-500 flex gap-3 leading-relaxed">
                                <i data-lucide="info" class="w-5 h-5 text-blue-400 shrink-0"></i>
                                <span>No cierres esta pestaña durante el proceso de escaneo.</span>
                            </div>
                            <button id="btn-logout-wa" onclick="logoutWA()" class="hidden w-full py-4 bg-red-500/10 text-red-500 rounded-2xl font-bold hover:bg-red-500 hover:text-white transition">
                                <i data-lucide="unlink" class="inline w-4 h-4 mr-2"></i>DESVINCULAR
                            </button>
                        </div>
                    </div>
                </div>

                <!-- PÁGINA RESPUESTAS -->
                <div id="p-train" class="page-content">
                    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                        <div>
                            <h2 class="text-3xl font-black font-outfit gradient-text">Gestión de Respuestas</h2>
                            <p class="text-xs text-zinc-400 mt-1">Configura disparadores de palabras clave y sus respuestas automáticas.</p>
                        </div>
                        <div class="flex gap-2">
                            <button onclick="downloadTemplate()" class="py-3 px-5 bg-purple-600 rounded-xl text-white font-bold text-xs flex items-center gap-2">Plantilla</button>
                            <button onclick="document.getElementById('import-file').click()" class="py-3 px-5 bg-green-600 rounded-xl text-white font-bold text-xs flex items-center gap-2">Importar</button>
                            <button onclick="exportTraining()" class="py-3 px-5 bg-orange-600 rounded-xl text-white font-bold text-xs flex items-center gap-2">Exportar</button>
                        </div>
                    </div>
                    <div class="grid lg:grid-cols-3 gap-5">
                        <div class="lg:col-span-1 glass-card p-6 rounded-3xl">
                            <h3 class="font-bold text-xl mb-5 flex items-center gap-2"><i data-lucide="plus-circle" class="text-blue-500"></i> Nueva Regla</h3>
                            <form id="train-form" enctype="multipart/form-data" onsubmit="saveTrain(event)">
                                <input type="hidden" id="t-id">
                                <input type="text" id="t-key" placeholder="Palabra clave (ej: hola, precio)" class="w-full mb-4 bg-black/40 border border-white/5 rounded-xl p-3 text-white" required>
                                <textarea id="t-res" placeholder="Respuesta automática..." class="w-full h-28 mb-5 bg-black/40 border border-white/5 rounded-xl p-3 text-white" required></textarea>
                                <div class="mb-5">
                                    <label class="block text-sm text-zinc-400 mb-2">Tipo de medio:</label>
                                    <div class="media-type-selector">
                                        <button type="button" onclick="setMediaType('text')" id="mt-text" class="media-type-btn active">Texto</button>
                                        <button type="button" onclick="setMediaType('image')" id="mt-image" class="media-type-btn">Imagen</button>
                                        <button type="button" onclick="setMediaType('video')" id="mt-video" class="media-type-btn">Video</button>
                                    </div>
                                </div>
                                <div id="media-upload" class="hidden mb-5">
                                    <input type="file" id="t-media" accept="image/*,video/*" multiple class="bg-black/40 border border-white/5 rounded-xl p-2 w-full text-white">
                                    <div id="media-preview" class="media-preview-container"></div>
                                </div>
                                <button type="submit" class="w-full py-4 bg-blue-600 rounded-xl font-bold hover:bg-blue-700 transition">Guardar</button>
                            </form>
                        </div>
                        <div id="l-train" class="lg:col-span-2 space-y-3"></div>
                    </div>
                    <input type="file" id="import-file" accept=".txt" class="hidden" onchange="importTraining(this)">
                </div>

                <!-- PÁGINA APRENDER -->
                <div id="p-learn" class="page-content">
                    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                        <div>
                            <h2 class="text-3xl font-black font-outfit gradient-text">Bandeja de Aprendizaje</h2>
                            <p class="text-xs text-zinc-400 mt-1">Mensajes que el bot no supo responder. Úsalos para crear nuevas reglas.</p>
                        </div>
                    </div>
                    <div id="l-learn" class="space-y-3"></div>
                </div>

                <!-- PÁGINA RECORDATORIOS -->
                <div id="p-rem" class="page-content">
                    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                        <div>
                            <h2 class="text-3xl font-black font-outfit gradient-text">Recordatorios</h2>
                            <p class="text-xs text-zinc-400 mt-1">Crea tareas programadas que el bot enviará a clientes de forma automática.</p>
                        </div>
                        <div class="clock-modern">
                            <div class="clock-time" id="rem-clock-time">--:--:--</div>
                            <div class="clock-date" id="rem-clock-date">cargando...</div>
                        </div>
                    </div>
                    <div class="glass-card p-6 rounded-3xl mb-8">
                        <h3 class="text-xl font-bold font-outfit mb-4">Programar nuevo recordatorio</h3>
                        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                            <input type="hidden" id="r-id">
                            <input type="text" id="r-name" placeholder="Nombre del recordatorio" class="bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                            <div class="relative flex gap-2">
                                <input type="text" id="r-phone" placeholder="Número (ej: 18091234567)" class="flex-1 bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                                <button type="button" onclick="openContactModal('r-phone', 'r-name')" class="p-3 bg-zinc-700 rounded-xl hover:bg-zinc-600">
                                    <i data-lucide="users" class="w-5 h-5"></i>
                                </button>
                            </div>
                            <textarea id="r-msg" placeholder="Mensaje del recordatorio" rows="2" class="bg-black/40 border border-white/5 rounded-xl p-3 text-white"></textarea>
                            <select id="r-freq" class="bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                                <option>Una vez</option><option>Diario</option><option>Semanal</option><option>Mensual</option><option>Anual</option>
                            </select>
                            <input type="datetime-local" id="r-date" class="bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                        </div>
                        <button onclick="saveRem()" class="mt-6 px-8 py-3 bg-emerald-600 rounded-xl font-bold hover:bg-emerald-700 transition">Guardar Recordatorio</button>
                    </div>
                    <div id="l-rem" class="grid grid-cols-1 md:grid-cols-2 gap-5"></div>
                </div>

                <!-- PÁGINA EXCLUIDOS -->
                <div id="p-excl" class="page-content">
                    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                        <div>
                            <h2 class="text-3xl font-black font-outfit gradient-text">Lista de Exclusión</h2>
                            <p class="text-xs text-zinc-400 mt-1">Contactos o números excluidos de las respuestas automáticas del bot.</p>
                        </div>
                    </div>
                    <div class="glass-card p-6 rounded-3xl">
                        <div class="flex flex-col sm:flex-row gap-3 mb-6">
                            <input type="text" id="e-name" placeholder="Nombre" class="flex-1 bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                            <div class="flex gap-2 flex-1">
                                <input type="text" id="e-phone" placeholder="Número" class="flex-1 bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                                <button onclick="openContactModal('e-phone', 'e-name')" class="p-3 bg-zinc-700 rounded-xl"><i data-lucide="users" class="w-5 h-5"></i></button>
                            </div>
                            <button onclick="saveExcl()" class="bg-white text-black px-6 py-3 font-bold rounded-xl hover:bg-zinc-200">Añadir Excluido</button>
                        </div>
                        <div id="l-excl" class="space-y-2"></div>
                    </div>
                </div>

                <!-- PÁGINA AJUSTES -->
                <div id="p-config" class="page-content">
                    <div>
                        <h2 class="text-3xl font-black font-outfit gradient-text mb-2">Configuración General</h2>
                        <p class="text-xs text-zinc-400 mb-6">Administra las credenciales, copias de seguridad e intervalos de envío.</p>
                    </div>
                    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                        <div class="glass-card p-6 rounded-3xl">
                            <h3 class="text-xl font-bold font-outfit mb-4">Credenciales de Acceso</h3>
                            <input type="text" id="conf-user" placeholder="Nuevo Usuario" class="w-full mb-4 bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                            <input type="password" id="conf-pass" placeholder="Nueva Contraseña" class="w-full mb-6 bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                            <button onclick="saveCredentials()" class="w-full py-3 bg-blue-600 rounded-xl font-bold hover:bg-blue-700">Actualizar Credenciales</button>
                        </div>
                        <div class="glass-card p-6 rounded-3xl">
                            <h3 class="text-xl font-bold font-outfit mb-4">Copias de Seguridad</h3>
                            <div class="mb-4">
                                <p class="text-xs text-zinc-400 mb-2">Número para backups automáticos:</p>
                                <div class="flex gap-2">
                                    <input type="text" id="conf-backup-phone" placeholder="Ej: 18091234567" class="flex-1 bg-black/40 border border-white/5 rounded-xl p-3 text-white">
                                    <button onclick="openContactModal('conf-backup-phone', null)" class="p-3 bg-zinc-700 rounded-xl"><i data-lucide="users" class="w-5 h-5"></i></button>
                                    <button onclick="saveBackupPhone()" class="px-4 bg-emerald-600 rounded-xl font-bold">Guardar</button>
                                </div>
                            </div>
                            <div class="space-y-3">
                                <button onclick="downloadBackup()" class="w-full py-3 bg-green-600 rounded-xl font-bold flex items-center justify-center gap-2"><i data-lucide="download"></i> Descargar Backup</button>
                                <button onclick="sendBackupManually()" class="w-full py-3 bg-blue-600 rounded-xl font-bold flex items-center justify-center gap-2"><i data-lucide="send"></i> Enviar a WhatsApp</button>
                                <button onclick="document.getElementById('restore-file').click()" class="w-full py-3 bg-orange-600 rounded-xl font-bold flex items-center justify-center gap-2"><i data-lucide="upload"></i> Restaurar Backup</button>
                                <input type="file" id="restore-file" accept=".json" class="hidden" onchange="restoreBackup(this)">
                            </div>
                            <p class="text-[10px] text-zinc-500 mt-4">💡 Backup diario automático a las 12:00 AM hora RD.</p>
                        </div>
                        <div class="lg:col-span-2 glass-card p-6 rounded-3xl">
                            <h3 class="text-xl font-bold font-outfit mb-6">Configuración de Envío</h3>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
                                <div>
                                    <label class="text-sm text-zinc-300 flex items-center gap-2 mb-2"><i data-lucide="clock" class="w-4 h-4"></i> Tiempo de espera (segundos)</label>
                                    <div class="flex items-center gap-4">
                                        <input type="range" id="response-delay" min="0" max="10" step="0.5" value="0" class="flex-1">
                                        <span id="delay-value" class="text-lg font-mono text-blue-400">0.0 s</span>
                                    </div>
                                </div>
                                <div>
                                    <label class="text-sm text-zinc-300 flex items-center gap-2 mb-2"><i data-lucide="layers" class="w-4 h-4"></i> Intervalo entre mensajes (ms)</label>
                                    <div class="flex items-center gap-4">
                                        <input type="range" id="queue-interval" min="500" max="10000" step="100" value="3000" class="flex-1">
                                        <span id="interval-value" class="text-lg font-mono text-orange-400">3000 ms</span>
                                    </div>
                                    <div class="mt-2 text-xs text-zinc-500">Mensajes en cola: <span id="queue-size" class="font-bold text-orange-400">0</span></div>
                                </div>
                            </div>
                            <div class="flex justify-end mt-6">
                                <button onclick="saveConfiguracionEnvio()" class="px-8 py-3 bg-orange-600 rounded-xl font-bold hover:bg-orange-700 flex items-center gap-2"><i data-lucide="save"></i> Guardar Configuración</button>
                            </div>
                        </div>
                    </div>
                </div>

            </div>
            <footer class="mt-auto py-6 border-t border-white/5 text-center text-xs text-zinc-600 bg-black/20">
                GZMBOT • Consola de Administración Premium • Hecho con dedicación en RD
            </footer>
        </main>
    </div>

    <!-- MODAL DE CONTACTOS -->
    <div id="contact-modal" class="modal" onclick="if(event.target===this) closeContactModal()">
        <div class="modal-content">
            <div class="flex justify-between items-center mb-4">
                <h3 class="text-xl font-bold">Seleccionar contacto</h3>
                <button onclick="closeContactModal()" class="p-2 rounded-full hover:bg-white/5"><i data-lucide="x" class="w-5 h-5"></i></button>
            </div>
            <input type="text" id="contactSearch" placeholder="Buscar..." class="w-full mb-4 bg-black/40 border border-white/5 rounded-xl p-3 text-white">
            <div id="contactList" class="space-y-2 max-h-96 overflow-y-auto"></div>
        </div>
    </div>

    <!-- TOAST NOTIFICATIONS -->
    <div id="toast" class="toast">
        <i data-lucide="check-circle" class="text-green-500 w-5 h-5"></i>
        <span id="toast-message">Operación exitosa</span>
    </div>

    <script>
        // ==================== VARIABLES GLOBALES ====================
        const socket = io();
        let db = { training:[], learning:[], reminders:[], excluded:[], stats:{ replied:0, total:0 } };
        let contacts = [];
        let currentMediaType = 'text';
        let selectedFiles = [];
        let activePhoneField = null;
        let activeNameField = null;
        
        // ==================== UTILIDADES ====================
        function showToast(message, isError = false) {
            const toast = document.getElementById('toast');
            document.getElementById('toast-message').textContent = message;
            toast.style.borderLeftColor = isError ? '#ef4444' : '#2563eb';
            toast.classList.add('show');
            setTimeout(() => toast.classList.remove('show'), 3000);
        }

        function toggleSidebar() { document.getElementById('sidebar').classList.toggle('-translate-x-full'); }
        function closeMobileSidebar() { if (window.innerWidth < 1024) document.getElementById('sidebar').classList.add('-translate-x-full'); }
        function nav(pageId) {
            document.querySelectorAll('.page-content').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.sidebar-item').forEach(i => i.classList.remove('active'));
            document.getElementById('p-'+pageId).classList.add('active');
            document.getElementById('n-'+pageId).classList.add('active');
            lucide.createIcons();
            closeMobileSidebar();
        }

        // Reloj en tiempo real (hora RD)
        function updateClock() {
            const now = new Date();
            const optionsTime = { timeZone: 'America/Santo_Domingo', hour12: true, hour: '2-digit', minute: '2-digit', second: '2-digit' };
            const timeStr = now.toLocaleString('en-US', optionsTime);
            const optionsDate = { timeZone: 'America/Santo_Domingo', weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' };
            const dateStr = now.toLocaleDateString('es-ES', optionsDate);
            document.querySelectorAll('.clock-time').forEach(el => el.textContent = timeStr);
            document.querySelectorAll('.clock-date').forEach(el => el.textContent = dateStr);
        }
        setInterval(updateClock, 1000);
        updateClock();

        // ==================== SOCKET.IO EVENTOS ====================
        socket.on('connection_status', (data) => {
            const qrContainer = document.getElementById('qr-img');
            const logoutBtn = document.getElementById('btn-logout-wa');
            const waStatusBox = document.getElementById('wa-status-box');
            if (data.connected) {
                if (qrContainer) qrContainer.innerHTML = '<span class="text-green-500">✅ Conectado</span>';
                if (logoutBtn) logoutBtn.style.display = 'block';
                if (waStatusBox) {
                    waStatusBox.innerHTML = `<div class="w-2.5 h-2.5 rounded-full bg-green-500 animate-pulse"></div><div><p class="font-bold text-white">WhatsApp Conectado</p><p class="text-zinc-500">Bot activo</p></div>`;
                }
            } else {
                if (logoutBtn) logoutBtn.style.display = 'none';
                if (waStatusBox) {
                    waStatusBox.innerHTML = `<div class="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse"></div><div><p class="font-bold text-white">No conectado</p><p class="text-zinc-500">Escanea el QR</p></div>`;
                }
            }
        });

        socket.on('qr_update', (url) => {
            const qrImg = document.getElementById('qr-img');
            if (qrImg) qrImg.innerHTML = `<img src="${url}" class="w-full h-full object-contain">`;
        });

        socket.on('qr_clear', () => {
            const qrImg = document.getElementById('qr-img');
            if (qrImg) qrImg.innerHTML = '<span class="text-sm text-gray-500">Esperando QR...</span>';
        });

        socket.on('data_update', (data) => { db = data; render(); });
        socket.on('contacts_update', (data) => { contacts = data; if (document.getElementById('contact-modal').classList.contains('active')) renderContactList(); });
        socket.on('queue_size', (size) => { document.getElementById('queue-size').textContent = size; });
        socket.on('config_update', (cfg) => {
            if (cfg.responseDelay !== undefined) { document.getElementById('response-delay').value = cfg.responseDelay; document.getElementById('delay-value').textContent = cfg.responseDelay.toFixed(1)+' s'; }
            if (cfg.queueInterval !== undefined) { document.getElementById('queue-interval').value = cfg.queueInterval; document.getElementById('interval-value').textContent = cfg.queueInterval+' ms'; }
        });

        // ==================== CARGA INICIAL DE DATOS ====================
        async function load() {
            try {
                const res = await fetch('/api/data');
                if (res.status === 401) { location.href = '/login'; return; }
                const data = await res.json();
                db = data;
                document.getElementById('conf-backup-phone').value = data.backupPhone || '';
                document.getElementById('response-delay').value = data.responseDelay || 0;
                document.getElementById('delay-value').textContent = (data.responseDelay || 0).toFixed(1)+' s';
                document.getElementById('queue-interval').value = data.queueInterval || 3000;
                document.getElementById('interval-value').textContent = (data.queueInterval || 3000)+' ms';
                document.getElementById('queue-size').textContent = data.queueSize || 0;
                render();
                lucide.createIcons();
                const contactsRes = await fetch('/api/contacts');
                contacts = await contactsRes.json();
            } catch(e) { console.error(e); }
        }

        // ==================== RENDERIZADO DE LISTAS ====================
        function esc(str) { if(!str) return ''; return String(str).replace(/[&<>]/g, function(m){ if(m === '&') return '&amp;'; if(m === '<') return '&lt;'; if(m === '>') return '&gt;'; return m; }).replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, function(c){ return c; }); }
        function formatDate(dateStr) { if(!dateStr) return ''; try { const d = new Date(dateStr); return d.toLocaleString('es-ES', { timeZone: 'America/Santo_Domingo' }); } catch(e){ return dateStr; } }

        function render() {
            document.getElementById('stat-replied').innerText = db.stats ? db.stats.replied : 0;
            document.getElementById('stat-total').innerText = db.stats ? db.stats.total : 0;
            document.getElementById('reminders-count').innerText = (db.reminders || []).length;

            // Training list
            document.getElementById('l-train').innerHTML = (db.training || []).map(t => `
                <div class="glass-card p-5 rounded-2xl">
                    <div class="flex justify-between items-start">
                        <div><span class="text-blue-400 font-bold">P:</span> <span class="font-medium">${esc(t.key)}</span> ${t.mediaPaths && JSON.parse(t.mediaPaths).length ? `<span class="text-[10px] bg-blue-500/20 px-2 py-1 rounded ml-2">${JSON.parse(t.mediaPaths).length} archivo(s)</span>` : ''}</div>
                        <div class="flex gap-2"><button onclick="editT(${t.id})" class="p-2 text-zinc-400 hover:text-white"><i data-lucide="edit-3" class="w-4 h-4"></i></button><button onclick="delT(${t.id})" class="p-2 text-red-400"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div>
                    </div>
                    <p class="text-sm text-zinc-400 mt-2">${esc(t.response)}</p>
                    ${t.mediaPaths && JSON.parse(t.mediaPaths).length ? `<div class="media-preview-container mt-3">${JSON.parse(t.mediaPaths).map(p => `<img src="/${p}" class="media-preview">`).join('')}</div>` : ''}
                </div>
            `).join('') || '<div class="text-center text-zinc-500 py-10">No hay respuestas configuradas</div>';

            // Learning list
            document.getElementById('l-learn').innerHTML = (db.learning || []).map(l => `
                <div class="glass-card p-4 rounded-2xl flex justify-between items-center">
                    <div><small class="text-zinc-500">${l.date} - ${l.from_phone}</small><br><span class="text-sm">${esc(l.text)}</span>${l.hasMedia ? ' <span class="text-[10px] bg-purple-500/20 px-2 py-1 rounded">MEDIA</span>' : ''}</div>
                    <div class="flex gap-2"><button onclick="useL(${l.id})" class="px-4 py-2 bg-blue-600 rounded-xl text-xs font-bold">Usar</button><button onclick="delL(${l.id})" class="p-2 text-red-400"><i data-lucide="x" class="w-4 h-4"></i></button></div>
                </div>
            `).join('') || '<div class="text-center text-zinc-500 py-10">No hay mensajes pendientes</div>';

            // Reminders list
            document.getElementById('l-rem').innerHTML = (db.reminders || []).map(r => `
                <div class="glass-card p-5 rounded-2xl border-l-4 border-emerald-500">
                    <div class="flex justify-between"><b class="text-lg">${esc(r.name)}</b><div><button onclick="editR(${r.id})" class="p-1"><i data-lucide="edit-3" class="w-4 h-4"></i></button><button onclick="delR(${r.id})" class="p-1"><i data-lucide="trash-2" class="w-4 h-4 text-red-400"></i></button></div></div>
                    <p class="text-sm text-zinc-400">📱 ${r.phone}</p>
                    <p class="text-sm mt-2">${esc(r.message)}</p>
                    <div class="flex gap-2 mt-3"><span class="badge">${r.freq}</span><span class="badge">📅 ${formatDate(r.date)}</span></div>
                </div>
            `).join('') || '<div class="text-center text-zinc-500 py-10">No hay recordatorios</div>';

            // Excluded list
            document.getElementById('l-excl').innerHTML = (db.excluded || []).map(e => `
                <div class="flex justify-between items-center p-3 glass-card rounded-xl">
                    <span>${esc(e.name)} (${e.phone})</span>
                    <button onclick="delE(${e.id})" class="p-2 text-red-400"><i data-lucide="user-minus" class="w-4 h-4"></i></button>
                </div>
            `).join('') || '<div class="text-center text-zinc-500 py-5">No hay números excluidos</div>';

            lucide.createIcons();
        }

        // ==================== FUNCIONES DE LAS API ====================
        async function saveTrain(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('id', document.getElementById('t-id').value);
            fd.append('key', document.getElementById('t-key').value);
            fd.append('response', document.getElementById('t-res').value);
            if (currentMediaType !== 'text' && selectedFiles.length) selectedFiles.forEach(f => fd.append('media', f));
            const res = await fetch('/api/train', { method:'POST', body:fd });
            if (res.ok) {
                showToast('Respuesta guardada');
                document.getElementById('t-id').value=''; document.getElementById('t-key').value=''; document.getElementById('t-res').value='';
                document.getElementById('t-media').value=''; document.getElementById('media-preview').innerHTML=''; selectedFiles=[]; setMediaType('text');
                load();
            } else showToast('Error al guardar', true);
        }

        function editT(id) { const t = db.training.find(t=>t.id==id); if(t){ document.getElementById('t-id').value=t.id; document.getElementById('t-key').value=t.key; document.getElementById('t-res').value=t.response; if(t.mediaPaths && JSON.parse(t.mediaPaths).length) setMediaType('image'); window.scrollTo({top:0}); } }
        async function delT(id) { if(confirm('¿Eliminar esta respuesta?')){ const res = await fetch('/api/train/'+id, {method:'DELETE'}); if(res.ok){ showToast('Eliminada'); load(); } else showToast('Error', true); } }
        function useL(id) { const l = db.learning.find(l=>l.id==id); if(l){ document.getElementById('t-key').value=l.text; nav('train'); document.getElementById('t-res').focus(); } }
        async function delL(id) { const res = await fetch('/api/learning/'+id, {method:'DELETE'}); if(res.ok){ showToast('Mensaje eliminado'); load(); } else showToast('Error', true); }
        
        async function saveRem() {
            const data = { id:document.getElementById('r-id').value, name:document.getElementById('r-name').value, phone:document.getElementById('r-phone').value, message:document.getElementById('r-msg').value, freq:document.getElementById('r-freq').value, date:document.getElementById('r-date').value };
            if(!data.name || !data.phone || !data.message || !data.date){ alert('Completa todos los campos'); return; }
            const res = await fetch('/api/reminders', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data) });
            if(res.ok){ showToast('Recordatorio guardado'); document.getElementById('r-id').value=''; document.getElementById('r-name').value=''; document.getElementById('r-phone').value=''; document.getElementById('r-msg').value=''; document.getElementById('r-date').value=''; load(); } else showToast('Error', true);
        }
        function editR(id) { const r = db.reminders.find(r=>r.id==id); if(r){ document.getElementById('r-id').value=r.id; document.getElementById('r-name').value=r.name; document.getElementById('r-phone').value=r.phone; document.getElementById('r-msg').value=r.message; document.getElementById('r-freq').value=r.freq; document.getElementById('r-date').value=r.date; window.scrollTo({top:0}); } }
        async function delR(id) { if(confirm('¿Eliminar recordatorio?')){ const res = await fetch('/api/reminders/'+id, {method:'DELETE'}); if(res.ok){ showToast('Eliminado'); load(); } else showToast('Error', true); } }

        async function saveExcl() { const name=document.getElementById('e-name').value, phone=document.getElementById('e-phone').value; if(!name || !phone){ alert('Complete los campos'); return; } const res = await fetch('/api/exclude', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({name,phone}) }); if(res.ok){ showToast('Añadido a exclusión'); document.getElementById('e-name').value=''; document.getElementById('e-phone').value=''; load(); } else showToast('Error', true); }
        async function delE(id) { if(confirm('¿Quitar de excluidos?')){ const res = await fetch('/api/exclude/'+id, {method:'DELETE'}); if(res.ok){ showToast('Eliminado'); load(); } else showToast('Error', true); } }

        async function saveCredentials() { const user=document.getElementById('conf-user').value, pass=document.getElementById('conf-pass').value; if(!user && !pass){ alert('Ingresa al menos un campo'); return; } const res = await fetch('/api/config/credentials', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({user,pass}) }); if(res.ok){ showToast('Credenciales actualizadas. Re-inicia sesión.'); setTimeout(()=>location.href='/login',1500); } else showToast('Error', true); }
        async function saveBackupPhone() { const bp = document.getElementById('conf-backup-phone').value.replace(/\D/g,''); const res = await fetch('/api/config/backup-phone', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({backupPhone:bp}) }); if(res.ok) showToast('Número guardado'); else showToast('Error', true); }
        async function saveConfiguracionEnvio() { const delay = parseFloat(document.getElementById('response-delay').value); const interval = parseInt(document.getElementById('queue-interval').value); await fetch('/api/config/delay', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({delay}) }); await fetch('/api/config/queue-interval', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({interval}) }); showToast('Configuración guardada'); }
        function downloadBackup() { window.location.href='/api/backup/download'; }
        function downloadTemplate() { window.location.href='/api/train/template'; }
        function exportTraining() { window.location.href='/api/train/export'; }
        async function sendBackupManually() { const phone = document.getElementById('conf-backup-phone').value; if(!phone){ alert('Guarda un número primero'); return; } const res = await fetch('/api/backup/send', {method:'POST'}); const data = await res.json(); if(data.ok) showToast('Backup enviado'); else showToast(data.message || 'Error', true); }
        async function restoreBackup(input) { if(!input.files[0]) return; if(!confirm('¿Restaurar backup?')){ input.value=''; return; } const fd = new FormData(); fd.append('backup', input.files[0]); const res = await fetch('/api/backup/restore', {method:'POST', body:fd}); const data = await res.json(); if(data.ok){ showToast('Restaurado correctamente'); setTimeout(()=>location.reload(),1500); } else showToast('Error: '+data.error, true); input.value=''; }
        async function importTraining(input) { if(!input.files[0]) return; const fd = new FormData(); fd.append('file', input.files[0]); const res = await fetch('/api/train/import', {method:'POST', body:fd}); const data = await res.json(); if(data.ok){ showToast(`${data.imported} respuestas importadas`); load(); } else showToast('Error: '+data.error, true); input.value=''; }
        async function logoutWA() { if(confirm('¿Desvincular WhatsApp? Se reiniciarán los contadores.')){ const res = await fetch('/api/logout-wa', {method:'POST'}); if(res.ok){ showToast('WhatsApp desconectado. Recargando...'); setTimeout(()=>location.reload(),3500); } else showToast('Error al desconectar', true); } }
        function handleLogout() { location.href = '/login'; }

        // ==================== MEDIA UPLOAD ====================
        function setMediaType(type) {
            currentMediaType = type;
            document.querySelectorAll('.media-type-btn').forEach(b=>b.classList.remove('active'));
            document.getElementById('mt-'+type).classList.add('active');
            if(type === 'text') document.getElementById('media-upload').classList.add('hidden');
            else { document.getElementById('media-upload').classList.remove('hidden'); document.getElementById('t-media').accept = type==='image'?'image/*':'video/*'; }
        }
        document.getElementById('t-media')?.addEventListener('change', function(e) {
            selectedFiles = Array.from(e.target.files);
            const preview = document.getElementById('media-preview');
            preview.innerHTML = '';
            selectedFiles.forEach((file, idx) => {
                const reader = new FileReader();
                reader.onload = ev => {
                    const div = document.createElement('div'); div.className='media-item';
                    if(file.type.startsWith('image/')) div.innerHTML = `<img src="${ev.target.result}" class="media-preview"><div class="media-remove" onclick="removeMediaFile(${idx})">×</div>`;
                    else div.innerHTML = `<video src="${ev.target.result}" class="media-preview" controls></video><div class="media-remove" onclick="removeMediaFile(${idx})">×</div>`;
                    preview.appendChild(div);
                };
                reader.readAsDataURL(file);
            });
        });
        function removeMediaFile(idx) { selectedFiles.splice(idx,1); const dt = new DataTransfer(); selectedFiles.forEach(f=>dt.items.add(f)); document.getElementById('t-media').files = dt.files; document.getElementById('t-media').dispatchEvent(new Event('change')); }

        // ==================== MODAL DE CONTACTOS ====================
        function openContactModal(phoneFieldId, nameFieldId) { activePhoneField = phoneFieldId; activeNameField = nameFieldId; document.getElementById('contact-modal').classList.add('active'); renderContactList(); }
        function closeContactModal() { document.getElementById('contact-modal').classList.remove('active'); activePhoneField = null; activeNameField = null; }
        function renderContactList() {
            const search = document.getElementById('contactSearch').value.toLowerCase();
            const filtered = contacts.filter(c => (c.name && c.name.toLowerCase().includes(search)) || (c.number && c.number.includes(search)));
            const list = document.getElementById('contactList');
            if(filtered.length===0) { list.innerHTML = '<div class="text-center text-zinc-500 py-5">No hay contactos</div>'; return; }
            list.innerHTML = filtered.map(c => `<div class="contact-item" onclick="selectContact('${c.number}', '${c.name.replace(/'/g,"\\'")}')"><div><div class="contact-name">${esc(c.name||'Sin nombre')}</div><div class="contact-number">${c.number}</div></div></div>`).join('');
        }
        function selectContact(number, name) { if(activePhoneField) document.getElementById(activePhoneField).value = number; if(activeNameField && document.getElementById(activeNameField)) document.getElementById(activeNameField).value = name; closeContactModal(); }
        document.getElementById('contactSearch')?.addEventListener('input', renderContactList);

        // Sliders display
        document.getElementById('response-delay')?.addEventListener('input', function(e){ document.getElementById('delay-value').textContent = parseFloat(e.target.value).toFixed(1)+' s'; });
        document.getElementById('queue-interval')?.addEventListener('input', function(e){ document.getElementById('interval-value').textContent = e.target.value+' ms'; });

        window.onload = load;
        lucide.createIcons();
    </script>
</body>
</html>
HTMLEOF

# ----------------------------------------------------------------------
# 9. LOGIN PAGE CON EL MISMO ESTILO
# ----------------------------------------------------------------------
cat <<'LOGINEOF' > views/login.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GZMBOT | Login</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&family=Outfit:wght@400;600;800;900&display=swap" rel="stylesheet">
    <style>
        body {
            background-color: #06060a;
            font-family: 'Inter', sans-serif;
            background-image: radial-gradient(circle at 30% 10%, rgba(37, 99, 235, 0.08) 0%, transparent 40%);
        }
        .glass-panel {
            background: rgba(13, 13, 23, 0.75);
            backdrop-filter: blur(20px) saturate(180%);
            border: 1px solid rgba(255, 255, 255, 0.04);
        }
        .gradient-text {
            background: linear-gradient(135deg, #ffffff 30%, #a5b4fc 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
    </style>
</head>
<body class="flex items-center justify-center min-h-screen p-4">
    <div class="fixed top-[-20%] left-[-10%] w-[600px] h-[600px] rounded-full bg-blue-900/10 blur-[140px] pointer-events-none"></div>
    <div class="fixed bottom-[-10%] right-[-10%] w-[500px] h-[500px] rounded-full bg-indigo-900/10 blur-[130px] pointer-events-none"></div>
    
    <div class="w-full max-w-[440px] glass-panel rounded-[2.5rem] p-8 sm:p-12 relative overflow-hidden shadow-[0_0_50px_rgba(0,0,0,0.6)]">
        <div class="text-center mb-8">
            <div class="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-blue-600/10 border border-blue-500/20 text-blue-500 mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/></svg>
            </div>
            <h1 class="text-3xl sm:text-4xl font-black tracking-tight font-outfit gradient-text">GZMBOT</h1>
            <p class="text-blue-400 font-bold text-[11px] tracking-[0.35em] uppercase mt-2">Administrative Panel</p>
        </div>

        <form onsubmit="login(event)" class="space-y-4">
            <div class="space-y-1">
                <label class="text-xs font-semibold text-zinc-400 ml-1">Usuario Maestro</label>
                <input type="text" id="u" placeholder="admin" class="w-full px-4 py-3.5 bg-black/40 rounded-2xl border border-white/5 text-white placeholder-zinc-600 outline-none focus:border-blue-500/50 transition-colors text-sm" required>
            </div>
            <div class="space-y-1">
                <label class="text-xs font-semibold text-zinc-400 ml-1">Contraseña</label>
                <input type="password" id="p" placeholder="••••••••" class="w-full px-4 py-3.5 bg-black/40 rounded-2xl border border-white/5 text-white placeholder-zinc-600 outline-none focus:border-blue-500/50 transition-colors text-sm" required>
            </div>
            <button type="submit" class="w-full py-4 bg-gradient-to-r from-blue-600 to-blue-500 rounded-2xl text-white font-bold text-sm tracking-wide shadow-lg shadow-blue-500/10 hover:shadow-blue-500/20 hover:scale-[1.01] active:scale-95 transition-all flex items-center justify-center gap-2 mt-2">
                ACCEDER AL PANEL
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
            </button>
        </form>
        <div class="text-center mt-8 text-[11px] text-zinc-500">
            GZMBOT Engine v3.1 • © 2026 RD
        </div>
    </div>

    <script>
        async function login(e) {
            e.preventDefault();
            const user = document.getElementById('u').value;
            const pass = document.getElementById('p').value;
            const res = await fetch('/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ user, pass })
            });
            const data = await res.json();
            if (data.ok) {
                window.location.href = '/';
            } else {
                alert('Credenciales incorrectas');
            }
        }
    </script>
</body>
</html>
LOGINEOF

# ----------------------------------------------------------------------
# 10. INSTALAR DEPENDENCIAS DE NODE Y CONFIGURAR PM2
# ----------------------------------------------------------------------
echo "📦 Instalando dependencias de Node.js (esto puede tomar unos minutos)..."
cd $HOME/gzmbot

npm install --no-audit --no-fund whatsapp-web.js qrcode express socket.io express-session puppeteer moment-timezone node-cron multer better-sqlite3
npm cache clean --force
npm audit fix --force

sudo npm install -g pm2
pm2 delete gzmbot 2>/dev/null
pm2 start app.js --name gzmbot --env TZ=America/Santo_Domingo --max-memory-restart 512M
pm2 save
pm2 startup

# ----------------------------------------------------------------------
# 11. INSTALAR NGINX Y CONFIGURAR PROXY CON SSL
# ----------------------------------------------------------------------
echo "🔧 Instalando Nginx y configurando SSL con Let's Encrypt..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

sudo tee /etc/nginx/sites-available/gzmbot > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    client_max_body_size 10M;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/gzmbot /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Obtener certificado SSL (si el dominio ya apunta al servidor)
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect || echo "⚠️ No se pudo obtener SSL automáticamente. Revisa que el dominio apunte a este servidor."

# ----------------------------------------------------------------------
# 12. MOSTRAR INFORMACIÓN FINAL
# ----------------------------------------------------------------------
echo ""
echo "===================================================="
echo "✨ GZMBOT ENTERPRISE - INSTALACIÓN COMPLETADA"
echo "===================================================="
echo "🌐 PANEL: https://$DOMAIN"
echo "👤 USUARIO: $ADMIN_USER"
echo "🔐 PASS: $ADMIN_PASS"
echo "🕐 TIMEZONE: America/Santo_Domingo (UTC-4)"
echo "🗄️ BASE DE DATOS: SQLite (alto rendimiento)"
echo "===================================================="
echo "✅ Node.js versión instalada: $(node --version)"
echo "✅ NPM versión instalada: $(npm --version)"
echo "✅ Google Chrome versión: $(google-chrome-stable --version)"
echo "===================================================="
echo "💡 Para monitorear el proceso: pm2 monit"
echo "💡 Para ver logs: pm2 logs gzmbot"
echo "💡 Si el panel no carga, espera 30 segundos y refresca"
echo "===================================================="