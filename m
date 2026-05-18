#!/bin/bash

# ============================================================

clear
echo " ⚙️ Iniciando Instalación de GZMBOT v12"

read -p "👤 Usuario Maestro: " ADMIN_USER
read -sp "🔐 Contraseña Maestra: " ADMIN_PASS
echo ""
read -p "🌐 Dominio para el panel : " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "❌ Debes ingresar un dominio válido."
    exit 1
fi

# ----------------------------------------------------------------------
# 1. DEPENDENCIAS DEL SISTEMA Y GOOGLE CHROME STABLE
# ----------------------------------------------------------------------
echo "📦 Instalando dependencias del sistema y Google Chrome..."
sudo apt-get update
sudo apt-get install -y \
    curl wget gnupg2 \
    ca-certificates \
    fonts-liberation \
    libappindicator3-1 \
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
    xdg-utils \
    resolvconf \
    --no-install-recommends

# DNS público para evitar EAI_AGAIN
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf

sudo mkdir -p /usr/share/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt-get update
sudo apt-get install -y google-chrome-stable

if ! command -v google-chrome-stable &> /dev/null; then
    echo "❌ Error: No se pudo instalar Google Chrome."
    exit 1
fi
echo "✅ Google Chrome instalado: $(google-chrome-stable --version)"
sudo ldconfig

# ----------------------------------------------------------------------
# 2. VARIABLES DE ENTORNO
# ----------------------------------------------------------------------
export PUPPETEER_EXECUTABLE_PATH=$(which google-chrome-stable)
export PUPPETEER_SKIP_DOWNLOAD=true
export TZ='America/Santo_Domingo'

# ----------------------------------------------------------------------
# 3. NODE.JS 20 LTS Y PM2
# ----------------------------------------------------------------------
echo "🟢 Instalando Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# ----------------------------------------------------------------------
# 4. ZONA HORARIA
# ----------------------------------------------------------------------
sudo timedatectl set-timezone America/Santo_Domingo 2>/dev/null || true

# ----------------------------------------------------------------------
# 5. ESTRUCTURA DE CARPETAS
# ----------------------------------------------------------------------
mkdir -p $HOME/gzmbot/views
mkdir -p $HOME/gzmbot/data
mkdir -p $HOME/gzmbot/media
mkdir -p $HOME/gzmbot/backups
cd $HOME/gzmbot

# ----------------------------------------------------------------------
# 6. CONFIG.JSON
# ----------------------------------------------------------------------
cat <<EOF > config.json
{
  "adminUser": "$ADMIN_USER",
  "adminPassword": "$ADMIN_PASS",
  "port": 3000,
  "sessionSecret": "$(openssl rand -hex 24)",
  "backupPhone": "",
  "responseDelay": 0,
  "queueInterval": 500,
  "cleanupLearningInterval": "off",
  "netflix": {
    "intervalSeconds": 120,
    "accounts": []
  }
}
EOF

# ----------------------------------------------------------------------
# 7. ARCHIVOS DE DATOS NETFLIX
# ----------------------------------------------------------------------
echo '[]' > data/netflix_logs.json
echo '[]' > data/netflix_processed.json

# ----------------------------------------------------------------------
# 8. MOTOR NETFLIX (netflix-engine.js) – SIN CAMBIOS, ROBUSTO
# ----------------------------------------------------------------------
cat <<'NETFLIXEOF' > netflix-engine.js
const fs = require('fs');
const path = require('path');
const { ImapFlow } = require('imapflow');
const { simpleParser } = require('mailparser');
const axios = require('axios');
const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());
const EventEmitter = require('events');

const LOGS_FILE = path.join(__dirname, 'data', 'netflix_logs.json');
const PROCESSED_FILE = path.join(__dirname, 'data', 'netflix_processed.json');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const USER_DATA_DIR_BASE = path.join(__dirname, '.puppeteer_data');

function getConfig() {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
}

function getLogs() {
    try { return JSON.parse(fs.readFileSync(LOGS_FILE, 'utf8')); } catch (e) { return []; }
}

function saveLogs(logs) {
    const trimmed = logs.slice(0, 200);
    fs.writeFileSync(LOGS_FILE, JSON.stringify(trimmed, null, 2));
}

function getProcessed() {
    try { return JSON.parse(fs.readFileSync(PROCESSED_FILE, 'utf8')); } catch (e) { return []; }
}

function saveProcessed(processed) {
    const cutoff = Date.now() - 7 * 24 * 3600 * 1000;
    const fresh = processed.filter(p => p.timestamp > cutoff);
    fs.writeFileSync(PROCESSED_FILE, JSON.stringify(fresh, null, 2));
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

class NetflixEngine extends EventEmitter {
    constructor(io) {
        super();
        this.io = io;
        this.config = getConfig().netflix || { intervalSeconds: 120, accounts: [] };
        this.timers = new Map();
        this.processingQueue = new Map();
        if (!fs.existsSync(USER_DATA_DIR_BASE)) fs.mkdirSync(USER_DATA_DIR_BASE, { recursive: true });
    }

    getCurrentAccountConfig(email) {
        const cfg = getConfig().netflix || { accounts: [] };
        return cfg.accounts.find(a => a.email === email) || {};
    }

    async #autoUpdateHousehold(link, accountEmail, extractedCode = null) {
        let browser = null;
        let result = { success: false, steps: [], error: null, finalMessage: '', codeUsed: extractedCode };
        
        const userDataDir = path.join(USER_DATA_DIR_BASE, Buffer.from(accountEmail).toString('base64').replace(/[^a-z0-9]/gi, '_'));
        if (!fs.existsSync(userDataDir)) fs.mkdirSync(userDataDir, { recursive: true });
        
        const logStep = (msg) => {
            console.log(`[Netflix-${accountEmail}] ${msg}`);
            result.steps.push(msg);
        };

        const randomDelay = (min, max) => sleep(Math.floor(Math.random() * (max - min + 1) + min) * 1000);

        try {
            logStep("Iniciando navegador stealth...");
            browser = await puppeteer.launch({
                executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/google-chrome-stable',
                headless: 'new',
                userDataDir: userDataDir,
                args: [
                    '--no-sandbox',
                    '--disable-setuid-sandbox',
                    '--disable-dev-shm-usage',
                    '--disable-gpu',
                    '--window-size=1280,800',
                    '--lang=es-ES'
                ],
                defaultViewport: { width: 1280, height: 800 }
            });

            const page = await browser.newPage();
            await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
            
            await page.mouse.move(100, 100);
            await randomDelay(1, 3);
            await page.evaluate(() => window.scrollBy(0, Math.random() * 100));
            
            logStep(`Navegando a: ${link}`);
            await page.goto(link, { waitUntil: 'networkidle2', timeout: 45000 });
            await randomDelay(3, 6);
            
            if (extractedCode) {
                try {
                    const codeInput = await page.$('input[type="text"], input[type="number"], input[name="code"], input[autocomplete="one-time-code"]');
                    if (codeInput) {
                        await codeInput.click({ clickCount: 3 });
                        await randomDelay(1, 2);
                        await codeInput.type(extractedCode);
                        logStep(`✅ Código ${extractedCode} ingresado automáticamente`);
                        await randomDelay(2, 4);
                        const verifyBtn = await page.$x("//button[contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'verificar') or contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'verify') or contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'enviar')]");
                        if (verifyBtn.length) {
                            await verifyBtn[0].click();
                            logStep(`Botón de verificar presionado`);
                            await randomDelay(3, 5);
                        }
                    }
                } catch (err) {
                    logStep(`No se pudo ingresar código automáticamente: ${err.message}`);
                }
            }
            
            const buttonSelectors = [
                'button:has-text("Actualizar hogar")', 'button:has-text("Confirmar")', 'button:has-text("Continuar")', 'button:has-text("Sí, actualizar")',
                'button:has-text("Update household")', 'button:has-text("Confirm")', 'button:has-text("Continue")', 'button:has-text("Yes, update")',
                'button:has-text("Actualizar")', 'button:has-text("Update")', 'button:has-text("Aceptar")', 'button:has-text("Accept")',
                'button:has-text("Verificar")', 'button:has-text("Verify")', 'button:has-text("Enviar")', 'button:has-text("Submit")',
                'button:has-text("Siguiente")', 'button:has-text("Next")'
            ];
            const xpaths = [
                '//button[contains(translate(text(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"), "actualizar")]',
                '//button[contains(translate(text(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"), "confirmar")]',
                '//a[contains(translate(text(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"), "actualizar")]'
            ];
            
            let clickCount = 0;
            let maxClicks = 5;
            let finished = false;
            let successDetected = false;
            
            while (clickCount < maxClicks && !finished) {
                let clicked = false;
                for (const selector of buttonSelectors) {
                    try {
                        const button = await page.$(selector);
                        if (button && await button.isIntersectingViewport()) {
                            await randomDelay(2, 5);
                            await button.hover();
                            await randomDelay(1, 2);
                            await button.click();
                            logStep(`Clic en botón: ${selector}`);
                            clicked = true;
                            clickCount++;
                            await randomDelay(4, 7);
                            await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 15000 }).catch(() => {});
                            break;
                        }
                    } catch (err) {}
                }
                if (!clicked) {
                    for (const xpath of xpaths) {
                        try {
                            const [button] = await page.$x(xpath);
                            if (button && await button.isIntersectingViewport()) {
                                await randomDelay(2, 5);
                                await button.hover();
                                await randomDelay(1, 2);
                                await button.click();
                                logStep(`Clic en XPath: ${xpath}`);
                                clicked = true;
                                clickCount++;
                                await randomDelay(4, 7);
                                await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 15000 }).catch(() => {});
                                break;
                            }
                        } catch (err) {}
                    }
                }
                
                if (!clicked) {
                    const pageContent = await page.content();
                    const successKeywords = ['hogar actualizado', 'household updated', 'todo listo', 'ya está actualizado', 'update successful', 'código correcto', 'verificación exitosa'];
                    for (const kw of successKeywords) {
                        if (pageContent.toLowerCase().includes(kw)) {
                            successDetected = true;
                            finished = true;
                            result.success = true;
                            result.finalMessage = 'Hogar actualizado correctamente';
                            logStep(`✅ Éxito detectado: "${kw}"`);
                            break;
                        }
                    }
                    if (!finished) {
                        logStep(`No se encontraron más botones. Verificando si ya está actualizado...`);
                        await randomDelay(5, 10);
                        finished = true;
                        result.success = true;
                        result.finalMessage = 'Proceso completado sin más interacción (posiblemente ya actualizado)';
                    }
                    break;
                }
            }
            
            if (result.success) {
                logStep(`✅ Actualización finalizada: ${result.finalMessage}`);
            } else {
                result.success = false;
                result.finalMessage = 'No se pudo completar la actualización automática después de varios intentos';
                logStep(`❌ Falló: ${result.finalMessage}`);
            }
            
            await randomDelay(2, 4);
            await browser.close();
            return result;
            
        } catch (err) {
            logStep(`❌ Error en automatización: ${err.message}`);
            if (browser) await browser.close().catch(()=>{});
            result.success = false;
            result.error = err.message;
            result.finalMessage = `Error: ${err.message}`;
            return result;
        }
    }

    extractNetflixData(parsed) {
        const text = (parsed.text || '') + ' ' + (parsed.html || '');
        let code = null;
        let link = null;

        const code4Match = text.match(/\b(\d{4})\b/);
        const code6Match = text.match(/\b(\d{6})\b/);
        if (code6Match) code = code6Match[1];
        else if (code4Match) code = code4Match[1];

        const html = parsed.html || '';
        const linkRegex = /<a\s+(?:[^>]*?\s+)?href="(https:\/\/www\.netflix\.com\/account\/verify\?[^"]+)"/i;
        const linkMatch = html.match(linkRegex);
        if (linkMatch) link = linkMatch[1];
        else {
            const textLinkMatch = text.match(/(https:\/\/www\.netflix\.com\/account\/verify\?\S+)/i);
            if (textLinkMatch) link = textLinkMatch[1];
        }

        const subject = (parsed.subject || '').toLowerCase();
        const isAccountVerification = subject.includes('verificación de seguridad') ||
                                      subject.includes('account verification') ||
                                      subject.includes('código de verificación');

        return { code, link, isAccountVerification };
    }

    async processEmail(parsed, uid, messageId, accountEmail, messageQueue) {
        const account = this.getCurrentAccountConfig(accountEmail);
        if (!account || !account.email) return null;

        const { code, link, isAccountVerification } = this.extractNetflixData(parsed);
        const from = parsed.from ? parsed.from.text : 'Desconocido';
        const subject = parsed.subject || 'Sin asunto';

        if (!code && !link) return null;

        const logEntry = {
            id: Date.now().toString(36) + Math.random().toString(36).substr(2),
            timestamp: new Date().toISOString(),
            account: account.email,
            from,
            subject,
            code: code || null,
            link: link || null,
            isAccountVerification: isAccountVerification,
            viewed: false,
            viewedAt: null,
            codeSentTo: [],
            linkInteraction: null
        };

        if (link) {
            if (this.processingQueue.get(account.email)) {
                console.log(`⏳ Ya hay un proceso en curso para ${account.email}, omitiendo temporalmente.`);
                return null;
            }
            this.processingQueue.set(account.email, true);
            let attempt = 0;
            let success = false;
            while (attempt < 3 && !success) {
                const automationResult = await this.#autoUpdateHousehold(link, account.email, code);
                logEntry.linkInteraction = {
                    success: automationResult.success,
                    steps: automationResult.steps,
                    finalMessage: automationResult.finalMessage,
                    codeUsed: automationResult.codeUsed,
                    error: automationResult.error,
                    attempt: attempt + 1
                };
                if (automationResult.success) {
                    success = true;
                } else {
                    attempt++;
                    if (attempt < 3) {
                        console.log(`Reintento ${attempt+1} para ${account.email}...`);
                        await sleep(10000);
                    }
                }
            }
            this.processingQueue.delete(account.email);
        }

        const groupPhone = account.groupPhone?.trim();
        if (groupPhone && code) {
            const groupChatId = groupPhone.includes('@') ? groupPhone : groupPhone + '@g.us';
            const canSend = (account.sendVerificationCodesToGroup === true) || (!isAccountVerification);
            if (canSend) {
                const formattedCode = `🔐 *CÓDIGO DE VERIFICACIÓN NETFLIX*\n\n📌 *${code}*\n\n⏱️ Válido por pocos minutos.\n${link ? '🔗 El enlace de actualización será procesado automáticamente.' : ''}`;
                messageQueue.enqueue(groupChatId, formattedCode);
                logEntry.codeSentTo.push('group');
                console.log(`📤 Código ${code} enviado al grupo ${groupPhone} (envío activado)`);
            } else {
                console.log(`ℹ️ Código ${code} NO enviado al grupo (opción desactivada para verificación)`);
            }
        }

        return logEntry;
    }

    async syncAccount(accountEmail, messageQueue, retries = 2) {
        const accountCfg = this.getCurrentAccountConfig(accountEmail);
        if (!accountCfg || !accountCfg.password) {
            console.error(`No se encuentra la contraseña para ${accountEmail}`);
            return;
        }
        const account = { email: accountEmail, password: accountCfg.password };

        let attempt = 0;
        while (attempt < retries) {
            const client = new ImapFlow({
                host: 'imap.gmail.com',
                port: 993,
                secure: true,
                auth: { user: account.email, pass: account.password },
                logger: false,
                timeout: 20000
            });
            try {
                await client.connect();
                let lock = await client.getMailboxLock('INBOX');
                try {
                    const all = await client.search({ seen: false });
                    const processed = getProcessed();
                    const processedIds = new Set(processed.map(p => p.messageId));

                    for (const uid of all.slice(0, 10)) {
                        try {
                            const msg = await client.fetchOne(uid, { source: true, envelope: true });
                            const parsed = await simpleParser(msg.source);
                            const mid = parsed.messageId || uid;
                            if (processedIds.has(mid)) {
                                await client.messageFlagsAdd(uid, ['\\Seen']);
                                continue;
                            }
                            const logEntry = await this.processEmail(parsed, uid, mid, account.email, messageQueue);
                            if (logEntry) {
                                const currentLogs = getLogs();
                                saveLogs([logEntry, ...currentLogs]);
                                processed.push({ messageId: mid, uid, timestamp: Date.now() });
                                saveProcessed(processed);
                                this.emitUpdate();
                            }
                            await client.messageFlagsAdd(uid, ['\\Seen']);
                        } catch (err) {
                            console.error(`Error procesando correo ${uid}:`, err.message);
                        }
                    }
                } finally {
                    lock.release();
                }
                await client.logout();
                return;
            } catch (err) {
                console.error(`Error sincronizando cuenta ${account.email} (intento ${attempt+1}/${retries}):`, err.message);
                attempt++;
                if (attempt < retries) await sleep(5000 * attempt);
            }
        }
        console.error(`❌ No se pudo sincronizar ${account.email} después de ${retries} intentos.`);
    }

    async startIntervalForAccount(accountEmail, messageQueue, intervalSeconds) {
        if (this.timers.has(accountEmail)) {
            clearInterval(this.timers.get(accountEmail));
        }
        console.log(`⏱️ Iniciando intervalo para ${accountEmail} cada ${intervalSeconds}s`);
        const timer = setInterval(async () => {
            await this.syncAccount(accountEmail, messageQueue, 2);
        }, intervalSeconds * 1000);
        this.timers.set(accountEmail, timer);
        await this.syncAccount(accountEmail, messageQueue, 2);
    }

    async stopIntervalForAccount(email) {
        const timer = this.timers.get(email);
        if (timer) {
            clearInterval(timer);
            this.timers.delete(email);
        }
    }

    async refreshAccounts(messageQueue) {
        for (let email of this.timers.keys()) {
            await this.stopIntervalForAccount(email);
        }

        const config = getConfig();
        const ncfg = config.netflix || { intervalSeconds: 120, accounts: [] };
        const intervalSeconds = ncfg.intervalSeconds || 120;

        for (let account of ncfg.accounts) {
            if (account.email && account.password) {
                await this.startIntervalForAccount(account.email, messageQueue, intervalSeconds);
            }
        }
    }

    emitUpdate() {
        if (this.io) {
            this.io.emit('netflix_update', { logs: this.getUnviewedLogs() });
        }
    }

    getUnviewedLogs() {
        return getLogs().filter(l => !l.viewed);
    }

    markLogAsViewed(logId) {
        const logs = getLogs();
        const log = logs.find(l => l.id === logId);
        if (log) {
            log.viewed = true;
            log.viewedAt = Date.now();
            saveLogs(logs);
            return true;
        }
        return false;
    }

    deleteLog(logId) {
        let logs = getLogs();
        logs = logs.filter(l => l.id !== logId);
        saveLogs(logs);
    }

    cleanupExpiredViewedLogs() {
        const logs = getLogs();
        const now = Date.now();
        const freshLogs = logs.filter(l => {
            const age = now - new Date(l.timestamp).getTime();
            return age < 10 * 60 * 1000;
        });
        if (freshLogs.length < logs.length) {
            saveLogs(freshLogs);
            console.log(`🧹 Eliminados ${logs.length - freshLogs.length} logs por expiración (10 min)`);
            this.emitUpdate();
        }
    }

    cleanupOldLogs() {
        const logs = getLogs();
        const cutoff = Date.now() - 7 * 24 * 3600 * 1000;
        const freshLogs = logs.filter(l => new Date(l.timestamp).getTime() > cutoff);
        if (freshLogs.length < logs.length) {
            saveLogs(freshLogs);
            console.log(`🧹 Limpiados ${logs.length - freshLogs.length} logs antiguos de Netflix`);
        }
    }
}

module.exports = NetflixEngine;
NETFLIXEOF

# ----------------------------------------------------------------------
# 9. BACKEND (app.js) – SIN CONTACTOS, ESTABLE
# ----------------------------------------------------------------------
cat <<'APPEOF' > app.js
process.env.TZ = 'America/Santo_Domingo';

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
const NetflixEngine = require('./netflix-engine');

const TZ = 'America/Santo_Domingo';
const app = express();
app.set('trust proxy', 1);

const server = http.createServer(app);
const io = socketIo(server, {
    pingTimeout: 60000,
    pingInterval: 25000,
    transports: ['websocket', 'polling']
});

const DB_PATH = path.join(__dirname, 'data/database.json');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const MEDIA_PATH = path.join(__dirname, 'media');
const BACKUP_PATH = path.join(__dirname, 'backups');
const AUTH_PATH = path.join(__dirname, '.wwebjs_auth');

if (!fs.existsSync(DB_PATH)) {
    fs.writeFileSync(DB_PATH, JSON.stringify({
        training: [], reminders: [], excluded: [], learning: [],
        stats: { replied: 0, total: 0 }
    }));
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, file.fieldname === 'backup' ? BACKUP_PATH : MEDIA_PATH);
    },
    filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname)
});
const upload = multer({ storage });

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use('/media', express.static(MEDIA_PATH));

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
    }
}));

const getDB = () => JSON.parse(fs.readFileSync(DB_PATH));
const saveDB = (data) => fs.writeFileSync(DB_PATH, JSON.stringify(data, null, 2));

function nowRD() {
    return moment().tz(TZ);
}

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

class MessageQueue {
    constructor(intervalMs = 500) {
        this.queue = [];
        this.intervalMs = intervalMs;
        this.processing = false;
    }

    enqueue(chatId, message, options = {}) {
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
let messageQueue;
let netflixEngine;
let learningCleanupCron = null;

console.log('🕐 Hora del servidor:', new Date().toString());
console.log('🕐 Hora RD (moment):', nowRD().format('DD/MM/YYYY HH:mm:ss'));

io.on('connection', (socket) => {
    console.log('Cliente conectado al socket');
    socket.emit('connection_status', { connected: isConnected, status: botStatus });
    if (lastQRImage) socket.emit('qr_update', lastQRImage);

    setInterval(() => {
        if (messageQueue) socket.emit('queue_size', messageQueue.size());
    }, 2000);
    if (netflixEngine) socket.emit('netflix_update', { logs: netflixEngine.getUnviewedLogs() });
    
    socket.on('ping', () => socket.emit('pong'));
});

function setupLearningCleanup() {
    if (learningCleanupCron) learningCleanupCron.stop();
    const interval = getConfig().cleanupLearningInterval;
    let cronExpression = null;
    switch (interval) {
        case 'diario':
            cronExpression = '0 0 * * *';
            break;
        case 'semanal':
            cronExpression = '0 0 * * 0';
            break;
        case '3dias':
            cronExpression = '0 0 */3 * *';
            break;
        default:
            return;
    }
    learningCleanupCron = cron.schedule(cronExpression, () => {
        console.log('🧹 Limpiando aprendizaje antiguo...');
        const db = getDB();
        const oldCount = db.learning.length;
        db.learning = [];
        saveDB(db);
        io.emit('data_update', db);
        console.log(`🧹 Eliminados ${oldCount} mensajes de aprendizaje`);
    }, {
        scheduled: true,
        timezone: TZ
    });
}

function initBot() {
    const config = getConfig();
    messageQueue = new MessageQueue(config.queueInterval || 500);

    client = new Client({
        authStrategy: new LocalAuth({ dataPath: AUTH_PATH }),
        puppeteer: {
            executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/google-chrome-stable',
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu']
        }
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

        if (netflixEngine) {
            netflixEngine.refreshAccounts(messageQueue);
        }
    });

    client.on('authenticated', () => console.log('🔐 Autenticado'));

    client.on('auth_failure', (msg) => {
        console.error('❌ Auth failure:', msg);
        botStatus = "Error de autenticación";
        io.emit('status_update', botStatus);
        setTimeout(() => {
            console.log('Reintentando inicialización del bot...');
            initBot();
        }, 10000);
    });

    client.on('disconnected', (reason) => {
        botStatus = "Desconectado";
        isConnected = false;
        lastQR = null;
        lastQRImage = null;
        io.emit('status_update', botStatus);
        io.emit('connection_status', { connected: false, status: botStatus });
        io.emit('qr_clear');
        console.log('❌ Bot desconectado:', reason);
        setTimeout(() => {
            console.log('Intentando reconectar el bot...');
            initBot();
        }, 5000);
    });

    client.on('message', async (msg) => {
        try {
            if (msg.from.includes('@g.us') || msg.from === 'status@broadcast') return;
            if (!msg.body || msg.type === 'ptt' || msg.type === 'audio' || msg.type === 'voice') return;

            const db = getDB();
            const phone = msg.from.replace('@c.us', '');

            if (db.excluded.some(ex => phone.includes(ex.phone))) return;

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
                db.stats.replied++;
            } else {
                // Mensaje no reconocido → guardar en aprendizaje
                const msgData = {
                    text: msg.body,
                    from: phone,      // número sin @c.us
                    phone: phone,
                    date: nowRD().format('DD/MM HH:mm'),
                    hasMedia: msg.hasMedia,
                    type: msg.type
                };
                // Evitar duplicados exactos
                if (!db.learning.some(l => l.text === msg.body && l.phone === phone)) {
                    db.learning.push(msgData);
                }
            }

            db.stats.total++;
            saveDB(db);
            io.emit('data_update', db);
        } catch (e) {
            console.error('Error en mensaje:', e);
        }
    });

    client.initialize().catch(e => {
        console.error("Error al iniciar el cliente:", e);
        setTimeout(() => initBot(), 10000);
    });
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
    const now = moment().tz(TZ);
    const currentRD = now.format('YYYY-MM-DDTHH:mm');
    let changed = false;

    for (let i = db.reminders.length - 1; i >= 0; i--) {
        const rem = db.reminders[i];
        if (!rem.date) continue;
        const remMoment = moment.tz(rem.date, TZ);
        if (remMoment.isValid() && remMoment.format('YYYY-MM-DDTHH:mm') === currentRD) {
            console.log('🔔 Encolando recordatorio para', rem.name, '(' + rem.phone + ') -', currentRD);
            const chatId = rem.phone.includes('@') ? rem.phone : rem.phone + '@c.us';
            messageQueue.enqueue(chatId, rem.message);

            if (rem.freq === 'Una vez') {
                db.reminders.splice(i, 1);
            } else if (rem.freq === 'Diario') {
                rem.date = remMoment.add(1, 'days').format('YYYY-MM-DDTHH:mm');
            } else if (rem.freq === 'Semanal') {
                rem.date = remMoment.add(7, 'days').format('YYYY-MM-DDTHH:mm');
            } else if (rem.freq === 'Mensual') {
                rem.date = remMoment.add(1, 'months').format('YYYY-MM-DDTHH:mm');
            } else if (rem.freq === 'Anual') {
                rem.date = remMoment.add(1, 'years').format('YYYY-MM-DDTHH:mm');
            }
            changed = true;
        }
    }

    if (changed) {
        saveDB(db);
        io.emit('data_update', db);
    }
}, {
    scheduled: true,
    timezone: TZ
});

console.log('⏰ Recordatorios activos - verificando cada minuto en hora RD');

setInterval(() => {
    if (netflixEngine) {
        netflixEngine.cleanupExpiredViewedLogs();
        netflixEngine.cleanupOldLogs();
    }
    const processedFile = path.join(__dirname, 'data', 'netflix_processed.json');
    try {
        const processed = JSON.parse(fs.readFileSync(processedFile));
        const cutoff = Date.now() - 7 * 24 * 3600 * 1000;
        const fresh = processed.filter(p => p.timestamp > cutoff);
        if (fresh.length < processed.length) {
            fs.writeFileSync(processedFile, JSON.stringify(fresh, null, 2));
        }
    } catch (e) {}
}, 60000);

netflixEngine = new NetflixEngine(io);
initBot();

process.on('uncaughtException', (err) => {
    console.error('💥 Excepción no capturada:', err);
    setTimeout(() => process.exit(1), 2000);
});
process.on('unhandledRejection', (reason, promise) => {
    console.error('💥 Promesa rechazada no manejada:', reason);
});

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
        queueInterval: getConfig().queueInterval || 500,
        cleanupLearningInterval: getConfig().cleanupLearningInterval || 'off',
        queueSize: messageQueue ? messageQueue.size() : 0,
        serverTime: nowRD().format('DD/MM/YYYY HH:mm:ss'),
        timezone: TZ,
        netflixConfig: getConfig().netflix,
        netflixLogs: netflixEngine ? netflixEngine.getUnviewedLogs() : []
    });
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
    const db = getDB();
    const { id, key, response } = req.body;
    const trainData = {
        key, response,
        mediaPaths: req.files && req.files.length > 0 ? req.files.map(f => f.path) : [],
        mediaTypes: req.files && req.files.length > 0 ? req.files.map(f => f.mimetype) : []
    };
    if (id !== "" && id !== null && id !== undefined && id !== "undefined") {
        if (db.training[id] && db.training[id].mediaPaths && db.training[id].mediaPaths.length > 0) {
            db.training[id].mediaPaths.forEach(p => { if (fs.existsSync(p)) fs.unlinkSync(p); });
        }
        db.training[id] = trainData;
    } else {
        db.training.push(trainData);
    }

    if (key) {
        const index = db.learning.findIndex(l => l.text.toLowerCase().trim() === key.toLowerCase().trim());
        if (index !== -1) {
            db.learning.splice(index, 1);
        }
    }

    saveDB(db);
    io.emit('data_update', db);
    res.json({ ok: true });
});

app.delete('/api/train/:id', checkAuth, (req, res) => {
    const db = getDB();
    const item = db.training[req.params.id];
    if (item && item.mediaPaths && item.mediaPaths.length > 0) {
        item.mediaPaths.forEach(p => { if (fs.existsSync(p)) fs.unlinkSync(p); });
    }
    db.training.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
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
        const db = getDB();
        let cQ = '', cR = '', imported = 0;
        for (let line of lines) {
            line = line.trim();
            if (line.startsWith('#') || line === '') continue;
            if (line.startsWith('PREGUNTA:')) cQ = line.replace('PREGUNTA:', '').trim();
            else if (line.startsWith('RESPUESTA:')) {
                cR = line.replace('RESPUESTA:', '').trim().replace(/\\n/g, '\n');
            } else if (line === '---' && cQ && cR) {
                db.training.push({ key: cQ, response: cR, mediaPaths: [], mediaTypes: [] });
                imported++; cQ = ''; cR = '';
            }
        }
        if (cQ && cR) { db.training.push({ key: cQ, response: cR, mediaPaths: [], mediaTypes: [] }); imported++; }
        saveDB(db); io.emit('data_update', db); fs.unlinkSync(req.file.path);
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
    const db = getDB();
    const { id, name, phone, message, freq, date } = req.body;
    const cleanPhone = phone.replace('@c.us', '').replace('@g.us', '').replace(/\D/g, '');
    const data = { name, phone: cleanPhone, message, freq, date };

    console.log('📝 Recordatorio guardado:', name, '- Fecha:', date, '- Hora actual RD:', nowRD().format('YYYY-MM-DDTHH:mm'));

    if (id !== "" && id !== null && id !== undefined && id !== "undefined") db.reminders[id] = data;
    else db.reminders.push(data);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/reminders/:id', checkAuth, (req, res) => {
    const db = getDB(); db.reminders.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.post('/api/exclude', checkAuth, (req, res) => {
    const db = getDB();
    const cleanPhone = req.body.phone.replace('@c.us', '').replace(/\D/g, '');
    db.excluded.push({ name: req.body.name, phone: cleanPhone });
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/exclude/:id', checkAuth, (req, res) => {
    const db = getDB(); db.excluded.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/learning/:id', checkAuth, (req, res) => {
    const db = getDB(); db.learning.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/learning/all', checkAuth, (req, res) => {
    const db = getDB();
    db.learning = [];
    saveDB(db);
    io.emit('data_update', db);
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
    fc.backupPhone = req.body.backupPhone.replace('@c.us', '').replace(/\D/g, '');
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
    fc.queueInterval = parseInt(req.body.interval) || 500;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    if (messageQueue) {
        messageQueue.setInterval(fc.queueInterval);
    }
    io.emit('config_update', { queueInterval: fc.queueInterval });
    res.json({ ok: true });
});

app.post('/api/config/cleanup-learning', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.cleanupLearningInterval = req.body.interval;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    setupLearningCleanup();
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
        if (bc.database) { saveDB(bc.database); io.emit('data_update', bc.database); }
        if (bc.config) {
            const cc = getConfig();
            const nc = { ...bc.config, adminUser: cc.adminUser, adminPassword: cc.adminPassword, sessionSecret: cc.sessionSecret };
            fs.writeFileSync(CONFIG_PATH, JSON.stringify(nc, null, 2));
            setupLearningCleanup();
            if (netflixEngine) netflixEngine.refreshAccounts(messageQueue);
        }
        fs.unlinkSync(req.file.path);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

// Netflix API endpoints
app.post('/api/netflix/config', checkAuth, (req, res) => {
    try {
        const cfg = getConfig();
        cfg.netflix = {
            intervalSeconds: parseInt(req.body.intervalSeconds) || 120,
            accounts: req.body.accounts || []
        };
        fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
        if (netflixEngine) {
            netflixEngine.refreshAccounts(messageQueue);
        }
        res.json({ ok: true, message: 'Configuración guardada' });
    } catch (e) {
        res.status(500).json({ ok: false, message: e.message });
    }
});

app.get('/api/netflix/logs', checkAuth, (req, res) => {
    try {
        const logs = netflixEngine ? netflixEngine.getUnviewedLogs() : [];
        res.json({ ok: true, logs });
    } catch (e) {
        res.status(500).json({ ok: false, message: e.message });
    }
});

app.post('/api/netflix/logs/:id/view', checkAuth, (req, res) => {
    try {
        const success = netflixEngine ? netflixEngine.markLogAsViewed(req.params.id) : false;
        if (success && netflixEngine) netflixEngine.emitUpdate();
        res.json({ ok: success });
    } catch (e) {
        res.status(500).json({ ok: false, message: e.message });
    }
});

app.delete('/api/netflix/logs/:id', checkAuth, (req, res) => {
    try {
        if (netflixEngine) netflixEngine.deleteLog(req.params.id);
        if (netflixEngine) netflixEngine.emitUpdate();
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ ok: false, message: e.message });
    }
});

app.post('/api/netflix/process', checkAuth, async (req, res) => {
    try {
        if (netflixEngine) {
            await netflixEngine.refreshAccounts(messageQueue);
        }
        res.json({ ok: true, logs: netflixEngine ? netflixEngine.getUnviewedLogs() : [] });
    } catch (e) {
        res.status(500).json({ ok: false, message: e.message });
    }
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

        const db = getDB();
        db.stats.replied = 0;
        db.stats.total = 0;
        saveDB(db);

        io.emit('data_update', db);
        io.emit('connection_status', { connected: false, status: botStatus });
        io.emit('qr_clear');

        res.json({ ok: true });

        setTimeout(() => {
            initBot();
        }, 2000);
    } catch (e) { 
        console.error('Error en logout:', e);
        res.status(500).json({ ok: false, error: e.message }); 
    }
});

server.listen(config.port, '127.0.0.1', () => {
    console.log('🚀 GZMBOT ONLINE en puerto', config.port, '(solo local)');
    console.log('🕐 Hora actual RD:', nowRD().format('DD/MM/YYYY HH:mm:ss'));
    console.log('📅 Próximo backup: 12:00 AM hora RD');
    console.log('📺 Netflix Hogar Multi-cuenta: activo (intervalo cada '+getConfig().netflix.intervalSeconds+' segundos)');
    setupLearningCleanup();
});
APPEOF

# ----------------------------------------------------------------------
# 10. FRONTEND (index.html) – SIN MODAL DE CONTACTOS, OPTIMIZADO
# ----------------------------------------------------------------------
cat <<'HTMLEOF' > views/index.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GZMBOT | Enterprise</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="/socket.io/socket.io.js"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:ital,wght@0,100..900;1,100..900&display=swap" rel="stylesheet">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #0a0a0f; color: #f4f4f5; font-family: 'Inter', sans-serif; background-image: radial-gradient(circle at 30% 10%, rgba(37, 99, 235, 0.08) 0%, transparent 40%); }
        .glass { background: rgba(18,18,24,0.7); backdrop-filter: blur(16px); border: 1px solid rgba(255,255,255,0.03); box-shadow: 0 20px 40px -12px rgba(0,0,0,0.6); }
        .glass-card { background: rgba(24,24,32,0.6); backdrop-filter: blur(12px); border: 1px solid rgba(255,255,255,0.02); border-radius: 28px; transition: transform 0.2s ease, border-color 0.2s, box-shadow 0.3s; box-shadow: 0 8px 30px rgba(0,0,0,0.3); }
        .glass-card:hover { border-color: rgba(37,99,235,0.4); transform: translateY(-3px); box-shadow: 0 15px 35px -10px #2563eb40; }
        .sidebar-item { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-radius: 16px; color: #a1a1aa; transition: all 0.2s; cursor: pointer; font-weight: 500; margin-bottom: 4px; }
        .sidebar-item:hover { background: rgba(255,255,255,0.05); color: #fff; }
        .sidebar-item.active { background: linear-gradient(135deg, #2563eb, #1d4ed8); color: #fff; box-shadow: 0 8px 20px -6px #2563eb; }
        .page { display: none; animation: fadeIn 0.3s ease; }
        .page.active { display: block; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
        input, select, textarea { background: #0f0f13 !important; border: 1px solid #27272a !important; color: #fff !important; padding: 14px 18px !important; border-radius: 20px !important; outline: none; width: 100%; font-size: 15px; transition: border 0.2s, box-shadow 0.2s; }
        input:focus, textarea:focus, select:focus { border-color: #2563eb !important; box-shadow: 0 0 0 3px rgba(37,99,235,0.2); }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-thumb { background: #3f3f46; border-radius: 10px; }
        .stat-value { font-size: 2.5rem; font-weight: 800; line-height: 1; background: linear-gradient(to right, #e5e7eb, #a5b4fc); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .badge { padding: 4px 12px; border-radius: 40px; font-size: 11px; font-weight: 600; letter-spacing: 0.4px; text-transform: uppercase; background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.05); }
        .reminder-item, .learning-item { background: rgba(39,39,45,0.4); border-radius: 20px; padding: 16px; border: 1px solid rgba(255,255,255,0.02); margin-bottom: 8px; transition: background 0.2s; }
        .reminder-item:hover, .learning-item:hover { background: rgba(55,55,65,0.5); }
        .aluminum-title { color: #f0f0f3; font-weight: 700; letter-spacing: -0.02em; }
        .aluminum-logo { background: linear-gradient(135deg, #ffffff, #cbd5e1); -webkit-background-clip: text; -webkit-text-fill-color: transparent; font-weight: 800; letter-spacing: -0.03em; }
        .media-preview { max-width: 100px; max-height: 100px; border-radius: 16px; margin: 4px; object-fit: cover; border: 1px solid #2a2a2e; }
        .media-preview-container { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 12px; }
        .media-item { position: relative; }
        .media-remove { position: absolute; top: -8px; right: -8px; background: #ef4444; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 14px; font-weight: bold; box-shadow: 0 4px 8px rgba(0,0,0,0.3); }
        .preserve-whitespace { white-space: pre-wrap; word-break: break-word; }

        .toast { position: fixed; bottom: 24px; right: 24px; background: #23232b; border-left: 5px solid #2563eb; padding: 14px 24px; border-radius: 40px; box-shadow: 0 20px 35px -8px black; transform: translateY(120px); opacity: 0; transition: all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1); z-index: 2000; color: #fff; font-weight: 500; display: flex; align-items: center; gap: 12px; backdrop-filter: blur(8px); }
        .toast.show { transform: translateY(0); opacity: 1; }

        .clock-modern { display: flex; flex-direction: column; align-items: flex-end; line-height: 1.2; }
        .clock-time { font-size: clamp(2rem, 5vw, 3.2rem); font-weight: 800; background: linear-gradient(to right, #2563eb, #60a5fa); -webkit-background-clip: text; -webkit-text-fill-color: transparent; letter-spacing: -0.02em; }
        .clock-date { font-size: clamp(0.85rem, 2vw, 1.1rem); color: #a1a1aa; font-weight: 400; text-transform: capitalize; }
        #qr-wrapper { display: flex; justify-content: center; align-items: center; }
        #qr-container { display: flex; justify-content: center; align-items: center; background: white; border-radius: 32px; padding: 20px; box-shadow: 0 20px 40px -10px rgba(0,0,0,0.5), 0 0 0 2px rgba(37,99,235,0.2); }
        #qr-img { display: flex; justify-content: center; align-items: center; width: 240px; height: 240px; }
        #qr-img img { width: 100%; height: 100%; object-fit: contain; border-radius: 16px; }
        #btn-logout-wa { transition: all 0.3s ease; }
        .bot-logo { background: linear-gradient(145deg, #2563eb, #1e40af); box-shadow: 0 10px 20px -5px #2563eb80, 0 0 0 2px rgba(255,255,255,0.05) inset; border-radius: 18px; width: 48px; height: 48px; display: flex; align-items: center; justify-content: center; }
        .bot-logo i { color: white; width: 28px; height: 28px; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3)); }
        input[type=range] { -webkit-appearance: none; height: 8px; border-radius: 10px; background: #2a2a30; }
        input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 22px; height: 22px; border-radius: 50%; cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,0.3); }
        #response-delay::-webkit-slider-thumb { background: #2563eb; border: 2px solid #ffffff30; }
        #queue-interval::-webkit-slider-thumb { background: #f97316; border: 2px solid #ffffff30; }
        .config-card { background: rgba(24,24,32,0.7); backdrop-filter: blur(12px); border-radius: 28px; padding: 28px; border: 1px solid rgba(255,255,255,0.03); }
        .config-divider { height: 1px; background: rgba(255,255,255,0.05); margin: 24px 0; }
        .btn-save-config { background: #f97316; box-shadow: 0 10px 20px -8px #f97316; transition: all 0.2s ease; }
        .btn-save-config:hover { background: #ea580c; transform: translateY(-2px); box-shadow: 0 15px 25px -10px #f97316; }
        .btn-save-config:active { transform: translateY(0); }
        .log-entry { background: rgba(30,30,36,0.5); border-radius: 20px; padding: 20px; border: 1px solid rgba(255,255,255,0.03); margin-bottom: 12px; }
        .log-code { font-family: 'Courier New', monospace; background: linear-gradient(135deg, #2563eb20, #1e40af20); padding: 6px 16px; border-radius: 40px; color: #60a5fa; letter-spacing: 2px; font-weight: 700; font-size: 1.1rem; border: 1px solid #2563eb40; }
        .netflix-icon { background: linear-gradient(135deg, #E50914, #b20710); border-radius: 16px; padding: 12px; width: 56px; height: 56px; display: flex; align-items: center; justify-content: center; }
        .netflix-icon i { color: white; width: 32px; height: 32px; }
        .netflix-page-header { display: flex; align-items: center; gap: 16px; margin-bottom: 24px; }
        .interaction-step { font-size: 12px; color: #a1a1aa; margin-top: 4px; border-left: 2px solid #2563eb; padding-left: 8px; }
        .media-type-btn { padding: 10px 20px; background: #0f0f13; border: 1px solid #27272a; border-radius: 14px; cursor: pointer; transition: all 0.3s; color: #fff; font-size: 14px; font-weight: 500; display: inline-flex; align-items: center; gap: 8px; }
        .media-type-btn.active { background: #2563eb; border-color: #2563eb; box-shadow: 0 4px 12px #2563eb50; }
        .media-type-btn i { width: 18px; height: 18px; }
    </style>
</head>
<body class="flex h-screen overflow-hidden">

    <div id="toast" class="toast">
        <i data-lucide="check-circle" class="text-green-500 w-5 h-5"></i>
        <span id="toast-message">Guardado correctamente</span>
    </div>

    <!-- SIDEBAR -->
    <aside id="sidebar" class="fixed inset-y-0 left-0 z-50 w-72 glass border-r border-white/5 -translate-x-full lg:translate-x-0 lg:static transition-transform duration-300 flex flex-col p-6 overflow-y-auto">
        <div class="flex items-center gap-3 mb-10 px-2">
            <div class="bot-logo">
                <i data-lucide="bot" class="w-7 h-7"></i>
            </div>
            <span class="text-2xl font-extrabold tracking-tight aluminum-logo">GZMBOT</span>
        </div>
        <nav class="space-y-1 flex-1">
            <div onclick="nav('dash'); if(window.innerWidth<1024) toggleSidebar()" id="n-dash" class="sidebar-item active"><i data-lucide="layout-dashboard" class="w-5 h-5"></i><span>Dashboard</span></div>
            <div onclick="nav('conn'); if(window.innerWidth<1024) toggleSidebar()" id="n-conn" class="sidebar-item"><i data-lucide="qr-code" class="w-5 h-5"></i><span>Conexión</span></div>
            <div onclick="nav('train'); if(window.innerWidth<1024) toggleSidebar()" id="n-train" class="sidebar-item"><i data-lucide="message-square" class="w-5 h-5"></i><span>Respuestas</span></div>
            <div onclick="nav('learn'); if(window.innerWidth<1024) toggleSidebar()" id="n-learn" class="sidebar-item"><i data-lucide="brain" class="w-5 h-5"></i><span>Aprender</span></div>
            <div onclick="nav('rem'); if(window.innerWidth<1024) toggleSidebar()" id="n-rem" class="sidebar-item"><i data-lucide="bell" class="w-5 h-5"></i><span>Recordatorios</span></div>
            <div onclick="nav('excl'); if(window.innerWidth<1024) toggleSidebar()" id="n-excl" class="sidebar-item"><i data-lucide="shield-off" class="w-5 h-5"></i><span>Excluidos</span></div>
            <div onclick="nav('netflix'); if(window.innerWidth<1024) toggleSidebar()" id="n-netflix" class="sidebar-item"><i data-lucide="tv" class="w-5 h-5"></i><span>Hogar Netflix</span></div>
            <div onclick="nav('config'); if(window.innerWidth<1024) toggleSidebar()" id="n-config" class="sidebar-item"><i data-lucide="settings" class="w-5 h-5"></i><span>Ajustes</span></div>
        </nav>
        <button onclick="location.href='/login'" class="sidebar-item text-red-400 hover:bg-red-500/10 mt-6">
            <i data-lucide="log-out" class="w-5 h-5"></i><span>Salir</span>
        </button>
    </aside>

    <!-- MAIN CONTENT -->
    <main id="main-content" class="flex-1 flex flex-col min-w-0 overflow-hidden" onclick="if(window.innerWidth<1024 && !document.getElementById('sidebar').classList.contains('-translate-x-full')) toggleSidebar()">
        <header class="lg:hidden p-5 glass border-b border-white/5 flex justify-between items-center flex-shrink-0 relative z-40">
            <span class="font-bold text-xl aluminum-logo">GZMBOT</span>
            <button onclick="toggleSidebar(); event.stopPropagation()" class="p-2.5 text-zinc-400 hover:text-white hover:bg-white/5 rounded-xl transition">
                <i data-lucide="menu" class="w-6 h-6"></i>
            </button>
        </header>

        <div class="flex-1 overflow-y-auto p-5 sm:p-7 lg:p-9 space-y-7">

            <!-- DASHBOARD -->
            <div id="p-dash" class="page active">
                <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-5 mb-8">
                    <h1 class="text-4xl font-bold aluminum-title">Panel de Control</h1>
                    <div id="server-clock" class="clock-modern">
                        <div class="clock-time" id="clock-time">--:--:-- --</div>
                        <div class="clock-date" id="clock-date">cargando...</div>
                    </div>
                    <div class="px-5 py-3 glass-card flex items-center gap-3">
                        <div id="dot" class="w-3 h-3 rounded-full bg-red-500 animate-pulse"></div>
                        <span id="bot-status" class="text-xs font-semibold uppercase tracking-wider text-zinc-300">Desconectado</span>
                    </div>
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 mb-10">
                    <div class="glass-card p-7 flex items-center gap-5">
                        <div class="w-16 h-16 rounded-2xl bg-blue-500/20 flex items-center justify-center">
                            <i data-lucide="message-circle" class="w-8 h-8 text-blue-400"></i>
                        </div>
                        <div>
                            <p class="text-zinc-400 text-sm font-medium mb-1">Respondidas</p>
                            <h2 id="s-replied" class="stat-value">0</h2>
                        </div>
                    </div>
                    <div class="glass-card p-7 flex items-center gap-5">
                        <div class="w-16 h-16 rounded-2xl bg-blue-500/20 flex items-center justify-center">
                            <i data-lucide="users" class="w-8 h-8 text-blue-400"></i>
                        </div>
                        <div>
                            <p class="text-zinc-400 text-sm font-medium mb-1">Total mensajes</p>
                            <h2 id="s-total" class="stat-value">0</h2>
                        </div>
                    </div>
                </div>

                <div class="glass-card p-7 mb-10">
                    <div class="flex items-center gap-3 mb-5">
                        <i data-lucide="bell" class="w-6 h-6 text-emerald-400"></i>
                        <h3 class="font-semibold text-xl aluminum-title">Recordatorios de hoy</h3>
                        <span class="badge bg-emerald-500/10 text-emerald-400 ml-auto">HOY</span>
                    </div>
                    <div id="today-reminders-list" class="space-y-3">
                        <div class="text-zinc-500 text-sm py-5 text-center">Cargando...</div>
                    </div>
                    <button onclick="nav('rem')" class="mt-4 text-sm text-blue-400 hover:text-blue-300 transition flex items-center gap-1 font-medium">
                        Ver todos <i data-lucide="arrow-right" class="w-4 h-4"></i>
                    </button>
                </div>

                <div class="glass-card p-7">
                    <div class="flex items-center gap-3 mb-5">
                        <i data-lucide="brain" class="w-6 h-6 text-amber-400"></i>
                        <h3 class="font-semibold text-xl aluminum-title">Últimos mensajes sin respuesta</h3>
                    </div>
                    <div id="recent-learning-list" class="space-y-3 max-h-80 overflow-y-auto pr-2">
                        <div class="text-zinc-500 text-sm py-5 text-center">No hay datos</div>
                    </div>
                    <button onclick="nav('learn')" class="mt-4 text-sm text-blue-400 hover:text-blue-300 transition flex items-center gap-1 font-medium">
                        Ir a aprender <i data-lucide="arrow-right" class="w-4 h-4"></i>
                    </button>
                </div>
            </div>

            <!-- CONEXIÓN -->
            <div id="p-conn" class="page">
                <h2 class="text-3xl font-bold aluminum-title mb-6">Conexión WhatsApp</h2>
                <div class="max-w-lg mx-auto glass-card p-10 text-center">
                    <div id="qr-wrapper" class="mb-7">
                        <div id="qr-container" class="inline-block">
                            <div id="qr-img" class="flex items-center justify-center">
                                <span class="text-sm text-gray-500">Esperando código QR...</span>
                            </div>
                        </div>
                    </div>
                    <div id="connected-container" class="hidden mb-7">
                        <div class="w-28 h-28 bg-green-500/20 rounded-full flex items-center justify-center mx-auto mb-5">
                            <i data-lucide="check-circle" class="w-14 h-14 text-green-500"></i>
                        </div>
                        <h2 class="text-2xl font-bold text-green-500 mb-2">WhatsApp Vinculado</h2>
                        <p class="text-zinc-400">El bot está conectado y funcionando.</p>
                    </div>
                    <h2 class="text-2xl font-bold aluminum-title mb-2">Escanear código QR</h2>
                    <p class="text-zinc-400 text-sm mb-7">Usa WhatsApp para vincular el bot.</p>
                    <button id="btn-logout-wa" onclick="logoutWA()" class="hidden w-full py-4 bg-red-500/10 text-red-500 rounded-2xl font-bold hover:bg-red-500 hover:text-white transition">
                        <i data-lucide="unlink" class="inline w-4 h-4 mr-2"></i>DESVINCULAR
                    </button>
                </div>
            </div>

            <!-- RESPUESTAS -->
            <div id="p-train" class="page">
                <h2 class="text-3xl font-bold aluminum-title mb-5">Gestión de Respuestas</h2>
                <div class="mb-5 flex gap-3 flex-wrap">
                    <button onclick="downloadTemplate()" class="px-5 py-3 bg-purple-600 rounded-xl font-bold flex items-center gap-2 hover:bg-purple-700 transition text-sm shadow-lg">
                        <i data-lucide="download" class="w-4 h-4"></i>Plantilla
                    </button>
                    <button onclick="document.getElementById('import-file').click()" class="px-5 py-3 bg-green-600 rounded-xl font-bold flex items-center gap-2 hover:bg-green-700 transition text-sm shadow-lg">
                        <i data-lucide="upload" class="w-4 h-4"></i>Importar
                    </button>
                    <button onclick="exportTraining()" class="px-5 py-3 bg-orange-600 rounded-xl font-bold flex items-center gap-2 hover:bg-orange-700 transition text-sm shadow-lg">
                        <i data-lucide="file-text" class="w-4 h-4"></i>Exportar
                    </button>
                    <input type="file" id="import-file" accept=".txt" class="hidden" onchange="importTraining(this)">
                </div>
                <div class="grid lg:grid-cols-3 gap-5 sm:gap-8">
                    <div class="lg:col-span-1 glass p-6 sm:p-7 rounded-3xl h-fit">
                        <h3 class="font-bold mb-5 flex items-center gap-2 aluminum-title text-lg"><i data-lucide="plus-circle" class="text-blue-500 w-5 h-5"></i> Nueva Regla</h3>
                        <form id="train-form" enctype="multipart/form-data" onsubmit="saveTrain(event)">
                            <input type="hidden" id="t-id">
                            <input type="text" id="t-key" placeholder="Cuando digan..." class="mb-4" required>
                            <textarea id="t-res" placeholder="Responder..." class="h-28 mb-5" required></textarea>
                            <div class="mb-5">
                                <label class="block text-sm text-zinc-400 mb-2">Tipo de respuesta:</label>
                                <div class="flex gap-3">
                                    <button type="button" onclick="setMediaType('text')" id="mt-text" class="media-type-btn active">
                                        <i data-lucide="type"></i> Texto
                                    </button>
                                    <button type="button" onclick="setMediaType('multimedia')" id="mt-multimedia" class="media-type-btn">
                                        <i data-lucide="image"></i> Multimedia
                                    </button>
                                </div>
                            </div>
                            <div id="media-upload" class="hidden mb-5">
                                <label class="block text-sm text-zinc-400 mb-2">Archivos (máx 10):</label>
                                <input type="file" id="t-media" accept="image/*,video/*" multiple>
                                <div id="media-preview" class="media-preview-container"></div>
                            </div>
                            <button type="submit" class="w-full py-4 bg-blue-600 rounded-2xl font-bold hover:bg-blue-700 transition shadow-lg">Guardar</button>
                        </form>
                    </div>
                    <div id="l-train" class="lg:col-span-2 space-y-3"></div>
                </div>
            </div>

            <!-- APRENDER -->
            <div id="p-learn" class="page">
                <div class="flex justify-between items-center mb-4">
                    <h2 class="text-3xl font-bold aluminum-title">Bandeja de Aprendizaje</h2>
                    <button onclick="clearAllLearning()" class="bg-red-600 hover:bg-red-700 text-white px-5 py-2 rounded-xl flex items-center gap-2 transition shadow-md">
                        <i data-lucide="trash-2" class="w-4 h-4"></i> Eliminar todo
                    </button>
                </div>
                <p class="text-zinc-400 text-sm mb-5">Conversaciones que el bot no supo responder</p>
                <div id="l-learn" class="space-y-3"></div>
            </div>

            <!-- RECORDATORIOS -->
            <div id="p-rem" class="page">
                <h2 class="text-3xl font-bold aluminum-title mb-5">Recordatorios</h2>
                <div class="glass p-6 sm:p-9 rounded-3xl mb-8">
                    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                        <h3 class="font-bold text-xl aluminum-title">Programar Recordatorio</h3>
                        <div class="clock-modern">
                            <div class="clock-time" id="rem-clock-time">--:--:-- --</div>
                            <div class="clock-date" id="rem-clock-date">cargando...</div>
                        </div>
                    </div>
                    <p class="text-xs text-zinc-500 mb-5">⏰ Hora República Dominicana (UTC-4)</p>
                    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                        <input type="hidden" id="r-id">
                        <input type="text" id="r-name" placeholder="Nombre">
                        <input type="text" id="r-phone" placeholder="Número (ej: 18091234567)">
                        <textarea id="r-msg" placeholder="Mensaje" rows="3" class="sm:col-span-2 lg:col-span-2 resize-none"></textarea>
                        <select id="r-freq"><option>Una vez</option><option>Diario</option><option>Semanal</option><option>Mensual</option><option>Anual</option></select>
                        <input type="datetime-local" id="r-date">
                    </div>
                    <button onclick="saveRem()" class="mt-6 w-full sm:w-auto px-10 py-4 bg-emerald-600 rounded-2xl font-bold hover:bg-emerald-700 transition shadow-lg">Programar</button>
                </div>
                <div id="l-rem" class="grid grid-cols-1 md:grid-cols-2 gap-5"></div>
            </div>

            <!-- EXCLUIDOS -->
            <div id="p-excl" class="page">
                <h2 class="text-3xl font-bold aluminum-title mb-5">Números Excluidos</h2>
                <div class="w-full max-w-2xl mx-auto glass p-6 sm:p-9 rounded-3xl">
                    <div class="flex flex-col sm:flex-row gap-3">
                        <input type="text" id="e-name" placeholder="Nombre" class="flex-1">
                        <input type="text" id="e-phone" placeholder="Número" class="flex-1">
                        <button onclick="saveExcl()" class="bg-white text-black px-7 py-3.5 font-bold rounded-xl hover:bg-zinc-200 transition whitespace-nowrap">Añadir</button>
                    </div>
                    <div id="l-excl" class="mt-7 space-y-2"></div>
                </div>
            </div>

            <!-- NETFLIX HOGAR -->
            <div id="p-netflix" class="page">
                <div class="netflix-page-header">
                    <div class="netflix-icon"><i data-lucide="tv" class="w-8 h-8"></i></div>
                    <h2 class="text-4xl font-bold aluminum-title">Hogar Netflix</h2>
                </div>
                <div class="flex flex-col lg:flex-row gap-5 h-full" style="min-height:70vh;">
                    <div class="lg:w-96 flex-shrink-0 glass rounded-3xl p-5 flex flex-col">
                        <div class="mb-5">
                            <div class="flex justify-between items-center mb-3">
                                <h3 class="font-semibold text-lg">Cuentas de Gmail</h3>
                                <button onclick="addNetflixAccount()" class="text-sm bg-blue-600 px-4 py-2 rounded-xl hover:bg-blue-700 transition">+ Agregar</button>
                            </div>
                            <div id="netflix-accounts-list" class="space-y-4 max-h-96 overflow-y-auto pr-2"></div>
                        </div>
                        <div class="mt-auto pt-4 border-t border-white/5">
                            <div class="mb-4">
                                <label class="text-sm text-zinc-400 block mb-1">Intervalo de sincronización (segundos)</label>
                                <input type="number" id="netflix-interval-seconds" min="30" max="3600" step="10" value="120" class="w-full">
                            </div>
                            <p class="text-xs text-zinc-500 mb-3">📡 Las cuentas se revisan cada X segundos.<br>Los códigos expiran a los 10 minutos.</p>
                            <button onclick="saveNetflixConfig()" class="w-full py-3 bg-red-600 hover:bg-red-700 rounded-xl font-bold text-white transition">Guardar configuración</button>
                        </div>
                    </div>
                    <div class="flex-1 flex flex-col min-w-0">
                        <div class="glass rounded-3xl p-6 flex-1 overflow-y-auto" style="max-height:70vh;" id="netflix-logs-panel">
                            <div class="flex justify-between items-center mb-6">
                                <h3 class="text-xl font-bold aluminum-title flex items-center gap-2"><i data-lucide="list" class="w-5 h-5 text-blue-400"></i> Historial de actividad</h3>
                                <span class="text-sm text-zinc-500" id="netflix-log-count">0 códigos pendientes</span>
                            </div>
                            <div id="netflix-logs-container" class="space-y-3">
                                <div class="text-zinc-500 text-center py-12"><i data-lucide="tv" class="w-16 h-16 mx-auto mb-4 text-zinc-600"></i><p class="text-lg">Sin actividad reciente</p></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- AJUSTES -->
            <div id="p-config" class="page">
                <h2 class="text-3xl font-bold aluminum-title mb-5">Configuración</h2>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-5 sm:gap-7 max-w-5xl mx-auto">
                    <div class="config-card">
                        <h2 class="text-xl sm:text-2xl font-bold aluminum-title mb-6">Credenciales de Acceso</h2>
                        <input type="text" id="conf-user" placeholder="Nuevo Usuario" class="mb-4">
                        <input type="password" id="conf-pass" placeholder="Nueva Contraseña" class="mb-7">
                        <button onclick="saveCredentials()" class="w-full py-4 bg-blue-600 rounded-2xl font-bold hover:bg-blue-700 transition shadow-lg">Actualizar</button>
                    </div>
                    <div class="config-card">
                        <h2 class="text-xl sm:text-2xl font-bold aluminum-title mb-5">Copias de Seguridad</h2>
                        <div class="mb-6">
                            <p class="text-xs sm:text-sm text-zinc-400 mb-2">Número para backups:</p>
                            <div class="flex gap-2">
                                <input type="text" id="conf-backup-phone" placeholder="Ej: 18091234567" class="flex-1">
                                <button onclick="saveBackupPhone()" class="px-5 py-3.5 bg-emerald-600 rounded-xl font-bold hover:bg-emerald-700 transition flex items-center gap-1 text-sm whitespace-nowrap">
                                    <i data-lucide="save" class="w-4 h-4"></i> Guardar
                                </button>
                            </div>
                        </div>
                        <div class="space-y-3">
                            <button onclick="downloadBackup()" class="w-full py-4 bg-green-600 rounded-xl font-bold flex items-center justify-center gap-2 hover:bg-green-700 transition text-sm shadow-lg">
                                <i data-lucide="download" class="w-4 h-4"></i>Descargar Backup
                            </button>
                            <button onclick="sendBackupManually()" class="w-full py-4 bg-blue-600 rounded-xl font-bold flex items-center justify-center gap-2 hover:bg-blue-700 transition text-sm shadow-lg">
                                <i data-lucide="send" class="w-4 h-4"></i>Enviar a WhatsApp
                            </button>
                            <button onclick="document.getElementById('restore-file').click()" class="w-full py-4 bg-orange-600 rounded-xl font-bold flex items-center justify-center gap-2 hover:bg-orange-700 transition text-sm shadow-lg">
                                <i data-lucide="upload" class="w-4 h-4"></i>Restaurar Backup
                            </button>
                            <input type="file" id="restore-file" accept=".json" class="hidden" onchange="restoreBackup(this)">
                        </div>
                        <p class="text-xs text-zinc-500 mt-5">💡 Backup diario 12:00 AM hora RD.</p>
                    </div>
                    <div class="config-card">
                        <h2 class="text-xl font-bold aluminum-title mb-4">Limpieza automática de aprendizaje</h2>
                        <select id="cleanup-learning-interval" class="w-full mb-4">
                            <option value="off">Desactivado</option>
                            <option value="diario">Diario (medianoche)</option>
                            <option value="semanal">Semanal (domingo)</option>
                            <option value="3dias">Cada 3 días</option>
                        </select>
                        <button onclick="saveCleanupLearning()" class="w-full py-3 bg-purple-600 rounded-xl font-bold hover:bg-purple-700 transition">Guardar</button>
                    </div>
                    <div class="config-card md:col-span-2">
                        <h2 class="text-xl sm:text-2xl font-bold aluminum-title mb-6">Configuración de Envío</h2>
                        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                            <div>
                                <div class="flex items-center gap-2 mb-2">
                                    <i data-lucide="clock" class="w-5 h-5 text-blue-400"></i>
                                    <span class="font-medium text-zinc-300">Tiempo de espera</span>
                                </div>
                                <p class="text-xs text-zinc-500 mb-4">Segundos antes de responder</p>
                                <div class="flex items-center gap-4">
                                    <input type="range" id="response-delay" min="0" max="10" step="0.5" value="0" class="flex-1">
                                    <span id="delay-value" class="text-lg font-mono text-blue-400 min-w-[60px]">0.0 s</span>
                                </div>
                            </div>
                            <div>
                                <div class="flex items-center gap-2 mb-2">
                                    <i data-lucide="layers" class="w-5 h-5 text-orange-400"></i>
                                    <span class="font-medium text-zinc-300">Intervalo entre mensajes</span>
                                </div>
                                <p class="text-xs text-zinc-500 mb-4">Milisegundos (ms)</p>
                                <div class="flex items-center gap-4">
                                    <input type="range" id="queue-interval" min="100" max="10000" step="100" value="500" class="flex-1">
                                    <span id="interval-value" class="text-lg font-mono text-orange-400 min-w-[70px]">500 ms</span>
                                </div>
                                <div class="mt-3 text-sm text-zinc-500">
                                    Mensajes en cola: <span id="queue-size" class="font-bold text-orange-400">0</span>
                                </div>
                            </div>
                        </div>
                        <div class="config-divider"></div>
                        <div class="flex justify-end">
                            <button onclick="saveConfiguracionEnvio()" class="btn-save-config px-8 py-4 rounded-xl font-bold text-white flex items-center gap-2 transition shadow-lg">
                                <i data-lucide="save" class="w-5 h-5"></i>
                                Guardar configuración
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </main>

    <script>
        const socket = io({
            transports: ['websocket', 'polling'],
            reconnection: true,
            reconnectionAttempts: Infinity,
            reconnectionDelay: 1000,
            reconnectionDelayMax: 5000
        });
        let db = { training:[], learning:[], reminders:[], excluded:[], stats:{ replied:0, total:0 }, backupPhone:'', responseDelay:0, queueInterval:500, queueSize:0, cleanupLearningInterval:'off' };
        let currentMediaType = 'text';
        let selectedFiles = [];
        let netflixLogs = [];
        let netflixConfig = { intervalSeconds: 120, accounts: [] };

        setInterval(() => { socket.emit('ping'); }, 25000);

        function showToast(message, isError = false) {
            const toast = document.getElementById('toast');
            const msgSpan = document.getElementById('toast-message');
            msgSpan.textContent = message;
            toast.style.borderLeftColor = isError ? '#ef4444' : '#2563eb';
            toast.classList.add('show');
            setTimeout(() => toast.classList.remove('show'), 3000);
        }

        function toggleSidebar() {
            document.getElementById('sidebar').classList.toggle('-translate-x-full');
        }

        function nav(id) {
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.sidebar-item').forEach(i => i.classList.remove('active'));
            document.getElementById('p-'+id).classList.add('active');
            document.getElementById('n-'+id).classList.add('active');
            if (id === 'netflix') renderNetflixLogs();
            lucide.createIcons();
        }

        function updateClock() {
            const now = new Date();
            const optionsTime = { timeZone: 'America/Santo_Domingo', hour12: true, hour: '2-digit', minute: '2-digit', second: '2-digit' };
            const timeStr = now.toLocaleString('en-US', optionsTime);
            const optionsDate = { timeZone: 'America/Santo_Domingo', weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' };
            const dateStr = now.toLocaleDateString('es-ES', optionsDate);
            document.getElementById('clock-time').textContent = timeStr;
            document.getElementById('clock-date').textContent = dateStr;
            const remTime = document.getElementById('rem-clock-time');
            const remDate = document.getElementById('rem-clock-date');
            if (remTime) remTime.textContent = timeStr;
            if (remDate) remDate.textContent = dateStr;
        }
        setInterval(updateClock, 1000);
        updateClock();

        socket.on('queue_size', size => {
            document.getElementById('queue-size').textContent = size;
        });

        socket.on('connection_status', data => {
            const qrWrapper = document.getElementById('qr-wrapper');
            const connectedContainer = document.getElementById('connected-container');
            const logoutBtn = document.getElementById('btn-logout-wa');
            const botStatusSpan = document.getElementById('bot-status');
            const dot = document.getElementById('dot');

            if (data.connected) {
                qrWrapper.style.display = 'none';
                connectedContainer.style.display = 'block';
                logoutBtn.style.display = 'block';
                clearQR();
                botStatusSpan.innerText = 'Conectado';
                dot.className = 'w-3 h-3 rounded-full bg-green-500';
            } else {
                qrWrapper.style.display = 'flex';
                connectedContainer.style.display = 'none';
                logoutBtn.style.display = 'none';
                botStatusSpan.innerText = data.status || 'Desconectado';
                dot.className = 'w-3 h-3 rounded-full bg-red-500 animate-pulse';
            }
        });

        socket.on('netflix_update', data => {
            netflixLogs = data.logs;
            renderNetflixLogs();
            document.getElementById('netflix-log-count').textContent = netflixLogs.length + ' códigos pendientes';
        });

        function setMediaType(type) {
            currentMediaType = type;
            document.querySelectorAll('.media-type-btn').forEach(b => b.classList.remove('active'));
            if (type === 'text') {
                document.getElementById('mt-text').classList.add('active');
                document.getElementById('media-upload').classList.add('hidden');
                selectedFiles = [];
            } else {
                document.getElementById('mt-multimedia').classList.add('active');
                document.getElementById('media-upload').classList.remove('hidden');
                document.getElementById('t-media').accept = 'image/*,video/*';
            }
            lucide.createIcons();
        }

        document.getElementById('t-media')?.addEventListener('change', function(e) {
            const files = Array.from(e.target.files);
            if (files.length > 10) { alert('Máximo 10'); return; }
            selectedFiles = files;
            const preview = document.getElementById('media-preview');
            preview.innerHTML = '';
            files.forEach((file, index) => {
                const reader = new FileReader();
                reader.onload = function(ev) {
                    const div = document.createElement('div');
                    div.className = 'media-item';
                    if (file.type.startsWith('image/')) {
                        div.innerHTML = '<img src="'+ev.target.result+'" class="media-preview"><div class="media-remove" onclick="removeMediaFile('+index+')">×</div>';
                    } else {
                        div.innerHTML = '<video src="'+ev.target.result+'" class="media-preview" controls></video><div class="media-remove" onclick="removeMediaFile('+index+')">×</div>';
                    }
                    preview.appendChild(div);
                };
                reader.readAsDataURL(file);
            });
        });

        function removeMediaFile(index) {
            selectedFiles.splice(index, 1);
            const dt = new DataTransfer();
            selectedFiles.forEach(file => dt.items.add(file));
            document.getElementById('t-media').files = dt.files;
            document.getElementById('t-media').dispatchEvent(new Event('change'));
        }

        function showQR(url) {
            const qrImg = document.getElementById('qr-img');
            if (qrImg) qrImg.innerHTML = '<img src="'+url+'" class="w-full">';
        }

        function clearQR() {
            const qrImg = document.getElementById('qr-img');
            if (qrImg) qrImg.innerHTML = '<span class="text-sm text-gray-500">Esperando código QR...</span>';
        }

        socket.on('qr_update', url => showQR(url));
        socket.on('qr_clear', () => clearQR());
        socket.on('data_update', data => { db = data; render(); });

        socket.on('config_update', (cfg) => {
            if (cfg.responseDelay !== undefined) {
                document.getElementById('response-delay').value = cfg.responseDelay;
                document.getElementById('delay-value').textContent = cfg.responseDelay.toFixed(1) + ' s';
            }
            if (cfg.queueInterval !== undefined) {
                document.getElementById('queue-interval').value = cfg.queueInterval;
                document.getElementById('interval-value').textContent = cfg.queueInterval + ' ms';
            }
        });

        async function load() {
            try {
                const res = await fetch('/api/data');
                if (res.status === 401) { location.href = '/login'; return; }
                const data = await res.json();
                db = data;

                const qrWrapper = document.getElementById('qr-wrapper');
                const connectedContainer = document.getElementById('connected-container');
                const logoutBtn = document.getElementById('btn-logout-wa');
                const botStatusSpan = document.getElementById('bot-status');
                const dot = document.getElementById('dot');

                if (data.isConnected) {
                    qrWrapper.style.display = 'none';
                    connectedContainer.style.display = 'block';
                    logoutBtn.style.display = 'block';
                    clearQR();
                    botStatusSpan.innerText = 'Conectado';
                    dot.className = 'w-3 h-3 rounded-full bg-green-500';
                } else {
                    qrWrapper.style.display = 'flex';
                    connectedContainer.style.display = 'none';
                    logoutBtn.style.display = 'none';
                    botStatusSpan.innerText = data.botStatus || 'Desconectado';
                    dot.className = 'w-3 h-3 rounded-full bg-red-500 animate-pulse';
                }

                document.getElementById('conf-backup-phone').value = data.backupPhone || '';
                document.getElementById('response-delay').value = data.responseDelay || 0;
                document.getElementById('delay-value').textContent = (data.responseDelay || 0).toFixed(1) + ' s';
                document.getElementById('queue-interval').value = data.queueInterval || 500;
                document.getElementById('interval-value').textContent = (data.queueInterval || 500) + ' ms';
                document.getElementById('queue-size').textContent = data.queueSize || 0;
                document.getElementById('cleanup-learning-interval').value = data.cleanupLearningInterval || 'off';
                
                netflixConfig = data.netflixConfig || { intervalSeconds: 120, accounts: [] };
                document.getElementById('netflix-interval-seconds').value = netflixConfig.intervalSeconds;
                renderNetflixAccounts();
                
                netflixLogs = data.netflixLogs || [];
                renderNetflixLogs();
                
                render();
                lucide.createIcons();
            } catch(e) { console.error(e); }
        }

        function esc(text) {
            if (!text) return '';
            const d = document.createElement('div');
            d.appendChild(document.createTextNode(text));
            return d.innerHTML;
        }

        function formatReminderDate(dateStr) {
            if (!dateStr) return '';
            try {
                const d = new Date(dateStr);
                const day = String(d.getDate()).padStart(2,'0');
                const month = String(d.getMonth()+1).padStart(2,'0');
                const year = d.getFullYear();
                const h = d.getHours();
                const m = String(d.getMinutes()).padStart(2,'0');
                const ampm = h >= 12 ? 'PM' : 'AM';
                const h12 = h % 12 || 12;
                return day+'/'+month+'/'+year+' '+h12+':'+m+' '+ampm;
            } catch(e) { return dateStr; }
        }

        function formatDate(timestamp) {
            if (!timestamp) return '';
            try {
                return new Date(timestamp).toLocaleString('es-ES', {
                    day: '2-digit', month: '2-digit', year: 'numeric',
                    hour: '2-digit', minute: '2-digit'
                });
            } catch(e) { return timestamp; }
        }

        function render() {
            document.getElementById('s-replied').innerText = db.stats ? db.stats.replied : 0;
            document.getElementById('s-total').innerText = db.stats ? db.stats.total : 0;

            const today = new Date(new Date().toLocaleString('en-US', { timeZone: 'America/Santo_Domingo' }));
            const todayStr = today.getFullYear() + '-' + 
                             String(today.getMonth() + 1).padStart(2, '0') + '-' + 
                             String(today.getDate()).padStart(2, '0');

            const todayReminders = (db.reminders || [])
                .map((r, index) => ({ ...r, index }))
                .filter(r => r.date && r.date.startsWith(todayStr))
                .sort((a, b) => a.date.localeCompare(b.date))
                .slice(0, 5);

            const todayRemEl = document.getElementById('today-reminders-list');
            if (todayReminders.length === 0) {
                todayRemEl.innerHTML = '<div class="text-zinc-500 text-sm py-5 text-center">No hay recordatorios para hoy</div>';
            } else {
                todayRemEl.innerHTML = todayReminders.map(r => `
                    <div class="reminder-item flex justify-between items-center">
                        <div>
                            <div class="font-medium text-base">${esc(r.name)}</div>
                            <div class="text-xs text-zinc-500 mt-1">📱 ${esc(r.phone)}</div>
                        </div>
                        <div class="text-right">
                            <div class="text-sm text-emerald-400 font-mono">${formatReminderDate(r.date)}</div>
                            <span class="badge bg-blue-500/10 text-blue-400 mt-1">${r.freq}</span>
                        </div>
                    </div>
                `).join('');
            }

            const recentLearn = (db.learning || []).slice(-5).reverse();
            const learnEl = document.getElementById('recent-learning-list');
            if (recentLearn.length === 0) {
                learnEl.innerHTML = '<div class="text-zinc-500 text-sm py-5 text-center">No hay mensajes nuevos</div>';
            } else {
                learnEl.innerHTML = recentLearn.map(l => `
                    <div class="learning-item">
                        <div class="flex justify-between items-start">
                            <span class="text-xs text-zinc-500">${l.date} · ${esc(l.phone)}</span>
                            <button onclick="useLFromDashboard('${esc(l.text)}')" class="text-blue-400 hover:text-blue-300 text-xs font-medium">Usar</button>
                        </div>
                        <p class="text-sm mt-2 break-all">${esc(l.text)}</p>
                    </div>
                `).join('');
            }

            document.getElementById('l-train').innerHTML = (db.training || []).map((t,i) =>
                '<div class="glass p-5 rounded-2xl"><div class="flex justify-between items-start mb-3 gap-2"><div class="flex-1 min-w-0"><div class="flex items-center gap-2 mb-1 flex-wrap"><b class="text-blue-500 text-sm">P:</b><span class="text-sm break-all font-medium">'+esc(t.key)+'</span>'+(t.mediaPaths && t.mediaPaths.length > 0 ? '<span class="text-[10px] bg-blue-500/20 text-blue-400 px-2 py-1 rounded">'+t.mediaPaths.length+' ARCHIVO(S)</span>' : '')+'</div><span class="text-xs sm:text-sm text-zinc-400 break-all">'+esc(t.response)+'</span></div><div class="flex gap-1 flex-shrink-0"><button onclick="editT('+i+')" class="p-2 text-zinc-500 hover:text-white"><i data-lucide="edit-3" class="w-4 h-4"></i></button><button onclick="delT('+i+')" class="p-2 text-red-500"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div></div>'+(t.mediaPaths && t.mediaPaths.length > 0 ? '<div class="media-preview-container">'+t.mediaPaths.map((p, idx) => (t.mediaTypes[idx] && t.mediaTypes[idx].includes('image')) ? '<img src="/'+p+'" class="media-preview">' : '<video src="/'+p+'" class="media-preview" controls></video>').join('')+'</div>' : '')+'</div>'
            ).join('');

            document.getElementById('l-learn').innerHTML = (!db.learning || db.learning.length === 0)
                ? '<div class="glass p-8 rounded-2xl text-center text-zinc-500">No hay conversaciones nuevas</div>'
                : db.learning.map((l,i) =>
                    '<div class="glass p-4 rounded-2xl flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3"><div class="min-w-0 flex-1"><small class="text-zinc-500 text-xs">'+l.date+' - '+esc(l.phone)+'</small><br><b class="text-sm break-all">'+esc(l.text)+'</b>'+(l.hasMedia ? ' <span class="ml-1 text-[10px] bg-purple-500/20 text-purple-400 px-2 py-1 rounded">MEDIA</span>' : '')+'</div><div class="flex gap-2 flex-shrink-0"><button onclick="useL('+i+')" class="bg-blue-600 px-4 py-2 rounded-xl text-xs font-bold hover:bg-blue-700 transition">Configurar</button><button onclick="delL('+i+')" class="text-red-500 p-2"><i data-lucide="x" class="w-4 h-4"></i></button></div></div>'
                ).join('');

            document.getElementById('l-rem').innerHTML = (db.reminders || []).map((r,i) =>
                '<div class="glass p-5 rounded-2xl border-l-4 border-emerald-500"><div class="flex justify-between items-start mb-3"><b class="text-lg">'+esc(r.name)+'</b><div class="flex gap-1"><button onclick="editR('+i+')" class="text-zinc-400 hover:text-white p-1"><i data-lucide="edit-3" class="w-4 h-4"></i></button><button onclick="delR('+i+')" class="text-red-500 p-1"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div></div><p class="text-sm text-zinc-400 mb-2">📱 '+esc(r.phone)+'</p><p class="text-sm text-zinc-400 mb-3 preserve-whitespace">'+esc(r.message)+'</p><div class="flex flex-wrap gap-2"><span class="text-xs font-bold uppercase bg-emerald-500/10 text-emerald-400 px-3 py-1.5 rounded">'+r.freq+'</span><span class="text-xs font-bold uppercase bg-blue-500/10 text-blue-400 px-3 py-1.5 rounded">📅 '+formatReminderDate(r.date)+'</span></div></div>'
            ).join('');

            document.getElementById('l-excl').innerHTML = (db.excluded || []).map((e,i) =>
                '<div class="glass p-4 rounded-xl flex justify-between items-center gap-2"><span class="text-sm break-all">'+esc(e.name)+' ('+esc(e.phone)+')</span><button onclick="delE('+i+')" class="text-red-500 flex-shrink-0 p-2 hover:bg-red-500/10 rounded-lg transition"><i data-lucide="user-minus" class="w-4 h-4"></i></button></div>'
            ).join('');

            lucide.createIcons();
        }

        function useLFromDashboard(text) {
            document.getElementById('t-key').value = text;
            nav('train');
            setTimeout(() => document.getElementById('t-res').focus(), 300);
        }

        async function saveTrain(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('id', document.getElementById('t-id').value);
            fd.append('key', document.getElementById('t-key').value);
            fd.append('response', document.getElementById('t-res').value);
            if (currentMediaType === 'multimedia' && selectedFiles.length > 0) selectedFiles.forEach(f => fd.append('media', f));
            const res = await fetch('/api/train', { method:'POST', body: fd });
            if (res.ok) {
                showToast('Respuesta guardada correctamente');
                document.getElementById('t-id').value=""; document.getElementById('t-key').value=""; document.getElementById('t-res').value="";
                document.getElementById('t-media').value=""; document.getElementById('media-preview').innerHTML="";
                selectedFiles=[]; setMediaType('text'); load();
            } else {
                showToast('Error al guardar la respuesta', true);
            }
        }

        function editT(i) {
            const t = db.training[i];
            document.getElementById('t-id').value = i; document.getElementById('t-key').value = t.key; document.getElementById('t-res').value = t.response;
            if (t.mediaPaths && t.mediaPaths.length > 0) setMediaType('multimedia');
            else setMediaType('text');
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        async function delT(i) { 
            if (confirm('¿Eliminar?')) { 
                const res = await fetch('/api/train/'+i, {method:'DELETE'}); 
                if (res.ok) { showToast('Respuesta eliminada'); load(); } 
                else showToast('Error al eliminar', true);
            } 
        }

        function useL(i) { document.getElementById('t-key').value = db.learning[i].text; nav('train'); setTimeout(() => document.getElementById('t-res').focus(), 300); }

        async function delL(i) { 
            const res = await fetch('/api/learning/'+i, {method:'DELETE'}); 
            if (res.ok) { showToast('Mensaje eliminado de la bandeja'); load(); } 
            else showToast('Error al eliminar', true);
        }

        async function clearAllLearning() {
            if (confirm('⚠️ ¿Eliminar TODOS los mensajes de aprendizaje? Esta acción no se puede deshacer.')) {
                const res = await fetch('/api/learning/all', {method:'DELETE'});
                if (res.ok) { showToast('Todos los mensajes eliminados'); load(); }
                else showToast('Error al eliminar', true);
            }
        }

        async function saveRem() {
            const data = {
                id: document.getElementById('r-id').value,
                name: document.getElementById('r-name').value,
                phone: document.getElementById('r-phone').value,
                message: document.getElementById('r-msg').value,
                freq: document.getElementById('r-freq').value,
                date: document.getElementById('r-date').value
            };
            if (!data.name || !data.phone || !data.message || !data.date) { alert('Completa todos los campos'); return; }
            const res = await fetch('/api/reminders', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data) });
            if (res.ok) {
                showToast('Recordatorio guardado');
                document.getElementById('r-id').value=""; document.getElementById('r-name').value="";
                document.getElementById('r-phone').value=""; document.getElementById('r-msg').value=""; document.getElementById('r-date').value="";
                load();
            } else showToast('Error al guardar recordatorio', true);
        }

        function editR(i) {
            const r = db.reminders[i];
            document.getElementById('r-id').value = i; document.getElementById('r-name').value = r.name;
            document.getElementById('r-phone').value = r.phone; document.getElementById('r-msg').value = r.message;
            document.getElementById('r-freq').value = r.freq; document.getElementById('r-date').value = r.date;
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        async function delR(i) { 
            if (confirm('¿Eliminar?')) { 
                const res = await fetch('/api/reminders/'+i, {method:'DELETE'}); 
                if (res.ok) { showToast('Recordatorio eliminado'); load(); } 
                else showToast('Error al eliminar', true);
            } 
        }

        async function saveExcl() {
            const name = document.getElementById('e-name').value, phone = document.getElementById('e-phone').value;
            if (!name || !phone) { alert('Completa los campos'); return; }
            const res = await fetch('/api/exclude', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({name,phone}) });
            if (res.ok) { showToast('Número excluido añadido'); document.getElementById('e-name').value=""; document.getElementById('e-phone').value=""; load(); } 
            else showToast('Error al añadir', true);
        }

        async function delE(i) { 
            if (confirm('¿Eliminar?')) { 
                const res = await fetch('/api/exclude/'+i, {method:'DELETE'}); 
                if (res.ok) { showToast('Excluido eliminado'); load(); } 
                else showToast('Error al eliminar', true);
            } 
        }

        async function saveCredentials() {
            const user = document.getElementById('conf-user').value, pass = document.getElementById('conf-pass').value;
            if (!user && !pass) { alert('Ingresa al menos un campo'); return; }
            const res = await fetch('/api/config/credentials', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({user,pass}) });
            if (res.ok) { showToast('Credenciales actualizadas. Inicia sesión de nuevo.'); setTimeout(() => location.href='/login', 1500); } 
            else showToast('Error al actualizar', true);
        }

        async function saveBackupPhone() {
            const bp = document.getElementById('conf-backup-phone').value;
            const res = await fetch('/api/config/backup-phone', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({backupPhone:bp}) });
            const data = await res.json();
            if (data.ok) showToast('Número de backup guardado'); else showToast('Error al guardar', true);
        }

        async function saveConfiguracionEnvio() {
            const delay = parseFloat(document.getElementById('response-delay').value);
            const interval = parseInt(document.getElementById('queue-interval').value);
            try {
                await fetch('/api/config/delay', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ delay }) });
                await fetch('/api/config/queue-interval', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ interval }) });
                showToast('Configuración de envío guardada');
            } catch (e) { showToast(e.message, true); }
        }

        async function saveCleanupLearning() {
            const interval = document.getElementById('cleanup-learning-interval').value;
            try {
                const res = await fetch('/api/config/cleanup-learning', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ interval }) });
                if (res.ok) showToast('Configuración de limpieza guardada');
                else showToast('Error al guardar', true);
            } catch(e) { showToast('Error de conexión', true); }
        }

        document.getElementById('response-delay')?.addEventListener('input', function(e) {
            document.getElementById('delay-value').textContent = parseFloat(e.target.value).toFixed(1) + ' s';
        });

        document.getElementById('queue-interval')?.addEventListener('input', function(e) {
            document.getElementById('interval-value').textContent = e.target.value + ' ms';
        });

        function downloadBackup() { window.location.href='/api/backup/download'; }
        function downloadTemplate() { window.location.href='/api/train/template'; }
        function exportTraining() { window.location.href='/api/train/export'; }

        async function sendBackupManually() {
            const phone = document.getElementById('conf-backup-phone').value;
            if (!phone || phone.trim()=='') { alert('⚠️ Guarda un número primero'); return; }
            if (!confirm('¿Enviar backup ahora?')) return;
            const res = await fetch('/api/backup/send', {method:'POST'});
            const data = await res.json();
            if (data.ok) showToast('Backup enviado a WhatsApp'); else showToast(data.message || 'Error', true);
        }

        async function restoreBackup(input) {
            if (!input.files[0]) return;
            if (!confirm('⚠️ ¿Restaurar backup?')) { input.value=''; return; }
            const fd = new FormData(); fd.append('backup', input.files[0]);
            const res = await fetch('/api/backup/restore', {method:'POST', body:fd});
            const data = await res.json();
            if (data.ok) { showToast('Backup restaurado correctamente'); setTimeout(() => location.reload(), 1500); } 
            else showToast('Error: '+(data.error||''), true);
            input.value='';
        }

        async function importTraining(input) {
            if (!input.files[0]) return;
            const fd = new FormData(); fd.append('file', input.files[0]);
            const res = await fetch('/api/train/import', {method:'POST', body:fd});
            const data = await res.json();
            if (data.ok) { showToast(`✅ ${data.imported} respuestas importadas`); load(); } 
            else showToast('Error: '+(data.error||''), true);
            input.value=''; 
        }

        async function logoutWA() {
            if (confirm("¿Desvincular? Los contadores se reiniciarán.")) {
                const res = await fetch('/api/logout-wa', {method:'POST'});
                if (res.ok) {
                    showToast('WhatsApp desconectado. Recargando...');
                    setTimeout(() => location.reload(), 3500);
                } else {
                    const err = await res.json();
                    showToast('Error al desconectar: ' + (err.error || ''), true);
                }
            }
        }

        // Netflix
        function renderNetflixLogs() {
            const container = document.getElementById('netflix-logs-container');
            if (!container) return;
            if (!netflixLogs || netflixLogs.length === 0) {
                container.innerHTML = '<div class="text-zinc-500 text-center py-12"><i data-lucide="tv" class="w-16 h-16 mx-auto mb-4 text-zinc-600"></i><p class="text-lg">Sin actividad reciente</p></div>';
                document.getElementById('netflix-log-count').textContent = '0 códigos pendientes';
                return;
            }
            container.innerHTML = netflixLogs.map(log => {
                const date = formatDate(log.timestamp);
                let content = '';
                if (log.code) {
                    content += `<div class="flex items-center gap-3 mb-2"><span class="log-code text-2xl font-mono tracking-widest">${log.code}</span><span class="badge ${log.codeSentTo.includes('group') ? 'bg-green-500/20 text-green-400' : 'bg-yellow-500/20 text-yellow-400'}">${log.codeSentTo.includes('group') ? 'Enviado al grupo' : 'Pendiente'}</span></div>`;
                }
                if (log.linkInteraction) {
                    const successIcon = log.linkInteraction.success ? '✅' : '❌';
                    content += `<div class="text-sm text-zinc-400 mt-2"><span class="mr-2">${successIcon}</span> Actualización: ${log.linkInteraction.finalMessage}</div>`;
                    if (log.linkInteraction.codeUsed) {
                        content += `<div class="text-xs text-blue-400 mt-1">🔑 Código utilizado: ${log.linkInteraction.codeUsed}</div>`;
                    }
                    if (log.linkInteraction.steps && log.linkInteraction.steps.length) {
                        content += `<div class="interaction-step">${log.linkInteraction.steps.slice(-2).join(' → ')}</div>`;
                    }
                } else if (log.link) {
                    content += `<div class="text-sm text-zinc-500">Enlace detectado, proceso ejecutado.</div>`;
                }
                return `<div class="log-entry">
                    <div class="flex justify-between items-start">
                        <div class="flex-1">
                            <div class="text-xs text-zinc-500 mb-2">${date} · ${esc(log.account)}</div>
                            <div class="space-y-1">${content || '<span class="text-zinc-400 italic">Procesado</span>'}</div>
                        </div>
                    </div>
                </div>`;
            }).join('');
            document.getElementById('netflix-log-count').textContent = netflixLogs.length + ' códigos pendientes';
            lucide.createIcons();
        }

        function renderNetflixAccounts() {
            const container = document.getElementById('netflix-accounts-list');
            if (!container) return;
            if (!netflixConfig.accounts || netflixConfig.accounts.length === 0) {
                container.innerHTML = '<div class="text-zinc-500 text-sm">No hay cuentas agregadas</div>';
                return;
            }
            container.innerHTML = netflixConfig.accounts.map((acc, idx) => `
                <div class="bg-zinc-800/50 p-4 rounded-xl space-y-3">
                    <div class="flex items-center gap-3">
                        <div class="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-3">
                            <input type="email" placeholder="Email" value="${esc(acc.email)}" onchange="updateAccount(${idx}, 'email', this.value)" class="w-full">
                            <input type="password" placeholder="Contraseña de aplicación" value="${esc(acc.password)}" onchange="updateAccount(${idx}, 'password', this.value)" class="w-full">
                        </div>
                        <button onclick="removeAccount(${idx})" class="text-red-400 hover:text-red-300 p-2"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
                        <input type="text" placeholder="ID del grupo (ej: 123456789@g.us)" value="${esc(acc.groupPhone||'')}" onchange="updateAccount(${idx}, 'groupPhone', this.value)" class="w-full">
                        <div class="flex items-center gap-2 text-sm">
                            <input type="checkbox" id="verif-${idx}" ${acc.sendVerificationCodesToGroup ? 'checked' : ''} onchange="updateAccount(${idx}, 'sendVerificationCodesToGroup', this.checked)" class="w-4 h-4">
                            <label for="verif-${idx}" class="text-zinc-400">Enviar verificación al grupo</label>
                        </div>
                    </div>
                </div>
            `).join('');
            lucide.createIcons();
        }

        function addNetflixAccount() {
            netflixConfig.accounts.push({ email: '', password: '', groupPhone: '', sendVerificationCodesToGroup: false });
            renderNetflixAccounts();
        }

        function removeAccount(idx) {
            if (confirm('¿Eliminar esta cuenta Netflix?')) {
                netflixConfig.accounts.splice(idx, 1);
                renderNetflixAccounts();
            }
        }

        function updateAccount(idx, field, value) {
            if (field === 'sendVerificationCodesToGroup') {
                netflixConfig.accounts[idx].sendVerificationCodesToGroup = value;
            } else {
                netflixConfig.accounts[idx][field] = value;
            }
        }

        async function saveNetflixConfig() {
            const intervalSeconds = parseInt(document.getElementById('netflix-interval-seconds').value) || 120;
            try {
                const r = await fetch('/api/netflix/config', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ intervalSeconds, accounts: netflixConfig.accounts })
                });
                const d = await r.json();
                if (d.ok) showToast('Configuración Netflix guardada');
                else showToast('Error: ' + (d.message||''), true);
            } catch(e) { showToast('Error de conexión', true); }
        }

        window.onload = load;
        lucide.createIcons();
    </script>
</body>
</html>
HTMLEOF

# ===================== LOGIN =====================
cat <<'LOGINEOF' > views/login.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GZMBOT | Login</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;800&display=swap" rel="stylesheet">
    <style>
        * { box-sizing: border-box; }
        body { background: #0a0a0f; font-family: 'Inter', sans-serif; height: 100vh; display: flex; align-items: center; justify-content: center; overflow: hidden; padding: 16px; background-image: radial-gradient(circle at 50% 50%, rgba(37,99,235,0.1) 0%, transparent 60%); }
        .glow { position: absolute; width: 600px; height: 600px; background: radial-gradient(circle, rgba(37,99,235,0.15) 0%, transparent 70%); z-index: -1; }
        .card { background: rgba(18,18,24,0.9); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.03); box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5); }
        .aluminum-title { color: #e5e7eb; font-weight: 800; letter-spacing: -0.02em; }
    </style>
</head>
<body>
    <div class="glow"></div>
    <div class="card p-8 sm:p-12 rounded-[2.5rem] sm:rounded-[3.5rem] w-full max-w-md shadow-2xl text-center">
        <h1 class="text-3xl sm:text-4xl font-black mb-2 tracking-tight aluminum-title">GZMBOT</h1>
        <p class="text-blue-500 font-bold text-[10px] uppercase tracking-[0.3em] mb-8 sm:mb-10">Administrative Panel</p>
        <form onsubmit="login(event)" class="space-y-4">
            <input type="text" id="u" placeholder="Usuario maestro" class="w-full p-4 bg-black/40 rounded-2xl border border-white/5 text-white outline-none text-base" required>
            <input type="password" id="p" placeholder="Contraseña" class="w-full p-4 bg-black/40 rounded-2xl border border-white/5 text-white outline-none text-base" required>
            <button type="submit" class="w-full py-4 sm:py-5 bg-blue-600 rounded-2xl text-white font-black hover:scale-[1.02] active:scale-95 transition-all">ACCEDER AHORA</button>
        </form>
    </div>
    <script>
        async function login(e) {
            e.preventDefault();
            const r = await fetch('/login', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({user:document.getElementById('u').value, pass:document.getElementById('p').value}) });
            const d = await r.json();
            if (d.ok) location.href='/'; else alert("Credenciales incorrectas");
        }
    </script>
</body>
</html>
LOGINEOF

# ----------------------------------------------------------------------
# 11. INSTALAR DEPENDENCIAS DE NODE
# ----------------------------------------------------------------------
echo "📦 Instalando dependencias de Node.js..."
cd $HOME/gzmbot
npm install --legacy-peer-deps \
    whatsapp-web.js \
    qrcode \
    express \
    socket.io \
    express-session \
    puppeteer \
    puppeteer-extra \
    puppeteer-extra-plugin-stealth \
    moment-timezone \
    node-cron \
    multer \
    imapflow \
    mailparser \
    axios

sudo npm install -g pm2
pm2 delete gzmbot 2>/dev/null
pm2 start app.js --name gzmbot --env TZ=America/Santo_Domingo
pm2 save
pm2 startup systemd -u $USER --hp $HOME
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $HOME

# ----------------------------------------------------------------------
# 12. NGINX + SSL
# ----------------------------------------------------------------------
echo "🔧 Instalando Nginx y configurando SSL con Let's Encrypt..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

sudo tee /etc/nginx/sites-available/gzmbot > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 50M;
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
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/gzmbot /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

# ----------------------------------------------------------------------
# 13. INFORMACIÓN FINAL
# ----------------------------------------------------------------------
echo "===================================================="
echo "✨ GZMBOT ENTERPRISE - INSTALACIÓN COMPLETADA (v12)"
echo "===================================================="
echo "🌐 PANEL: https://$DOMAIN"
echo "👤 USUARIO: $ADMIN_USER"
echo "🔐 PASS: $ADMIN_PASS"
echo "🕐 TIMEZONE: America/Santo_Domingo (UTC-4)"
echo "===================================================="