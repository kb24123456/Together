-- =============================================================
-- Migration 007: convert_opaque_jsonb_columns_to_text
--
-- 6 个 jsonb 字段被客户端当不透明 JSON 字符串处理（DTO 层声明
-- String?），服务端却声明为 jsonb。当 jsonb 默认值 '{}' / '[]'
-- 触发时，PostgREST 返回 JSON 对象/数组，Swift Decoder 把 {} cast
-- 到 String? 直接抛 decodingError，拖挂整个 catchUp。
--
-- Plan A 从未真正 pull 过 tasks 行（RLS/FK 在前拦住），所以这个 bug
-- 到今天才暴露。解决：字段类型改 text，defaults 同步改字符串；
-- 同时清洗之前 push 成功的 5 行里被 jsonb scalar-string 语义带出的
-- 多余引号（`"[]"` → `[]`）。
--
-- 客户端 TaskDTO/PeriodicTaskDTO 的 encode 路径本来就写 String，
-- 不用改。
-- =============================================================

-- schema
ALTER TABLE tasks ALTER COLUMN repeat_rule            TYPE text USING repeat_rule::text;
ALTER TABLE tasks ALTER COLUMN occurrence_completions TYPE text USING occurrence_completions::text;
ALTER TABLE tasks ALTER COLUMN occurrence_completions SET DEFAULT '{}';
ALTER TABLE tasks ALTER COLUMN response_history      TYPE text USING response_history::text;
ALTER TABLE tasks ALTER COLUMN response_history      SET DEFAULT '[]';
ALTER TABLE tasks ALTER COLUMN assignment_messages   TYPE text USING assignment_messages::text;
ALTER TABLE tasks ALTER COLUMN assignment_messages   SET DEFAULT '[]';

ALTER TABLE periodic_tasks ALTER COLUMN reminder_rules TYPE text USING reminder_rules::text;
ALTER TABLE periodic_tasks ALTER COLUMN reminder_rules SET DEFAULT '[]';
ALTER TABLE periodic_tasks ALTER COLUMN completions    TYPE text USING completions::text;
ALTER TABLE periodic_tasks ALTER COLUMN completions    SET DEFAULT '{}';

-- data cleanup: jsonb scalar strings were cast with their surrounding quotes;
-- strip the accidental wrapping layer on previously pushed rows.
UPDATE tasks SET response_history    = '[]' WHERE response_history    = '"[]"';
UPDATE tasks SET assignment_messages = '[]' WHERE assignment_messages = '"[]"';
UPDATE tasks SET occurrence_completions = '{}' WHERE occurrence_completions = '"{}"';

UPDATE periodic_tasks SET reminder_rules = '[]' WHERE reminder_rules = '"[]"';
UPDATE periodic_tasks SET completions    = '{}' WHERE completions    = '"{}"';
