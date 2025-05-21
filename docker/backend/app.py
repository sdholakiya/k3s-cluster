from flask import Flask, jsonify, request
import os
import psycopg2
import logging
from datetime import datetime
import json
import time
from prometheus_client import Counter, generate_latest, REGISTRY

app = Flask(__name__)

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logging.basicConfig(level=getattr(logging, log_level),
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('request_count', 'App Request Count', ['method', 'endpoint', 'status'])
DB_REQUEST_COUNT = Counter('db_request_count', 'Database Request Count', ['operation', 'status'])

# Database connection parameters
db_params = {
    'dbname': os.environ.get('POSTGRES_DB', 'app_database'),
    'user': os.environ.get('POSTGRES_USER', 'postgres'),
    'password': os.environ.get('POSTGRES_PASSWORD', 'postgres'),
    'host': os.environ.get('DATABASE_URL', 'database').split('://')[1].split(':')[0] if '://' in os.environ.get('DATABASE_URL', 'database') else os.environ.get('DATABASE_URL', 'database'),
    'port': 5432
}

def get_db_connection():
    """Create a database connection"""
    try:
        logger.info("Connecting to database...")
        conn = psycopg2.connect(**db_params)
        DB_REQUEST_COUNT.labels('connect', 'success').inc()
        return conn
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        DB_REQUEST_COUNT.labels('connect', 'error').inc()
        return None

def initialize_db():
    """Create tables if they don't exist"""
    conn = get_db_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute('''
                    CREATE TABLE IF NOT EXISTS items (
                        id SERIAL PRIMARY KEY,
                        name VARCHAR(100) NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                ''')
                cur.execute('''
                    CREATE TABLE IF NOT EXISTS logs (
                        id SERIAL PRIMARY KEY,
                        message TEXT NOT NULL,
                        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                ''')
                conn.commit()
                logger.info("Database initialized successfully")
                DB_REQUEST_COUNT.labels('initialize', 'success').inc()
        except Exception as e:
            logger.error(f"Database initialization error: {e}")
            DB_REQUEST_COUNT.labels('initialize', 'error').inc()
        finally:
            conn.close()

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(REGISTRY)

@app.route('/api/items', methods=['GET'])
def get_items():
    """Get all items from the database"""
    try:
        conn = get_db_connection()
        if not conn:
            REQUEST_COUNT.labels('GET', '/api/items', 500).inc()
            return jsonify({'error': 'Database connection failed'}), 500
        
        with conn.cursor() as cur:
            cur.execute('SELECT * FROM items ORDER BY created_at DESC')
            items = cur.fetchall()
            
        conn.close()
        
        # Format the response
        formatted_items = [{'id': item[0], 'name': item[1], 'created_at': item[2].isoformat()} for item in items]
        
        # Log communication with database
        logger.info(f"Retrieved {len(formatted_items)} items from database")
        
        # Record metrics
        REQUEST_COUNT.labels('GET', '/api/items', 200).inc()
        DB_REQUEST_COUNT.labels('select', 'success').inc()
        
        return jsonify({'items': formatted_items})
    except Exception as e:
        logger.error(f"Error retrieving items: {e}")
        REQUEST_COUNT.labels('GET', '/api/items', 500).inc()
        return jsonify({'error': str(e)}), 500

@app.route('/api/items', methods=['POST'])
def create_item():
    """Create a new item in the database"""
    try:
        data = request.json
        if not data or 'name' not in data:
            REQUEST_COUNT.labels('POST', '/api/items', 400).inc()
            return jsonify({'error': 'Name is required'}), 400
        
        conn = get_db_connection()
        if not conn:
            REQUEST_COUNT.labels('POST', '/api/items', 500).inc()
            return jsonify({'error': 'Database connection failed'}), 500
        
        with conn.cursor() as cur:
            cur.execute('INSERT INTO items (name) VALUES (%s) RETURNING id', (data['name'],))
            item_id = cur.fetchone()[0]
            conn.commit()
        
        conn.close()
        
        # Log communication with database
        logger.info(f"Created new item with ID {item_id}")
        
        # Record metrics
        REQUEST_COUNT.labels('POST', '/api/items', 201).inc()
        DB_REQUEST_COUNT.labels('insert', 'success').inc()
        
        return jsonify({'id': item_id, 'name': data['name']}), 201
    except Exception as e:
        logger.error(f"Error creating item: {e}")
        REQUEST_COUNT.labels('POST', '/api/items', 500).inc()
        return jsonify({'error': str(e)}), 500

@app.route('/api/log', methods=['POST'])
def log_message():
    """Log a message to the database"""
    try:
        data = request.json
        if not data or 'message' not in data:
            REQUEST_COUNT.labels('POST', '/api/log', 400).inc()
            return jsonify({'error': 'Message is required'}), 400
        
        conn = get_db_connection()
        if not conn:
            REQUEST_COUNT.labels('POST', '/api/log', 500).inc()
            return jsonify({'error': 'Database connection failed'}), 500
        
        with conn.cursor() as cur:
            cur.execute('INSERT INTO logs (message) VALUES (%s) RETURNING id', (data['message'],))
            log_id = cur.fetchone()[0]
            conn.commit()
        
        conn.close()
        
        # Log communication
        logger.info(f"Logged message with ID {log_id}")
        
        # Record metrics
        REQUEST_COUNT.labels('POST', '/api/log', 201).inc()
        DB_REQUEST_COUNT.labels('insert', 'success').inc()
        
        return jsonify({'id': log_id, 'message': data['message']}), 201
    except Exception as e:
        logger.error(f"Error logging message: {e}")
        REQUEST_COUNT.labels('POST', '/api/log', 500).inc()
        return jsonify({'error': str(e)}), 500

# Initialize the database when the application starts
@app.before_first_request
def before_first_request():
    """Initialize the database before the first request"""
    initialize_db()

if __name__ == '__main__':
    # Retry database connection a few times before giving up
    # This helps when the database container is still starting up
    max_retries = 5
    for i in range(max_retries):
        try:
            initialize_db()
            break
        except Exception as e:
            if i < max_retries - 1:
                logger.warning(f"Database initialization attempt {i+1} failed, retrying in 5 seconds...")
                time.sleep(5)
            else:
                logger.error(f"Failed to initialize database after {max_retries} attempts")
    
    # Start the Flask application
    app.run(host='0.0.0.0', port=8080)