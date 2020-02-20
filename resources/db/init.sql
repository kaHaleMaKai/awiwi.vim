PRAGMA foreign_keys = 1;
-- sqlite supports ddls inside of transactions

BEGIN;

CREATE TABLE task_state (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX task_state_name ON task_state (name);

CREATE TABLE task_log_state (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX task_log_state_name ON task_log_state (name);

CREATE TABLE urgency (
  `id` int NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `value` int unsigned NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
  -- CHECK (`name` BETWEEN 'a' AND 'z'),
  -- CHECK (`value` BETWEEN 0 AND 10)
);
CREATE UNIQUE INDEX urgency_name ON urgency (name);

CREATE TABLE project (
  `id` int NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `url` varchar(255),
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
  -- CHECK (`name` BETWEEN 'a' AND 'z')
);
CREATE UNIQUE INDEX project_name ON project (name);

CREATE TABLE tag (
  `id` int NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
  -- CHECK (`name` BETWEEN 'a' AND 'z')
);
CREATE UNIQUE INDEX tag_name ON tag (name);

CREATE TABLE task (
  `id` int NOT NULL PRIMARY KEY,
  `title` varchar(255) NOT NULL,
  `task_state_id` varchar(255) NOT NULL,
  `date` date NOT NULL,
  `start` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `end` timestamp DEFAULT NULL,
  `backlink` integer DEFAULT NULL,
  `forwardlink` integer DEFAULT NULL,
  `project_id` integer,
  `issue_link` varchar(255),
  `urgency_id` int unsigned NOT NULL,
  `updated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `duration` int unsigned NOT NULL DEFAULT '0',
  -- CHECK (`state` IN ('started', 'paused', 'done')),
  FOREIGN KEY (`urgency_id`) REFERENCES urgency(`id`),
  FOREIGN KEY (`project_id`) REFERENCES project(`id`),
  FOREIGN KEY (`task_state_id`) REFERENCES task_state(`id`)
);
CREATE UNIQUE INDEX task_title ON task (title, date);

CREATE TABLE task_tags (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `task_id` int NOT NULL,
  `tag_id` int NOT NULL,
  FOREIGN KEY (`task_id`) REFERENCES task(`id`),
  FOREIGN KEY (`tag_id`) REFERENCES tag(`id`)
);

CREATE TRIGGER update_task_timestamp
  AFTER UPDATE
  ON task
FOR EACH ROW
BEGIN
  UPDATE task
  SET
    updated = CURRENT_TIMESTAMP
  WHERE
    new.id = old.id;
END;

CREATE TABLE setting (
  `id` int NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `value` varchar(255)
);
CREATE UNIQUE INDEX setting_name ON setting (name);

CREATE TABLE task_log (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `task_id` int NOT NULL,
  `state_id` varchar(255) NOT NULL,
  FOREIGN KEY (`task_id`) REFERENCES task(`id`),
  FOREIGN KEY (`state_id`) REFERENCES task_log_state(`id`)
);
CREATE INDEX task_log_task_id ON task_log (`task_id`);

CREATE TABLE project_tags (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `project_id` int NOT NULL,
  `tag_id` int NOT NULL,
  FOREIGN KEY (`project_id`) REFERENCES project(`id`),
  FOREIGN KEY (`tag_id`) REFERENCES tag(`id`)
);

CREATE TABLE checklist (
  `id` int NOT NULL PRIMARY KEY,
  `file` varchar(255) NOT NULL,
  `title` varchar(255) NOT NULL,
  `created` timestamp NOT NULL,
  `checked` boolean NOT NULL DEFAULT '0',
  `updated` timestamp DEFAULT NULL
);

-- insert values
INSERT INTO setting (`id`, `name`, `value`)
VALUES
  (1, 'version', 1),
  (2, 'db_created', CURRENT_TIMESTAMP);

INSERT INTO urgency (`id`, `name`, `value`)
VALUES
  (1, 'backlog', 0),
  (2, 'low', 3),
  (3, 'normal', 5),
  (4, 'high', 7),
  (5, 'immediate', 10);

INSERT INTO task_state (name)
VALUES
  ('started'),
  ('paused'),
  ('done');

INSERT INTO task_log_state (name)
VALUES
  ('created'),
  ('restarted'),
  ('paused'),
  ('done'),
  ('duration_updated'),
  ('urgency_changed');

COMMIT;
