-- Initialize database with sample data

-- Create items table if it doesn't exist
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create logs table if it doesn't exist
CREATE TABLE IF NOT EXISTS logs (
    id SERIAL PRIMARY KEY,
    message TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert some sample data
INSERT INTO items (name) VALUES ('Sample Item 1');
INSERT INTO items (name) VALUES ('Sample Item 2');
INSERT INTO items (name) VALUES ('Sample Item 3');

-- Insert a log entry
INSERT INTO logs (message) VALUES ('Database initialized with sample data');