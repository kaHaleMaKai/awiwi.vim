SELECT
  task.id AS id@n,
  task.title AS title@s,
  task.`date` AS date@s,
  task.state AS state@s,
  GROUP_CONCAT(tag.name) AS tags@ls
FROM
  (SELECT
    id,
    title,
    `date`,
    state
  FROM
    task
  WHERE
    task.id = (SELECT Max(id) FROM task where title = ?)) AS task
  LEFT JOIN
    task_tags
    ON (task.id = task_tags.task_id)
  LEFT JOIN
    tag
    ON (tag.id = task_tags.tag_id)
GROUP BY
  task.id
