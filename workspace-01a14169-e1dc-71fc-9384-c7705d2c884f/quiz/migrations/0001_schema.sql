-- Cloudflare D1 schema and starter quizzes. No API keys or personal results.
CREATE TABLE IF NOT EXISTS quizzes (
 id TEXT PRIMARY KEY, title TEXT NOT NULL, emoji TEXT, category TEXT,
 description TEXT, image TEXT, plays INTEGER DEFAULT 0,
 created TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS sessions (
 id TEXT PRIMARY KEY, quiz_id TEXT NOT NULL, history TEXT NOT NULL, result TEXT
);
CREATE INDEX IF NOT EXISTS sessions_quiz_idx ON sessions(quiz_id);
INSERT OR IGNORE INTO quizzes(id,title,emoji,category,description,image) VALUES('cat','Сколько в тебе котов?','🐈','ЖИЗА','Измерим твою внутреннюю пушистость. Научно? Нет. Точно? Мяу.','cat.jpg');
INSERT OR IGNORE INTO quizzes(id,title,emoji,category,description,image) VALUES('forest','Кто ты в волшебном лесу?','🧚','ФЭНТЕЗИ','Кажется, у старого дуба есть для тебя послание.','forest.jpg');
INSERT OR IGNORE INTO quizzes(id,title,emoji,category,description,image) VALUES('genshin','Кто ты из Genshin Impact?','✦','ФАНДОМЫ','Твой элемент, твой характер, твоя история в Тейвате.','flowers.jpg');
INSERT OR IGNORE INTO quizzes(id,title,emoji,category,description,image) VALUES('gnome','Какой ты гном?','🍄','ФЭНТЕЗИ','Лесной мудрец или любитель блестящих камушков?','forest.jpg');
INSERT OR IGNORE INTO quizzes(id,title,emoji,category,description,image) VALUES('planet','Какая ты планета?','🪐','КОСМОС','У каждого своя орбита. Давай найдём твою.','space.jpg');
INSERT OR IGNORE INTO quizzes(id,title,emoji,category,description,image) VALUES('sea','Какое ты море?','🐚','ПРО СЕБЯ','Штиль снаружи, целый океан внутри. Или наоборот?','sea.jpg');
