#!/bin/bash

# SCRIPT COMPLETO - ABARROTE PANEL
# Versión corregida para evitar errores internos del servidor
# Incluye todas las funcionalidades solicitadas: login obligatorio, token del bot, envío de fotos por Telegram, diseño profesional, recomendaciones de carrito, edición de perfil
# Colores: azul, negro, gris, blanco, modo oscuro
# Ícono de carrito en lugar de patana
# Nombre del panel: Abarrote con ícono de tienda
# Diseño moderno: Usando Tailwind CSS con transiciones, sombras, responsive layout, font Inter, iconos FontAwesome

set -e

echo "=================================================="
echo "    INSTALADOR COMPLETO - ABARROTE PANEL"
echo "=================================================="
echo

# Verificar Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    echo "❌ Este script es solo para Ubuntu"
    exit 1
fi

# Configuración
PANEL_DIR="/opt/abarrote-panel"
SERVICE_USER="paneluser"
NGINX_CONF="/etc/nginx/sites-available/abarrote-panel"
NGINX_LINK="/etc/nginx/sites-enabled/abarrote-panel"
NGINX_DEFAULT="/etc/nginx/sites-enabled/default"
DB_PATH="$PANEL_DIR/employees.db"

# Detener servicios previos si existen
sudo systemctl stop abarrote-panel 2>/dev/null || true
sudo systemctl disable abarrote-panel 2>/dev/null || true
sudo systemctl stop nginx 2>/dev/null || true

# Crear usuario
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "👤 Creando usuario $SERVICE_USER..."
    sudo useradd -r -s /bin/bash -d "$PANEL_DIR" "$SERVICE_USER" || { echo "Error creando usuario"; exit 1; }
fi

# Crear directorio
echo "📁 Creando directorio..."
sudo mkdir -p "$PANEL_DIR/templates" "$PANEL_DIR/static" "$PANEL_DIR/uploads"
sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$PANEL_DIR"
cd "$PANEL_DIR"

# Instalar dependencias
echo "📦 Instalando dependencias del sistema..."
sudo apt update || { echo "Error en apt update"; exit 1; }
sudo apt install -y python3 python3-pip python3-venv sqlite3 curl nginx python3-certbot-nginx || { echo "Error instalando paquetes"; exit 1; }

# Crear requirements.txt
echo "🐍 Configurando Python..."
sudo -u "$SERVICE_USER" bash -c "cat > requirements.txt" << 'EOF'
flask==2.3.3
flask-sqlalchemy==3.0.5
flask-login==0.6.3
werkzeug==2.3.7
requests==2.31.0
python-telegram-bot==20.7
gunicorn==21.2.0
apscheduler==3.10.4
pytz==2023.3
EOF

# Entorno virtual
echo "🔧 Configurando entorno virtual..."
sudo -u "$SERVICE_USER" python3 -m venv venv || { echo "Error creando venv"; exit 1; }
sudo -u "$SERVICE_USER" bash -c "
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt || { echo 'Error instalando pip paquetes'; exit 1; }
"

# Crear aplicación Flask
echo "🚀 Creando aplicación Flask..."
sudo -u "$SERVICE_USER" bash -c "cat > app.py" << 'EOF'
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_file, session
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from datetime import datetime, timedelta, date
import requests
from threading import Thread
import os
from apscheduler.schedulers.background import BackgroundScheduler
import atexit
import logging
import random
import pytz
from io import BytesIO
import sqlite3
import telegram
from telegram.ext import Updater, CommandHandler

# Configurar logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s', filename='/opt/abarrote-panel/app.log')
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SECRET_KEY'] = 'clave-secreta-segura-2024-abarrote'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:////opt/abarrote-panel/employees.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['UPLOAD_FOLDER'] = '/opt/abarrote-panel/uploads'
app.config['STATIC_FOLDER'] = '/opt/abarrote-panel/static'
app.config['ALLOWED_EXTENSIONS'] = {'png', 'jpg', 'jpeg'}
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max-limit

db = SQLAlchemy(app)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# Bot de Telegram
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '8290025107:AAHXW-gc0DhocRb4dOBgnZ8wiBDbRELIZnA')

# Zona horaria RD
TZ_RD = pytz.timezone('America/Santo_Domingo')

# Configurar scheduler
scheduler = BackgroundScheduler(timezone=TZ_RD)
scheduler.start()
atexit.register(lambda: scheduler.shutdown())

class Employee(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    employee_code = db.Column(db.String(20), unique=True, nullable=False)
    name = db.Column(db.String(100), nullable=False)
    password_hash = db.Column(db.String(200), nullable=False)
    role = db.Column(db.String(20), nullable=False)
    aisle = db.Column(db.String(10), default='1')
    day_off = db.Column(db.String(20), default='Domingo')
    telegram_id = db.Column(db.String(50), default='N/A')
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(TZ_RD))

class Task(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    description = db.Column(db.Text, nullable=False)
    assigned_to_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    assigned_by_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    status = db.Column(db.String(20), default='asignada')
    date_created = db.Column(db.DateTime, default=lambda: datetime.now(TZ_RD))
    completed_at = db.Column(db.DateTime)
    priority = db.Column(db.String(20), default='media')
    is_patana = db.Column(db.Boolean, default=False)
    requires_photo = db.Column(db.Boolean, default=False)
    photo_path = db.Column(db.String(200))
    due_date = db.Column(db.DateTime)
    due_time = db.Column(db.String(10))
    
    assigned_to = db.relationship('Employee', foreign_keys=[assigned_to_id], backref='tasks')
    assigned_by = db.relationship('Employee', foreign_keys=[assigned_by_id])

class TeamTask(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    description = db.Column(db.Text, nullable=False, default='Quedarse en el montacarga para recibir y organizar los productos')
    employee1_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    employee2_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    assigned_by_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    execution_time = db.Column(db.DateTime)
    is_executed = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(TZ_RD))
    date = db.Column(db.Date, default=lambda: date.today())
    
    employee1 = db.relationship('Employee', foreign_keys=[employee1_id])
    employee2 = db.relationship('Employee', foreign_keys=[employee2_id])
    assigned_by = db.relationship('Employee', foreign_keys=[assigned_by_id])

class PatanaAssignment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    date = db.Column(db.Date, nullable=False, default=lambda: date.today())
    original_employee_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    replacement_employee_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    aisle = db.Column(db.String(10), nullable=False)
    assigned_by_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(TZ_RD))
    
    original_employee = db.relationship('Employee', foreign_keys=[original_employee_id])
    replacement_employee = db.relationship('Employee', foreign_keys=[replacement_employee_id])
    assigned_by = db.relationship('Employee', foreign_keys=[assigned_by_id])

class Log(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    action = db.Column(db.String(100), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    timestamp = db.Column(db.DateTime, default=lambda: datetime.now(TZ_RD))
    details = db.Column(db.Text)

    user = db.relationship('Employee', foreign_keys=[user_id])

@login_manager.user_loader
def load_user(user_id):
    try:
        return Employee.query.get(int(user_id))
    except Exception as e:
        logger.error(f"Error cargando usuario {user_id}: {e}")
        return None

def send_telegram_message(chat_id, message, photo=None):
    if not chat_id or chat_id == 'N/A':
        return
    try:
        bot = telegram.Bot(token=TELEGRAM_BOT_TOKEN)
        if photo:
            bot.send_photo(chat_id=chat_id, photo=photo, caption=message, parse_mode='HTML')
        else:
            bot.send_message(chat_id=chat_id, text=message, parse_mode='HTML')
        logger.info(f"Mensaje enviado a {chat_id}")
    except Exception as e:
        logger.error(f"Error enviando mensaje Telegram: {e}")

def get_day_of_week_in_spanish():
    days = {
        'Monday': 'Lunes',
        'Tuesday': 'Martes', 
        'Wednesday': 'Miércoles',
        'Thursday': 'Jueves',
        'Friday': 'Viernes',
        'Saturday': 'Sábado',
        'Sunday': 'Domingo'
    }
    today_english = datetime.now(TZ_RD).strftime('%A')
    return days.get(today_english, today_english)

def get_patana_recommendations():
    try:
        today = get_day_of_week_in_spanish()
        employees_off_today = Employee.query.filter(
            Employee.day_off == today, 
            Employee.is_active == True,
            Employee.role == 'worker'
        ).all()
        
        employees_working_today = Employee.query.filter(
            Employee.day_off != today,
            Employee.is_active == True,
            Employee.role == 'worker'
        ).all()
        
        recommendations = []
        
        for emp_off in employees_off_today:
            available_workers = [emp for emp in employees_working_today if emp.id != emp_off.id]
            
            if available_workers:
                recommendation = {
                    'employee_off': emp_off,
                    'aisle_to_cover': emp_off.aisle,
                    'available_workers': available_workers
                }
                recommendations.append(recommendation)
        
        return recommendations
    except Exception as e:
        logger.error(f"Error en get_patana_recommendations: {e}")
        return []

def get_todays_patana_assignments():
    try:
        today = date.today()
        assignments = PatanaAssignment.query.filter_by(date=today).all()
        return assignments
    except Exception as e:
        logger.error(f"Error obteniendo asignaciones de carrito: {e}")
        return []

def get_todays_team_task():
    try:
        today = date.today()
        team_task = TeamTask.query.filter_by(date=today).first()
        return team_task
    except Exception as e:
        logger.error(f"Error obteniendo tarea de equipo: {e}")
        return None

def auto_assign_team_task():
    try:
        today = date.today()
        
        existing_task = TeamTask.query.filter_by(date=today).first()
        if existing_task:
            logger.info("Ya existe una tarea de equipo para hoy")
            return
        
        today_day = get_day_of_week_in_spanish()
        available_workers = Employee.query.filter(
            Employee.day_off != today_day,
            Employee.is_active == True,
            Employee.role == 'worker'
        ).all()
        
        if len(available_workers) >= 2:
            selected_workers = random.sample(available_workers, 2)
            
            admin = Employee.query.filter_by(role='admin_principal').first()
            
            execution_time = datetime.now(TZ_RD).replace(hour=17, minute=40, second=0, microsecond=0)
            
            team_task = TeamTask(
                description="Quedarse en el montacarga para recibir y organizar los productos. Los demás empleados bajarán a recibir los productos.",
                employee1_id=selected_workers[0].id,
                employee2_id=selected_workers[1].id,
                assigned_by_id=admin.id if admin else 1,
                execution_time=execution_time,
                date=today
            )
            db.session.add(team_task)
            db.session.commit()
            
            logger.info(f"Tarea de equipo asignada automáticamente a {selected_workers[0].name} y {selected_workers[1].name}")
            
            for emp in selected_workers:
                if emp.telegram_id != 'N/A':
                    message = f"📦 ASIGNACIÓN AUTOMÁTICA MONTACARGA\n\nHas sido seleccionado para quedarte en el montacarga hoy a las 5:40 PM.\n\nTarea: Recibir y organizar los productos.\nCompañero: {selected_workers[1].name if emp.id == selected_workers[0].id else selected_workers[0].name}\n\nLos demás empleados bajarán a recibir los productos que ustedes enviarán."
                    Thread(target=send_telegram_message, args=(emp.telegram_id, message)).start()
                    
            other_workers = [emp for emp in available_workers if emp.id not in [selected_workers[0].id, selected_workers[1].id]]
            for emp in other_workers:
                if emp.telegram_id != 'N/A':
                    message = f"📦 ASIGNACIÓN AUTOMÁTICA ALMACÉN\n\nHoy a las 5:40 PM, bajarás a recibir los productos en el almacén.\n\nLos empleados en montacarga: {selected_workers[0].name} y {selected_workers[1].name}."
                    Thread(target=send_telegram_message, args=(emp.telegram_id, message)).start()
                    
    except Exception as e:
        logger.error(f"Error en auto_assign_team_task: {e}")

def execute_scheduled_team_tasks():
    try:
        now = datetime.now(TZ_RD)
        today = date.today()
        
        team_tasks = TeamTask.query.filter(
            TeamTask.date == today,
            TeamTask.is_executed == False
        ).all()
        
        for task in team_tasks:
            if now >= task.execution_time:
                employees = [task.employee1, task.employee2]
                for emp in employees:
                    if emp.telegram_id != 'N/A':
                        message = f"📦 RECORDATORIO MONTACARGA\n\nEs hora de ir al montacarga para recibir y organizar los productos.\n\nTarea asignada: 5:40 PM\nCompañero: {task.employee2.name if emp.id == task.employee1.id else task.employee1.name}\n\nPor favor proceda a su asignación!"
                        Thread(target=send_telegram_message, args=(emp.telegram_id, message)).start()
                
                task.is_executed = True
                db.session.commit()
                logger.info(f"Tarea de equipo ejecutada: {task.employee1.name} y {task.employee2.name}")
                
    except Exception as e:
        logger.error(f"Error en execute_scheduled_team_tasks: {e}")

def check_overdue_tasks():
    try:
        now = datetime.now(TZ_RD)
        overdue_tasks = Task.query.filter(
            Task.status.notin_(['completada', 'vencida']),
            Task.due_date < now
        ).all()
        
        for task in overdue_tasks:
            task.status = 'vencida'
            db.session.commit()
            
            if task.assigned_to.telegram_id != 'N/A':
                message = f"⚠️ Tarea vencida: {task.description}\n\nVenció el {task.due_date.strftime('%d/%m/%Y %H:%M')}. Por favor complete lo antes posible."
                Thread(target=send_telegram_message, args=(task.assigned_to.telegram_id, message)).start()
                
    except Exception as e:
        logger.error(f"Error en check_overdue_tasks: {e}")

def clean_completed_tasks():
    try:
        eight_hours_ago = datetime.now(TZ_RD) - timedelta(hours=8)
        completed_tasks = Task.query.filter(
            Task.status == 'completada',
            Task.completed_at < eight_hours_ago
        ).all()
        
        for task in completed_tasks:
            if task.photo_path and os.path.exists(task.photo_path):
                os.remove(task.photo_path)
            db.session.delete(task)
        
        db.session.commit()
        logger.info(f"Eliminadas {len(completed_tasks)} tareas completadas.")
    except Exception as e:
        logger.error(f"Error en clean_completed_tasks: {e}")

def create_backup():
    try:
        conn = sqlite3.connect(app.config['SQLALCHEMY_DATABASE_URI'].replace('sqlite:///', ''))
        cursor = conn.cursor()
        backup_file = f"/opt/abarrote-panel/backup_{datetime.now(TZ_RD).strftime('%Y%m%d_%H%M%S')}.sql"
        with open(backup_file, 'w') as f:
            for line in conn.iterdump():
                f.write(f"{line}\n")
        
        admin = Employee.query.filter_by(role='admin_principal').first()
        if admin and admin.telegram_id != 'N/A':
            message = f"📂 Copia de seguridad automática creada el {datetime.now(TZ_RD).strftime('%d/%m/%Y %H:%M')}."
            send_telegram_message(admin.telegram_id, message, backup_file)
        
        logger.info("Backup automático creado y enviado.")
    except Exception as e:
        logger.error(f"Error en create_backup: {e}")

# Programar tareas automáticas
scheduler.add_job(
    func=auto_assign_team_task,
    trigger='cron',
    hour=8,
    minute=0,
    id='auto_assign_team_task'
)

scheduler.add_job(
    func=execute_scheduled_team_tasks,
    trigger='cron',
    hour=17,
    minute=40,
    id='execute_team_tasks'
)

scheduler.add_job(
    func=check_overdue_tasks,
    trigger='interval',
    minutes=5,
    id='check_overdue_tasks'
)

scheduler.add_job(
    func=clean_completed_tasks,
    trigger='cron',
    hour=3,
    minute=0,
    id='clean_completed_tasks'
)

scheduler.add_job(
    func=create_backup,
    trigger='cron',
    hour=4,
    minute=0,
    id='create_backup'
)

# Bot Telegram setup
def start_telegram_bot():
    try:
        updater = Updater(token=TELEGRAM_BOT_TOKEN, use_context=True)
        dp = updater.dispatcher
        dp.add_handler(CommandHandler('start', start_handler))
        updater.start_polling()
        updater.idle()
    except Exception as e:
        logger.error(f"Error iniciando bot de Telegram: {e}")

def start_handler(update, context):
    try:
        chat_id = update.message.chat_id
        update.message.reply_text(f"Su ID de Telegram es: {chat_id}\n\nEnvíe este ID al administrador para registrar en el panel.")
        employee = Employee.query.filter_by(telegram_id=str(chat_id)).first()
        if employee:
            update.message.reply_text("Bot activado — recibirá sus tareas.")
        else:
            update.message.reply_text("Registre este ID en su perfil del panel para recibir notificaciones.")
        
        admin = Employee.query.filter_by(role='admin_principal').first()
        if admin and admin.telegram_id != 'N/A':
            message = f"📢 Nuevo usuario ha iniciado el bot. ID de Telegram: {chat_id}"
            send_telegram_message(admin.telegram_id, message)
    except Exception as e:
        logger.error(f"Error en start_handler: {e}")

Thread(target=start_telegram_bot).start()

# Rutas
@app.route('/')
def index():
    try:
        if current_user.is_authenticated:
            if current_user.role == 'worker':
                return redirect(url_for('worker_dashboard'))
            return redirect(url_for('admin_dashboard'))
        return redirect(url_for('login'))
    except Exception as e:
        logger.error(f"Error en ruta /: {e}")
        flash('Error al cargar la página inicial', 'error')
        return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    try:
        if current_user.is_authenticated:
            return redirect(url_for('index'))
        
        if request.method == 'POST':
            code = request.form.get('employee_code')
            password = request.form.get('password')
            if not code or not password:
                flash('Código de empleado y contraseña son requeridos', 'error')
                return render_template('login.html')
            
            employee = Employee.query.filter_by(employee_code=code, is_active=True).first()
            
            if employee and check_password_hash(employee.password_hash, password):
                session.clear()  # Limpiar cualquier sesión previa
                login_user(employee)
                flash('Inicio de sesión exitoso', 'success')
                log_action(employee.id, 'login', 'Inicio de sesión')
                if employee.role == 'worker':
                    return redirect(url_for('worker_dashboard'))
                return redirect(url_for('admin_dashboard'))
            else:
                flash('Credenciales incorrectas', 'error')
        return render_template('login.html')
    except Exception as e:
        logger.error(f"Error en login: {e}")
        flash('Error interno al iniciar sesión', 'error')
        return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    try:
        session.clear()
        logout_user()
        flash('Sesión cerrada correctamente', 'info')
        return redirect(url_for('login'))
    except Exception as e:
        logger.error(f"Error en logout: {e}")
        flash('Error al cerrar sesión', 'error')
        return redirect(url_for('login'))

@app.route('/profile', methods=['GET', 'POST'])
@login_required
def profile():
    try:
        if request.method == 'POST':
            current_user.name = request.form.get('name')
            current_user.aisle = request.form.get('aisle')
            current_user.day_off = request.form.get('day_off')
            current_user.telegram_id = request.form.get('telegram_id', 'N/A')
            password = request.form.get('password')
            if password:
                current_user.password_hash = generate_password_hash(password)
            db.session.commit()
            flash('Perfil actualizado', 'success')
            log_action(current_user.id, 'update_profile', 'Perfil actualizado')
            return redirect(url_for('profile'))
        return render_template('profile.html', user=current_user)
    except Exception as e:
        logger.error(f"Error en profile: {e}")
        flash('Error al actualizar perfil', 'error')
        return render_template('profile.html', user=current_user)

@app.route('/worker/dashboard')
@login_required
def worker_dashboard():
    try:
        if current_user.role != 'worker':
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        
        tasks = Task.query.filter_by(assigned_to_id=current_user.id).order_by(Task.date_created.desc()).all()
        pending_tasks = [task for task in tasks if task.status in ['asignada', 'en_progreso']]
        completed_tasks = [task for task in tasks if task.status == 'completada']
        
        aisle_mates = Employee.query.filter(
            Employee.aisle == current_user.aisle,
            Employee.id != current_user.id,
            Employee.role == 'worker',
            Employee.is_active == True
        ).all()
        
        todays_team_task = get_todays_team_task()
        user_in_team_task = False
        if todays_team_task:
            user_in_team_task = current_user.id in [todays_team_task.employee1_id, todays_team_task.employee2_id]
        
        return render_template('worker_dashboard.html', 
                             tasks=tasks,
                             pending_tasks=pending_tasks,
                             completed_tasks=completed_tasks,
                             aisle_mates=aisle_mates,
                             todays_team_task=todays_team_task,
                             user_in_team_task=user_in_team_task,
                             user=current_user)
    except Exception as e:
        logger.error(f"Error en worker_dashboard: {e}")
        flash('Error al cargar el dashboard', 'error')
        return redirect(url_for('login'))

@app.route('/admin/dashboard')
@login_required
def admin_dashboard():
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('worker_dashboard'))
        
        employees = Employee.query.order_by(Employee.created_at.desc()).all()
        tasks = Task.query.order_by(Task.date_created.desc()).all()
        workers = Employee.query.filter_by(role='worker', is_active=True).all()
        team_tasks = TeamTask.query.order_by(TeamTask.created_at.desc()).limit(5).all()
        
        patana_recommendations = get_patana_recommendations()
        todays_patana_assignments = get_todays_patana_assignments()
        todays_team_task = get_todays_team_task()
        
        stats = {
            'total_employees': len(employees),
            'active_workers': len(workers),
            'pending_tasks': len([t for t in tasks if t.status in ['asignada', 'en_progreso']]),
            'completed_tasks': len([t for t in tasks if t.status == 'completada']),
            'employees_off_today': len(patana_recommendations),
            'patana_assignments_today': len(todays_patana_assignments)
        }
        
        return render_template('admin_dashboard.html', 
                             employees=employees, 
                             tasks=tasks,
                             workers=workers,
                             team_tasks=team_tasks,
                             patana_recommendations=patana_recommendations,
                             todays_patana_assignments=todays_patana_assignments,
                             todays_team_task=todays_team_task,
                             stats=stats,
                             current_user=current_user)
    except Exception as e:
        logger.error(f"Error en admin_dashboard: {e}")
        flash('Error al cargar el dashboard', 'error')
        return redirect(url_for('login'))

@app.route('/complete_task/<int:task_id>', methods=['GET', 'POST'])
@login_required
def complete_task(task_id):
    try:
        task = Task.query.get_or_404(task_id)
        if task.assigned_to_id != current_user.id:
            flash('No autorizado', 'error')
            return redirect(url_for('worker_dashboard'))
        
        if request.method == 'POST':
            task.status = 'completada'
            task.completed_at = datetime.now(TZ_RD)
            
            photo = None
            if task.requires_photo:
                if 'photo' not in request.files:
                    flash('Foto requerida', 'error')
                    return redirect(request.url)
                file = request.files['photo']
                if file.filename == '':
                    flash('No se seleccionó foto', 'error')
                    return redirect(request.url)
                if file and allowed_file(file.filename):
                    photo = BytesIO(file.read())
                    file.seek(0)
                    
                    admin = Employee.query.filter_by(role='admin_principal').first()
                    if admin and admin.telegram_id != 'N/A':
                        message = f"📸 Tarea completada por {current_user.name}: {task.description}. Por favor, califique la tarea."
                        send_telegram_message(admin.telegram_id, message, photo=photo)
            
            db.session.commit()
            flash('Tarea completada', 'success')
            if task.assigned_to.telegram_id != 'N/A':
                message = f"✅ Tarea completada: {task.description}"
                send_telegram_message(task.assigned_to.telegram_id, message)
            log_action(current_user.id, 'complete_task', f"Tarea {task_id} completada")
            return redirect(url_for('worker_dashboard'))
        
        return render_template('complete_task.html', task=task)
    except Exception as e:
        logger.error(f"Error en complete_task: {e}")
        flash('Error al completar tarea', 'error')
        return redirect(url_for('worker_dashboard'))

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in app.config['ALLOWED_EXTENSIONS']

def log_action(user_id, action, details=''):
    try:
        log = Log(user_id=user_id, action=action, details=details)
        db.session.add(log)
        db.session.commit()
    except Exception as e:
        logger.error(f"Error en log_action: {e}")

@app.route('/admin/config')
@login_required
def config():
    try:
        if current_user.role != 'admin_principal':
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        return render_template('config.html', token=TELEGRAM_BOT_TOKEN)
    except Exception as e:
        logger.error(f"Error en config: {e}")
        flash('Error al cargar configuración', 'error')
        return redirect(url_for('admin_dashboard'))

@app.route('/admin/config/update_token', methods=['POST'])
@login_required
def update_token():
    try:
        if current_user.role != 'admin_principal':
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        global TELEGRAM_BOT_TOKEN
        TELEGRAM_BOT_TOKEN = request.form.get('token')
        os.environ['TELEGRAM_BOT_TOKEN'] = TELEGRAM_BOT_TOKEN
        flash('Token actualizado', 'success')
        log_action(current_user.id, 'update_token', 'Token bot actualizado')
        return redirect(url_for('config'))
    except Exception as e:
        logger.error(f"Error en update_token: {e}")
        flash('Error al actualizar token', 'error')
        return redirect(url_for('config'))

@app.route('/admin/config/backup', methods=['GET', 'POST'])
@login_required
def manual_backup():
    try:
        if current_user.role != 'admin_principal':
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        if request.method == 'POST':
            create_backup()
            flash('Backup manual creado y enviado', 'success')
            log_action(current_user.id, 'manual_backup', 'Backup manual creado')
        return redirect(url_for('config'))
    except Exception as e:
        logger.error(f"Error en manual_backup: {e}")
        flash('Error al crear backup', 'error')
        return redirect(url_for('config'))

@app.route('/admin/config/restore', methods=['POST'])
@login_required
def restore_backup():
    try:
        if current_user.role != 'admin_principal':
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        if 'backup_file' not in request.files:
            flash('No se seleccionó archivo', 'error')
            return redirect(url_for('config'))
        file = request.files['backup_file']
        if file.filename == '':
            flash('No se seleccionó archivo', 'error')
            return redirect(url_for('config'))
        if file:
            filename = secure_filename(file.filename)
            backup_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(backup_path)
            
            try:
                conn = sqlite3.connect(app.config['SQLALCHEMY_DATABASE_URI'].replace('sqlite:///', ''))
                with open(backup_path, 'r') as f:
                    sql = f.read()
                conn.executescript(sql)
                conn.commit()
                flash('Backup restaurado', 'success')
                log_action(current_user.id, 'restore_backup', f"Backup {filename} restaurado")
            except Exception as e:
                flash('Error al restaurar backup', 'error')
                logger.error(f"Error restaurando backup: {e}")
            finally:
                os.remove(backup_path)
        return redirect(url_for('config'))
    except Exception as e:
        logger.error(f"Error en restore_backup: {e}")
        flash('Error al restaurar backup', 'error')
        return redirect(url_for('config'))

@app.route('/admin/config/domain', methods=['POST'])
@login_required
def set_domain():
    try:
        if current_user.role != 'admin_principal':
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        domain = request.form.get('domain')
        if domain:
            os.system(f"sudo certbot --nginx -d {domain} --non-interactive --agree-tos --email admin@example.com")
            flash('Dominio configurado y HTTPS habilitado', 'success')
            log_action(current_user.id, 'set_domain', f"Dominio {domain} configurado")
        return redirect(url_for('config'))
    except Exception as e:
        logger.error(f"Error en set_domain: {e}")
        flash('Error al configurar dominio', 'error')
        return redirect(url_for('config'))

@app.route('/admin/tasks/add', methods=['POST'])
@login_required
def add_task():
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        
        description = request.form.get('description')
        employee_ids = request.form.getlist('employee_id')
        priority = request.form.get('priority', 'media')
        is_patana = request.form.get('is_patana') == 'on'
        requires_photo = request.form.get('requires_photo') == 'on'
        due_date = request.form.get('due_date')
        due_time = request.form.get('due_time')
        
        if not description or not employee_ids:
            flash('Descripción y empleados son requeridos', 'error')
            return redirect(url_for('manage_tasks'))
        
        due_datetime = None
        if due_date and due_time:
            try:
                due_datetime = TZ_RD.localize(datetime.strptime(f"{due_date} {due_time}", "%Y-%m-%d %H:%M"))
            except ValueError:
                flash('Formato de fecha u hora inválido', 'error')
                return redirect(url_for('manage_tasks'))
        
        for employee_id in employee_ids:
            task = Task(
                description=description,
                assigned_to_id=employee_id,
                assigned_by_id=current_user.id,
                priority=priority,
                is_patana=is_patana,
                requires_photo=requires_photo,
                due_date=due_datetime,
                due_time=due_time
            )
            db.session.add(task)
        
        db.session.commit()
        
        for employee_id in employee_ids:
            employee = Employee.query.get(employee_id)
            if employee and employee.telegram_id != 'N/A':
                due_text = f"\nVence: {due_datetime.strftime('%d/%m/%Y %H:%M')}" if due_datetime else ""
                photo_text = " (Requiere foto)" if requires_photo else ""
                message = f"📋 NUEVA TAREA ASIGNADA{photo_text}\n\n{description}\n\nPrioridad: {priority.upper()}\nPasillo: {employee.aisle}\nAsignada por: {current_user.name}{due_text}"
                Thread(target=send_telegram_message, args=(employee.telegram_id, message)).start()
        
        flash('Tarea asignada correctamente', 'success')
        log_action(current_user.id, 'add_task', f"Tarea asignada a {len(employee_ids)} empleados")
        return redirect(url_for('manage_tasks'))
    except Exception as e:
        logger.error(f"Error en add_task: {e}")
        flash('Error al asignar tarea', 'error')
        return redirect(url_for('manage_tasks'))

@app.route('/admin/employees/add', methods=['POST'])
@login_required
def add_employee():
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        
        name = request.form.get('name')
        employee_code = request.form.get('employee_code')
        password = request.form.get('password')
        role = request.form.get('role')
        aisle = request.form.get('aisle')
        day_off = request.form.get('day_off')
        telegram_id = request.form.get('telegram_id', 'N/A')
        
        if not all([name, employee_code, password, role]):
            flash('Todos los campos requeridos deben completarse', 'error')
            return redirect(url_for('manage_employees'))
        
        if Employee.query.filter_by(employee_code=employee_code).first():
            flash('Código de empleado ya existe', 'error')
            return redirect(url_for('manage_employees'))
        
        employee = Employee(
            name=name,
            employee_code=employee_code,
            password_hash=generate_password_hash(password),
            role=role,
            aisle=aisle,
            day_off=day_off,
            telegram_id=telegram_id
        )
        db.session.add(employee)
        db.session.commit()
        
        flash('Empleado agregado correctamente', 'success')
        log_action(current_user.id, 'add_employee', f"Empleado {name} agregado")
        return redirect(url_for('manage_employees'))
    except Exception as e:
        logger.error(f"Error en add_employee: {e}")
        flash('Error al agregar empleado', 'error')
        return redirect(url_for('manage_employees'))

@app.route('/admin/employees/edit/<int:employee_id>', methods=['GET', 'POST'])
@login_required
def edit_employee(employee_id):
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        
        employee = Employee.query.get_or_404(employee_id)
        
        if request.method == 'POST':
            employee.name = request.form.get('name')
            employee.employee_code = request.form.get('employee_code')
            password = request.form.get('password')
            if password:
                employee.password_hash = generate_password_hash(password)
            employee.role = request.form.get('role')
            employee.aisle = request.form.get('aisle')
            employee.day_off = request.form.get('day_off')
            employee.telegram_id = request.form.get('telegram_id', 'N/A')
            
            if Employee.query.filter_by(employee_code=employee.employee_code).filter(Employee.id != employee.id).first():
                flash('Código de empleado ya existe', 'error')
                return redirect(url_for('edit_employee', employee_id=employee_id))
            
            db.session.commit()
            flash('Empleado actualizado correctamente', 'success')
            log_action(current_user.id, 'edit_employee', f"Empleado {employee.name} actualizado")
            return redirect(url_for('manage_employees'))
        
        return render_template('edit_employee.html', employee=employee)
    except Exception as e:
        logger.error(f"Error en edit_employee: {e}")
        flash('Error al editar empleado', 'error')
        return redirect(url_for('manage_employees'))

@app.route('/admin/employees/toggle/<int:employee_id>', methods=['POST'])
@login_required
def toggle_employee(employee_id):
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        
        employee = Employee.query.get_or_404(employee_id)
        employee.is_active = not employee.is_active
        
        if not employee.is_active:
            tasks = Task.query.filter_by(assigned_to_id=employee.id, status='asignada').all()
            available_workers = Employee.query.filter(
                Employee.id != employee.id,
                Employee.is_active == True,
                Employee.role == 'worker'
            ).all()
            
            if tasks and available_workers:
                for task in tasks:
                    new_assignee = random.choice(available_workers)
                    task.assigned_to_id = new_assignee.id
                    if new_assignee.telegram_id != 'N/A':
                        message = f"📋 TAREA REASIGNADA\n\nLa tarea '{task.description}' ha sido reasignada a usted debido a que {employee.name} ha sido desactivado."
                        Thread(target=send_telegram_message, args=(new_assignee.telegram_id, message)).start()
        
        db.session.commit()
        flash(f"Empleado {'activado' if employee.is_active else 'desactivado'} correctamente", 'success')
        log_action(current_user.id, 'toggle_employee', f"Empleado {employee.name} {'activado' if employee.is_active else 'desactivado'}")
        return redirect(url_for('manage_employees'))
    except Exception as e:
        logger.error(f"Error en toggle_employee: {e}")
        flash('Error al cambiar estado del empleado', 'error')
        return redirect(url_for('manage_employees'))

@app.route('/admin/employees')
@login_required
def manage_employees():
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        employees = Employee.query.order_by(Employee.created_at.desc()).all()
        return render_template('manage_employees.html', employees=employees)
    except Exception as e:
        logger.error(f"Error en manage_employees: {e}")
        flash('Error al cargar empleados', 'error')
        return redirect(url_for('admin_dashboard'))

@app.route('/admin/tasks')
@login_required
def manage_tasks():
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        tasks = Task.query.order_by(Task.date_created.desc()).all()
        workers = Employee.query.filter_by(role='worker', is_active=True).all()
        return render_template('manage_tasks.html', tasks=tasks, workers=workers)
    except Exception as e:
        logger.error(f"Error en manage_tasks: {e}")
        flash('Error al cargar tareas', 'error')
        return redirect(url_for('admin_dashboard'))

@app.route('/admin/patana')
@login_required
def manage_patana():
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        recommendations = get_patana_recommendations()
        todays_assignments = get_todays_patana_assignments()
        return render_template('manage_patana.html', recommendations=recommendations, todays_assignments=todays_assignments)
    except Exception as e:
        logger.error(f"Error en manage_patana: {e}")
        flash('Error al cargar gestión de carrito', 'error')
        return redirect(url_for('admin_dashboard'))

@app.route('/admin/patana/assign', methods=['POST'])
@login_required
def assign_patana():
    try:
        if current_user.role not in ['admin', 'admin_principal']:
            flash('Acceso no autorizado', 'error')
            return redirect(url_for('admin_dashboard'))
        
        original_id = request.form.get('original_id')
        replacement_id = request.form.get('replacement_id')
        aisle = request.form.get('aisle')
        
        if not all([original_id, replacement_id, aisle]):
            flash('Todos los campos son requeridos', 'error')
            return redirect(url_for('manage_patana'))
        
        assignment = PatanaAssignment(
            date=date.today(),
            original_employee_id=original_id,
            replacement_employee_id=replacement_id,
            aisle=aisle,
            assigned_by_id=current_user.id
        )
        db.session.add(assignment)
        db.session.commit()
        
        original = Employee.query.get(original_id)
        replacement = Employee.query.get(replacement_id)
        
        message = f"📦 Hola {replacement.name},\n\nHoy te han asignado el carrito del pasillo {aisle} porque {original.name} tiene su día libre. También continuarás con tu carrito asignado. ¡Gracias por tu apoyo!"
        if replacement.telegram_id != 'N/A':
            send_telegram_message(replacement.telegram_id, message)
        flash(message, 'info')
        
        flash('Carrito asignado correctamente', 'success')
        log_action(current_user.id, 'assign_patana', f"Carrito {aisle} asignado a {replacement.name}")
        return redirect(url_for('manage_patana'))
    except Exception as e:
        logger.error(f"Error en assign_patana: {e}")
        flash('Error al asignar carrito', 'error')
        return redirect(url_for('manage_patana'))

def init_db():
    try:
        with app.app_context():
            db.create_all()
            if not Employee.query.filter_by(employee_code='291003').first():
                admin = Employee(
                    employee_code='291003',
                    name='Administrador Principal',
                    password_hash=generate_password_hash('admin2024'),
                    role='admin_principal',
                    aisle='N/A',
                    day_off='Sábado'
                )
                db.session.add(admin)
                db.session.commit()
                logger.info("Administrador principal creado")
    except Exception as e:
        logger.error(f"Error inicializando base de datos: {e}")
        raise

if __name__ == '__main__':
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
    os.makedirs(app.config['STATIC_FOLDER'], exist_ok=True)
    init_db()
    with app.app_context():
        auto_assign_team_task()
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Crear archivo CSS estático
echo "🎨 Creando estilos personalizados..."
sudo -u "$SERVICE_USER" bash -c "cat > static/styles.css" << 'EOF'
/* Estilos personalizados para Abarrote Panel - Azul, negro, gris, blanco, modo oscuro */
body {
    font-family: 'Inter', sans-serif;
    background-color: #111827;
    color: #f9fafb;
}

.sidebar {
    background-color: #1f2937;
    border-right: 1px solid #374151;
}

.sidebar a {
    transition: background-color 0.3s ease;
}

.sidebar a:hover {
    background-color: #374151;
}

.card {
    background-color: #1f2937;
    border-radius: 0.5rem;
    padding: 1rem;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}

button, input[type="submit"] {
    transition: background-color 0.3s ease;
    background-color: #3b82f6;
    color: #ffffff;
}

button:hover, input[type="submit"]:hover {
    background-color: #2563eb;
}

.alert-success {
    background-color: #22c55e;
}

.alert-error {
    background-color: #ef4444;
}

.alert-info {
    background-color: #3b82f6;
}

input, select, textarea {
    background-color: #374151;
    border: 1px solid #4b5563;
    color: #f9fafb;
}

input:focus, select:focus, textarea:focus {
    outline: none;
    border-color: #3b82f6;
    box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2);
}
EOF

# Template: base.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/base.html" << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Abarrote</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="{{ url_for('static', filename='styles.css') }}" rel="stylesheet">
    <script>
        function toggleSidebar() {
            document.getElementById('sidebar').classList.toggle('hidden');
        }
    </script>
</head>
<body class="flex min-h-screen">
    <aside id="sidebar" class="sidebar w-64 p-4 fixed h-full md:block hidden md:relative md:h-auto">
        <h1 class="text-2xl font-bold mb-6"><i class="fas fa-store mr-2"></i> Abarrote</h1>
        <nav>
            <ul>
                {% if current_user.is_authenticated %}
                    {% if current_user.role == 'worker' %}
                        <li><a href="{{ url_for('worker_dashboard') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-home mr-2"></i> Dashboard</a></li>
                    {% else %}
                        <li><a href="{{ url_for('admin_dashboard') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-home mr-2"></i> Dashboard</a></li>
                        <li><a href="{{ url_for('manage_tasks') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-tasks mr-2"></i> Tareas</a></li>
                        <li><a href="{{ url_for('manage_employees') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-users mr-2"></i> Empleados</a></li>
                        <li><a href="{{ url_for('manage_patana') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-shopping-cart mr-2"></i> Carrito</a></li>
                        {% if current_user.role == 'admin_principal' %}
                            <li><a href="{{ url_for('config') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-cog mr-2"></i> Configuración</a></li>
                        {% endif %}
                    {% endif %}
                    <li><a href="{{ url_for('profile') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-user mr-2"></i> Perfil</a></li>
                    <li><a href="{{ url_for('logout') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-sign-out-alt mr-2"></i> Cerrar Sesión</a></li>
                {% else %}
                    <li><a href="{{ url_for('login') }}" class="block p-2 hover:bg-gray-600 rounded"><i class="fas fa-sign-in-alt mr-2"></i> Iniciar Sesión</a></li>
                {% endif %}
            </ul>
        </nav>
    </aside>
    <main class="flex-1 p-6 md:ml-64">
        <button onclick="toggleSidebar()" class="md:hidden text-white p-2"><i class="fas fa-bars text-2xl"></i></button>
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                    <div class="alert-{{ category }} text-white p-4 rounded mb-4">
                        {{ message }}
                    </div>
                {% endfor %}
            {% endif %}
        {% endwith %}
        {% block content %}{% endblock %}
    </main>
</body>
</html>
EOF

# Template: login.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/login.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="max-w-md mx-auto card mt-20">
    <h2 class="text-2xl font-bold mb-4 text-center"><i class="fas fa-store mr-2"></i> Abarrote - Iniciar Sesión</h2>
    <form method="POST" action="{{ url_for('login') }}">
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="employee_code">Código de Empleado</label>
            <input type="text" id="employee_code" name="employee_code" class="w-full p-2 rounded" required>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="password">Contraseña</label>
            <input type="password" id="password" name="password" class="w-full p-2 rounded" required>
        </div>
        <button type="submit" class="w-full bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-sign-in-alt mr-2"></i> Iniciar Sesión</button>
    </form>
</div>
{% endblock %}
EOF

# Template: profile.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/profile.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-2xl font-bold mb-4">Perfil - {{ user.name }}</h2>
<div class="card">
    <form method="POST" action="{{ url_for('profile') }}">
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="name">Nombre</label>
            <input type="text" id="name" name="name" class="w-full p-2 rounded" value="{{ user.name }}" required>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="aisle">Pasillo</label>
            <input type="text" id="aisle" name="aisle" class="w-full p-2 rounded" value="{{ user.aisle }}">
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="day_off">Día de Descanso</label>
            <select id="day_off" name="day_off" class="w-full p-2 rounded">
                <option value="Lunes" {% if user.day_off == 'Lunes' %}selected{% endif %}>Lunes</option>
                <option value="Martes" {% if user.day_off == 'Martes' %}selected{% endif %}>Martes</option>
                <option value="Miércoles" {% if user.day_off == 'Miércoles' %}selected{% endif %}>Miércoles</option>
                <option value="Jueves" {% if user.day_off == 'Jueves' %}selected{% endif %}>Jueves</option>
                <option value="Viernes" {% if user.day_off == 'Viernes' %}selected{% endif %}>Viernes</option>
                <option value="Sábado" {% if user.day_off == 'Sábado' %}selected{% endif %}>Sábado</option>
                <option value="Domingo" {% if user.day_off == 'Domingo' %}selected{% endif %}>Domingo</option>
            </select>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="telegram_id">ID de Telegram</label>
            <input type="text" id="telegram_id" name="telegram_id" class="w-full p-2 rounded" value="{{ user.telegram_id }}">
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="password">Nueva Contraseña (dejar en blanco para no cambiar)</label>
            <input type="password" id="password" name="password" class="w-full p-2 rounded">
        </div>
        <button type="submit" class="w-full bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-save mr-2"></i> Guardar Cambios</button>
    </form>
</div>
{% endblock %}
EOF

# Template: worker_dashboard.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/worker_dashboard.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-2xl font-bold mb-4">Dashboard - {{ user.name }}</h2>
<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
    <div class="card">
        <h3 class="text-lg font-semibold mb-2"><i class="fas fa-tasks mr-2"></i> Tareas Pendientes</h3>
        {% if pending_tasks %}
            <ul class="space-y-2">
                {% for task in pending_tasks %}
                    <li class="bg-gray-700 p-3 rounded">
                        <p><strong>{{ task.description }}</strong></p>
                        <p>Prioridad: {{ task.priority | capitalize }}</p>
                        <p>Estado: {{ task.status | capitalize }}</p>
                        {% if task.due_date %}
                            <p>Vence: {{ task.due_date.strftime('%d/%m/%Y %H:%M') }}</p>
                        {% endif %}
                        {% if task.requires_photo %}
                            <p><i class="fas fa-camera mr-2"></i> Requiere foto</p>
                        {% endif %}
                        <a href="{{ url_for('complete_task', task_id=task.id) }}" class="text-blue-400 hover:underline"><i class="fas fa-check mr-2"></i> Completar</a>
                    </li>
                {% endfor %}
            </ul>
        {% else %}
            <p>No hay tareas pendientes</p>
        {% endif %}
    </div>
    <div class="card">
        <h3 class="text-lg font-semibold mb-2"><i class="fas fa-users mr-2"></i> Compañeros de Pasillo</h3>
        {% if aisle_mates %}
            <ul class="space-y-2">
                {% for mate in aisle_mates %}
                    <li>{{ mate.name }} (Pasillo {{ mate.aisle }})</li>
                {% endfor %}
            </ul>
        {% else %}
            <p>No hay compañeros en tu pasillo</p>
        {% endif %}
    </div>
    {% if todays_team_task and user_in_team_task %}
        <div class="card col-span-2">
            <h3 class="text-lg font-semibold mb-2"><i class="fas fa-shopping-cart mr-2"></i> Tarea de Carrito Hoy</h3>
            <p><strong>{{ todays_team_task.description }}</strong></p>
            <p>Compañero: {{ todays_team_task.employee2.name if user.id == todays_team_task.employee1.id else todays_team_task.employee1.name }}</p>
            <p>Hora: {{ todays_team_task.execution_time.strftime('%H:%M') }}</p>
        </div>
    {% endif %}
</div>
{% endblock %}
EOF

# Template: admin_dashboard.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/admin_dashboard.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-2xl font-bold mb-4">Dashboard Administrativo</h2>
<div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
    <div class="card">
        <h3 class="text-lg font-semibold"><i class="fas fa-users mr-2"></i> Total Empleados</h3>
        <p class="text-2xl">{{ stats.total_employees }}</p>
    </div>
    <div class="card">
        <h3 class="text-lg font-semibold"><i class="fas fa-tasks mr-2"></i> Tareas Pendientes</h3>
        <p class="text-2xl">{{ stats.pending_tasks }}</p>
    </div>
    <div class="card">
        <h3 class="text-lg font-semibold"><i class="fas fa-check-circle mr-2"></i> Tareas Completadas</h3>
        <p class="text-2xl">{{ stats.completed_tasks }}</p>
    </div>
</div>
<div class="mb-6">
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-shopping-cart mr-2"></i> Carritos Asignados Hoy</h3>
    {% if todays_patana_assignments %}
        <ul class="space-y-2">
            {% for assignment in todays_patana_assignments %}
                <li class="bg-gray-700 p-3 rounded">
                    <p>{{ assignment.original_employee.name }} reemplazado por {{ assignment.replacement_employee.name }} en Pasillo {{ assignment.aisle }}</p>
                </li>
            {% endfor %}
        </ul>
    {% else %}
        <p>No hay asignaciones de carrito para hoy</p>
    {% endif %}
</div>
<div class="mb-6">
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-lightbulb mr-2"></i> Recomendaciones de Carrito</h3>
    {% if patana_recommendations %}
        <ul class="space-y-2">
            {% for rec in patana_recommendations %}
                <li class="bg-gray-700 p-3 rounded">
                    <p><strong>{{ rec.employee_off.name }}</strong> está de descanso (Pasillo {{ rec.aisle_to_cover }})</p>
                    <p>Reemplazos sugeridos: {{ rec.available_workers | map(attribute='name') | join(', ') }}</p>
                </li>
            {% endfor %}
        </ul>
    {% else %}
        <p>No hay recomendaciones de carrito</p>
    {% endif %}
</div>
<div>
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-tasks mr-2"></i> Tareas Recientes</h3>
    {% if tasks %}
        <ul class="space-y-2">
            {% for task in tasks | sort(attribute='date_created', reverse=True) %}
                <li class="bg-gray-700 p-3 rounded">
                    <p><strong>{{ task.description }}</strong></p>
                    <p>Asignada a: {{ task.assigned_to.name }}</p>
                    <p>Estado: {{ task.status | capitalize }}</p>
                    {% if task.due_date %}
                        <p>Vence: {{ task.due_date.strftime('%d/%m/%Y %H:%M') }}</p>
                    {% endif %}
                    {% if task.requires_photo %}
                        <p><i class="fas fa-camera mr-2"></i> Requiere foto</p>
                    {% endif %}
                </li>
            {% endfor %}
        </ul>
    {% else %}
        <p>No hay tareas recientes</p>
    {% endif %}
</div>
{% endblock %}
EOF

# Template: complete_task.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/complete_task.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="max-w-md mx-auto card">
    <h2 class="text-2xl font-bold mb-4">Completar Tarea</h2>
    <p><strong>{{ task.description }}</strong></p>
    <p>Prioridad: {{ task.priority | capitalize }}</p>
    {% if task.due_date %}
        <p>Vence: {{ task.due_date.strftime('%d/%m/%Y %H:%M') }}</p>
    {% endif %}
    <form method="POST" enctype="multipart/form-data">
        {% if task.requires_photo %}
            <div class="mb-4">
                <label class="block text-sm font-medium mb-2" for="photo">Subir Foto</label>
                <input type="file" id="photo" name="photo" accept="image/*" capture="camera" class="w-full p-2 rounded" required>
            </div>
        {% endif %}
        <button type="submit" class="w-full bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-check mr-2"></i> Marcar como Completada</button>
    </form>
</div>
{% endblock %}
EOF

# Template: manage_tasks.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/manage_tasks.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-2xl font-bold mb-4">Gestionar Tareas</h2>
<div class="mb-6 card">
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-plus-circle mr-2"></i> Asignar Nueva Tarea</h3>
    <form method="POST" action="{{ url_for('add_task') }}">
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="description">Descripción</label>
            <textarea id="description" name="description" class="w-full p-2 rounded" required></textarea>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="employee_id">Asignar a</label>
            <select id="employee_id" name="employee_id" multiple class="w-full p-2 rounded" required>
                {% for worker in workers %}
                    <option value="{{ worker.id }}">{{ worker.name }} (Pasillo {{ worker.aisle }})</option>
                {% endfor %}
            </select>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="priority">Prioridad</label>
            <select id="priority" name="priority" class="w-full p-2 rounded">
                <option value="baja">Baja</option>
                <option value="media" selected>Media</option>
                <option value="alta">Alta</option>
            </select>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2"><input type="checkbox" name="is_patana"> Es tarea de carrito</label>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2"><input type="checkbox" name="requires_photo"> Requiere foto</label>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="due_date">Fecha de Vencimiento</label>
            <input type="date" id="due_date" name="due_date" class="w-full p-2 rounded">
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="due_time">Hora de Vencimiento</label>
            <input type="time" id="due_time" name="due_time" class="w-full p-2 rounded">
        </div>
        <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-plus mr-2"></i> Asignar Tarea</button>
    </form>
</div>
<div>
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-tasks mr-2"></i> Tareas Activas</h3>
    {% if tasks %}
        <ul class="space-y-2">
            {% for task in tasks %}
                <li class="bg-gray-700 p-3 rounded">
                    <p><strong>{{ task.description }}</strong></p>
                    <p>Asignada a: {{ task.assigned_to.name }}</p>
                    <p>Estado: {{ task.status | capitalize }}</p>
                    {% if task.due_date %}
                        <p>Vence: {{ task.due_date.strftime('%d/%m/%Y %H:%M') }}</p>
                    {% endif %}
                    {% if task.requires_photo %}
                        <p><i class="fas fa-camera mr-2"></i> Requiere foto</p>
                    {% endif %}
                </li>
            {% endfor %}
        </ul>
    {% else %}
        <p>No hay tareas activas</p>
    {% endif %}
</div>
{% endblock %}
EOF

# Template: manage_employees.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/manage_employees.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-2xl font-bold mb-4">Gestionar Empleados</h2>
<div class="mb-6 card">
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-user-plus mr-2"></i> Agregar Empleado</h3>
    <form method="POST" action="{{ url_for('add_employee') }}">
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="name">Nombre</label>
            <input type="text" id="name" name="name" class="w-full p-2 rounded" required>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="employee_code">Código de Empleado</label>
            <input type="text" id="employee_code" name="employee_code" class="w-full p-2 rounded" required>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="password">Contraseña</label>
            <input type="password" id="password" name="password" class="w-full p-2 rounded" required>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="role">Rol</label>
            <select id="role" name="role" class="w-full p-2 rounded">
                <option value="worker">Trabajador</option>
                <option value="admin">Administrador</option>
                {% if current_user.role == 'admin_principal' %}
                    <option value="admin_principal">Administrador Principal</option>
                {% endif %}
            </select>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="aisle">Pasillo</label>
            <input type="text" id="aisle" name="aisle" class="w-full p-2 rounded" value="1">
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="day_off">Día de Descanso</label>
            <select id="day_off" name="day_off" class="w-full p-2 rounded">
                <option value="Lunes">Lunes</option>
                <option value="Martes">Martes</option>
                <option value="Miércoles">Miércoles</option>
                <option value="Jueves">Jueves</option>
                <option value="Viernes">Viernes</option>
                <option value="Sábado">Sábado</option>
                <option value="Domingo" selected>Domingo</option>
            </select>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="telegram_id">ID de Telegram</label>
            <input type="text" id="telegram_id" name="telegram_id" class="w-full p-2 rounded" value="N/A">
        </div>
        <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-plus mr-2"></i> Agregar Empleado</button>
    </form>
</div>
<div>
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-users mr-2"></i> Lista de Empleados</h3>
    {% if employees %}
        <ul class="space-y-2">
            {% for emp in employees %}
                <li class="bg-gray-700 p-3 rounded flex justify-between items-center">
                    <div>
                        <p><strong>{{ emp.name }}</strong> ({{ emp.employee_code }})</p>
                        <p>Rol: {{ emp.role | capitalize }}</p>
                        <p>Pasillo: {{ emp.aisle }}</p>
                        <p>Día de descanso: {{ emp.day_off }}</p>
                        <p>ID Telegram: {{ emp.telegram_id }}</p>
                        <p>Estado: {{ 'Activo' if emp.is_active else 'Inactivo' }}</p>
                    </div>
                    <div>
                        <a href="{{ url_for('edit_employee', employee_id=emp.id) }}" class="text-blue-400 hover:underline"><i class="fas fa-edit mr-2"></i> Editar</a>
                        <form method="POST" action="{{ url_for('toggle_employee', employee_id=emp.id) }}" class="inline">
                            <button type="submit" class="text-{{ 'red' if emp.is_active else 'green' }}-400 hover:underline">
                                <i class="fas fa-{{ 'ban' if emp.is_active else 'check' }} mr-2"></i> {{ 'Desactivar' if emp.is_active else 'Activar' }}
                            </button>
                        </form>
                    </div>
                </li>
            {% endfor %}
        </ul>
    {% else %}
        <p>No hay empleados registrados</p>
    {% endif %}
</div>
{% endblock %}
EOF

# Template: edit_employee.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/edit_employee.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="max-w-md mx-auto card">
    <h2 class="text-2xl font-bold mb-4">Editar Empleado</h2>
    <form method="POST" action="{{ url_for('edit_employee', employee_id=employee.id) }}">
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="name">Nombre</label>
            <input type="text" id="name" name="name" class="w-full p-2 rounded" value="{{ employee.name }}" required>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="employee_code">Código de Empleado</label>
            <input type="text" id="employee_code" name="employee_code" class="w-full p-2 rounded" value="{{ employee.employee_code }}" required>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="password">Nueva Contraseña (dejar en blanco para no cambiar)</label>
            <input type="password" id="password" name="password" class="w-full p-2 rounded">
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="role">Rol</label>
            <select id="role" name="role" class="w-full p-2 rounded">
                <option value="worker" {% if employee.role == 'worker' %}selected{% endif %}>Trabajador</option>
                <option value="admin" {% if employee.role == 'admin' %}selected{% endif %}>Administrador</option>
                {% if current_user.role == 'admin_principal' %}
                    <option value="admin_principal" {% if employee.role == 'admin_principal' %}selected{% endif %}>Administrador Principal</option>
                {% endif %}
            </select>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="aisle">Pasillo</label>
            <input type="text" id="aisle" name="aisle" class="w-full p-2 rounded" value="{{ employee.aisle }}">
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="day_off">Día de Descanso</label>
            <select id="day_off" name="day_off" class="w-full p-2 rounded">
                <option value="Lunes" {% if employee.day_off == 'Lunes' %}selected{% endif %}>Lunes</option>
                <option value="Martes" {% if employee.day_off == 'Martes' %}selected{% endif %}>Martes</option>
                <option value="Miércoles" {% if employee.day_off == 'Miércoles' %}selected{% endif %}>Miércoles</option>
                <option value="Jueves" {% if employee.day_off == 'Jueves' %}selected{% endif %}>Jueves</option>
                <option value="Viernes" {% if employee.day_off == 'Viernes' %}selected{% endif %}>Viernes</option>
                <option value="Sábado" {% if employee.day_off == 'Sábado' %}selected{% endif %}>Sábado</option>
                <option value="Domingo" {% if employee.day_off == 'Domingo' %}selected{% endif %}>Domingo</option>
            </select>
        </div>
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2" for="telegram_id">ID de Telegram</label>
            <input type="text" id="telegram_id" name="telegram_id" class="w-full p-2 rounded" value="{{ employee.telegram_id }}">
        </div>
        <button type="submit" class="w-full bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-save mr-2"></i> Guardar Cambios</button>
    </form>
</div>
{% endblock %}
EOF

# Template: config.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/config.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-2xl font-bold mb-4">Configuración</h2>
<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
    <div class="card">
        <h3 class="text-lg font-semibold mb-2"><i class="fas fa-robot mr-2"></i> Token de Telegram Actual</h3>
        <p class="p-2 bg-gray-700 rounded">{{ token }}</p>
        <h3 class="text-lg font-semibold mb-2 mt-4"><i class="fas fa-robot mr-2"></i> Actualizar Token de Telegram</h3>
        <form method="POST" action="{{ url_for('update_token') }}">
            <div class="mb-4">
                <label class="block text-sm font-medium mb-2" for="token">Token del Bot</label>
                <input type="text" id="token" name="token" class="w-full p-2 rounded" required>
            </div>
            <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-save mr-2"></i> Actualizar</button>
        </form>
    </div>
    <div class="card">
        <h3 class="text-lg font-semibold mb-2"><i class="fas fa-download mr-2"></i> Backup Manual</h3>
        <form method="POST" action="{{ url_for('manual_backup') }}">
            <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-download mr-2"></i> Generar Backup</button>
        </form>
    </div>
    <div class="card">
        <h3 class="text-lg font-semibold mb-2"><i class="fas fa-upload mr-2"></i> Restaurar Backup</h3>
        <form method="POST" action="{{ url_for('restore_backup') }}" enctype="multipart/form-data">
            <div class="mb-4">
                <label class="block text-sm font-medium mb-2" for="backup_file">Archivo de Backup</label>
                <input type="file" id="backup_file" name="backup_file" class="w-full p-2 rounded" required>
            </div>
            <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-upload mr-2"></i> Restaurar</button>
        </form>
    </div>
    <div class="card">
        <h3 class="text-lg font-semibold mb-2"><i class="fas fa-globe mr-2"></i> Configurar Dominio</h3>
        <form method="POST" action="{{ url_for('set_domain') }}">
            <div class="mb-4">
                <label class="block text-sm font-medium mb-2" for="domain">Dominio</label>
                <input type="text" id="domain" name="domain" class="w-full p-2 rounded" placeholder="ejemplo.com" required>
            </div>
            <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-save mr-2"></i> Configurar</button>
        </form>
    </div>
</div>
{% endblock %}
EOF

# Template: manage_patana.html
sudo -u "$SERVICE_USER" bash -c "cat > templates/manage_patana.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-2xl font-bold mb-4">Gestionar Carrito</h2>
<div class="mb-6 card">
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-shopping-cart mr-2"></i> Recomendaciones de Carrito para Hoy</h3>
    {% if recommendations %}
        <ul class="space-y-2">
            {% for rec in recommendations %}
                <li class="bg-gray-700 p-3 rounded">
                    <p><strong>{{ rec.employee_off.name }}</strong> está de descanso (Pasillo {{ rec.aisle_to_cover }})</p>
                    <p>Reemplazos sugeridos:</p>
                    <form method="POST" action="{{ url_for('assign_patana') }}">
                        <input type="hidden" name="original_id" value="{{ rec.employee_off.id }}">
                        <input type="hidden" name="aisle" value="{{ rec.aisle_to_cover }}">
                        <select name="replacement_id" class="w-full p-2 rounded mb-2">
                            {% for worker in rec.available_workers %}
                                <option value="{{ worker.id }}">{{ worker.name }} (Pasillo {{ worker.aisle }})</option>
                            {% endfor %}
                        </select>
                        <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded"><i class="fas fa-shopping-cart mr-2"></i> Asignar</button>
                    </form>
                </li>
            {% endfor %}
        </ul>
    {% else %}
        <p>No hay recomendaciones de carrito</p>
    {% endif %}
</div>
<div>
    <h3 class="text-lg font-semibold mb-2"><i class="fas fa-shopping-cart mr-2"></i> Carritos Asignados Hoy</h3>
    {% if todays_assignments %}
        <ul class="space-y-2">
            {% for assignment in todays_assignments %}
                <li class="bg-gray-700 p-3 rounded">
                    <p>{{ assignment.original_employee.name }} reemplazado por {{ assignment.replacement_employee.name }} en Pasillo {{ assignment.aisle }}</p>
                </li>
            {% endfor %}
        </ul>
    {% else %}
        <p>No hay asignaciones de carrito para hoy</p>
    {% endif %}
</div>
{% endblock %}
EOF

# Configurar Gunicorn
echo "⚙️ Configurando Gunicorn..."
sudo -u "$SERVICE_USER" bash -c "cat > gunicorn_config.py" << 'EOF'
bind = "0.0.0.0:5000"
workers = 4
threads = 4
timeout = 120
EOF

# Configurar servicio systemd
echo "🔄 Configurando servicio systemd..."
sudo bash -c "cat > /etc/systemd/system/abarrote-panel.service" << 'EOF'
[Unit]
Description=Abarrote Panel Flask Application
After=network.target

[Service]
User=paneluser
Group=paneluser
WorkingDirectory=/opt/abarrote-panel
ExecStart=/opt/abarrote-panel/venv/bin/gunicorn --config /opt/abarrote-panel/gunicorn_config.py app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable abarrote-panel
sudo systemctl start abarrote-panel || { echo "Error iniciando servicio abarrote-panel"; sudo journalctl -u abarrote-panel -n 20; exit 1; }

# Configurar Nginx
echo "🌐 Configurando Nginx..."
sudo rm -f "$NGINX_DEFAULT"
sudo bash -c "cat > $NGINX_CONF" << 'EOF'
server {
    listen 80;
    server_name _;

    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /static/ {
        alias /opt/abarrote-panel/static/;
    }

    location /uploads/ {
        alias /opt/abarrote-panel/uploads/;
    }
}
EOF

sudo ln -sf "$NGINX_CONF" "$NGINX_LINK"
sudo nginx -t || { echo "Error en la configuración de Nginx"; exit 1; }
sudo systemctl restart nginx || { echo "Error reiniciando Nginx"; exit 1; }

# Inicializar base de datos
echo "🗄️ Inicializando base de datos..."
sudo -u "$SERVICE_USER" bash -c "
    source venv/bin/activate
    python -c 'from app import init_db; init_db()' || { echo 'Error inicializando base de datos'; exit 1; }
"

# Verificar permisos de la base de datos
sudo chown "$SERVICE_USER:$SERVICE_USER" "$DB_PATH"
sudo chmod 664 "$DB_PATH"

# Verificar estado del servicio
echo "🔍 Verificando estado del servicio..."
sudo systemctl status abarrote-panel --no-pager || true
sudo systemctl status nginx --no-pager || true

# Resumen
echo "=================================================="
echo "    INSTALACIÓN COMPLETADA"
echo "=================================================="
echo
echo "✅ Abarrote Panel instalado en: $PANEL_DIR"
echo "🌐 Acceso: http://<IP_DEL_SERVIDOR>"
echo "👤 Credenciales iniciales:"
echo "   - Código: 291003"
echo "   - Contraseña: admin2024"
echo
echo "📌 Configurar Telegram Bot:"
echo "1. Crear bot con @BotFather y obtener token"
echo "2. Iniciar sesión como admin y actualizar token en Configuración"
echo "3. Usar /start en el bot para obtener ID de Telegram (se envía al admin)"
echo "4. Registrar IDs en la sección de Empleados"
echo
echo "🔐 Para habilitar HTTPS:"
echo "1. Configurar dominio en la sección Configuración"
echo "2. Certbot se aplicará automáticamente"
echo
echo "📅 Tareas automáticas:"
echo "- Limpieza de tareas completadas: 03:00 AM"
echo "- Backup automático: 04:00 AM"
echo "- Tarea Monta Carga: 5:40 PM"
echo
echo "📜 Logs en: /opt/abarrote-panel/app.log y /opt/abarrote-panel/employees.db (tabla Log)"
echo "=================================================="