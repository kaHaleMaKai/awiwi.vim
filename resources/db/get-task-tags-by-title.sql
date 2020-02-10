SELECT
  tag.id@n,
  tag.name@s
FROM
  tag
  JOIN
    task_tags
    ON (tag.id = task_tags.tag_id)
WHERE
  task_tags.task_id = (SELECT Max(id) FROM task WHERE title = ?)
